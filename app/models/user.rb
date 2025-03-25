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
end




