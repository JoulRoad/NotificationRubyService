class User < ActiveRecord::Base
  def self.get_user_by_uuid uuid, with_rank=false, skip_local_cache = false

    begin
      ::NewRelic::Agent.add_custom_parameters({ uuid: uuid })
    rescue
    end

    return if uuid.blank? || uuid.include?('-')

    val = User.get_user_from_local_cache uuid, skip_local_cache
    if val.nil?
      query=URI.encode('get_user_by_uid?user_uid='+uuid)
      url = ServicesConfig.config['user_service_url']
      uri = URI.parse url
      uri = uri.merge!(query)

      begin
        Net::HTTP.start(uri.host, uri.port) do |http|
          request = Net::HTTP::Get.new uri.request_uri
          @response = http.request request
        end
      rescue Exception=>e
        return nil
      end

      return unless response&.status == 200
      val = JSON.parse(response.body)
      val.delete("credits")

      %w[email_id _id].each do |key|
        User.add_user_info_to_cache([val[key], val.to_json]) if val[key].present?
      end


      val["uuid"] ||= val.dig("_id", "$oid")
      val["name"] = User.get_name(val)
      val["name"] = val["name"]&.downcase&.split&.uniq&.join(" ")&.titleize

      add_city_rank_info(val) if with_rank
      User.update_user_pic_origin(val)

    else
      val["uuid"] ||= val.dig("_id", "$oid")
      val["name"] = User.get_name(val)
      val["name"] = val["name"]&.downcase&.split&.uniq&.join(" ")&.titleize

      User.update_user_pic_origin(val)
      add_city_rank_info(val) if with_rank
    end
  end

  def self.get_user_from_local_cache id, skip_local_cache = false
    @@user_data ||= {}

    return @@user_data[id] if @@user_data[id].present? && !skip_local_cache

    data = get_users_from_cache([id])[id]
    return nil if data.blank?

    begin
      data = JSON.parse(data)
    rescue JSON::ParserError
      return nil
    end

    if data.present?
      @@user_data[data["email_id"]&.downcase] = data if data["email_id"].present?
      @@user_data[data.dig("_id", "$oid")] = data if data.dig("_id", "$oid").present?
    end
    data
  end


  def self.get_users_from_cache ids
    retObj = {}
    return retObj if ids.blank?

    userObjs = $as_userDatabase.mget(keys: ids, setname: Constants::AerospikeUserObjectSetname, bins: "default")
    ids.each_with_index do |id, i|
      retObj[id] = userObjs[i]
    end
    retObj

  end

  def self.add_user_info_to_cache hmset_users
    hmset_users.each_slice(2) do |p_key, value|
      $as_userDatabase.set(key: p_key, setname: Constants::AerospikeUserObjectSetname, value: value, expiration: (7.days.to_i))
    end
  end

  def self.add_city_rank_info user
    return if user.blank?
    user_rank_data = $as_nc_userDatabase.get({:key => user["uuid"] || user["_id"]["$oid"], :bins => "default", :setname => "scrapbookers"})
    if user_rank_data.present?
      user_rank_data = JSON.parse(user_rank_data)
      user["cityRank"] = user_rank_data["cityRank"] || "" if user["city"].present? && user["city"] == user_rank_data["city"]
    end
  end

  def self.update_user_pic_origin(user)
    return if user.blank?

    user_pic_keys = ["pic", "tnpic"]
    user_pic_keys.each do |user_pic_key|
      if user.present? && user.dig(user_pic_key).present?
        user[user_pic_key] = ImageLinkHelper.replace_origin(user[user_pic_key])
      end
    end
  end

  #new
  def self.get_user_global_discount id
    begin
      $as_userDatabase.get(key: id, setname: Constants::AerospikeUserObjectSetname, bins: "gdp_disc")
    rescue
      return 0
    end
  end

  def self.is_gdp_discount_blocked? id
    return nil if id.blank?
    return $as_userDatabase.get(key: id, setname: "gdp_blacklist", bin: "blocked")
  end

  def self.get_user_by_email email, with_rank = false
    if email.nil?
      return -1
    end
    if !email.include?('@')
      return User.get_user_by_uuid email, with_rank
    end
    val = User.get_user_from_local_cache email.downcase
    if val.nil?
      semail = CGI.escape(email)
      query = URI.encode('get_user_by_email?')
      query += 'email_id=' + semail
      url = ServicesConfig.config['user_service_url']
      uri = URI.parse url
      uri = uri.merge!(query)
      Net::HTTP.start(uri.host, uri.port) do |http|
        request = Net::HTTP::Get.new uri.request_uri
        @response = http.request request
      end
      if @response.code == "200"
        val = JSON.parse @response.body
        val.delete("credits")
        User.add_user_info_to_cache([val["email_id"].downcase, val.to_json, val["_id"]["$oid"], val.to_json])
        if val["uuid"].nil?
          val["uuid"] = val["_id"]["$oid"]
        end
        val["name"] = User.get_name val
        add_city_rank_info val if with_rank
        User.update_user_pic_origin(val)
        return val
      else
        return -1
      end
    else
      if val["uuid"].nil?
        val["uuid"] = val["_id"]["$oid"]
      end
      val["name"] = User.get_name val
      add_city_rank_info val if with_rank
      User.update_user_pic_origin(val)
      return val
    end


  end
  def self.get_users_by_uuids uuids, with_rank=false
    uuids = uuids.try(:uniq).try(:compact)
    return {} if uuids.blank?
    user_map = User.get_users_from_cache uuids#redis.hmget("userData",uuids)
    users_not_in_redis = uuids - user_map.select{|k,v| v.present?}.keys
    uuids.each { |uuid|
      if user_map[uuid].present?
        begin
          user = JSON.parse(user_map[uuid])
        rescue JSON::ParserError => e
          users_not_in_redis << uuid
          next
        end
        user["uuid"] = user["_id"]["$oid"] if user["uuid"].blank?
        user["name"] = User.get_name user
        user_map[uuid] = user
      end
    }

    if users_not_in_redis.present?
      hmset_users = []
      users_not_in_redis.each do |uuid|
        query=URI.encode("get_user_by_uid?user_uid=#{uuid}")
        url = ServicesConfig.config['user_service_url']
        uri = URI.parse url
        uri = uri.merge!(query)
        begin
          Net::HTTP.start(uri.host, uri.port) do |http|
            request = Net::HTTP::Get.new uri.request_uri
            @response = http.request request
          end
        rescue Exception=>e
          user_map[uuid] = nil
          next
        end
        if @response.code=="200"
          user=JSON.parse @response.body
          user.delete("credits")
          user["uuid"]=user["_id"]["$oid"] if user["uuid"].blank?
          user["name"]=User.get_name user
          User.update_user_pic_origin(user)
          user_map[uuid] = user
          user_json = user.to_json
          hmset_users << [user["email_id"].downcase, user_json, uuid, user_json]
        else
          user_map[uuid] = nil
        end
      end
    end
    User.add_user_info_to_cache hmset_users.flatten if hmset_users.present?
    add_city_rank_info_to_users(user_map.values) if with_rank.present?
    user_map
  end

  def self.add_city_rank_info_to_users users
    return if users.blank?
    user_rank_data = $as_nc_userDatabase.mget({:keys => users.map{|user| user["uuid"] || user["_id"]["$oid"]}, :bins => "default", :setname => "scrapbookers"})
    users.each_with_index { |user, i|
      if user_rank_data[i].present?
        user_rank_data[i] = JSON.parse(user_rank_data[i])
        user["cityRank"] = user_rank_data[i]["cityRank"] || "" if user["city"].present? && user["city"] == user_rank_data[i]["city"]
      end
    }
  end


  def self.get_name user
    if !user["first_name"].present?
      if !user["email_id"].present?
        return Constants::LRUSER
      else
        return user["email_id"].split("@")[0]
      end
    else
      if !user["last_name"].present?
        return user["first_name"].strip
      else
        return user["first_name"] + " " + user["last_name"]
      end
    end
  end

  def self.offer_not_available? offer
    offer_text = offer.is_a?(Array) ? offer[0] : offer
    return true if offer_text.blank?
    offer_text = offer_text.downcase
    (RequestInfo.prohibited_offers||[]).include?(offer_text.downcase)
  end

end

