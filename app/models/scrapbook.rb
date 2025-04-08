class Scrapbook < ApplicationRecord
  def self.get_scrap_by_id scrap_id
    if scrap_id.nil?
      return nil
    end
    scrap_id = scrap_id.split('?')[0]
    if scrap_id.nil?
      return nil
    end
    val = get_scraps_from_cache([scrap_id])[scrap_id]
    if val.nil?
      query=URI.encode('scrapbook/get_new_scrap_by_id?scrap_id='+ scrap_id)
      url = ServicesConfig.config['final_user_service_url']
      uri = URI.parse url
      uri=uri.merge!(query)
      begin
        Net::HTTP.start(uri.host, uri.port) do |http|
          request = Net::HTTP::Get.new URI.encode(uri.request_uri)
          @response = http.request request
        end
      rescue Errno::ECONNREFUSED
        return nil
      end
      if @response.code=="200"
        scrap=JSON.parse @response.body
        if !scrap.nil?
          scrap = Scrapbook.add_user_fields_to_scrap(scrap)
          Scrapbook.save_scraps_in_cache({scrap["scrap_id"]=>scrap.to_json}, expiration: Scrapbook::RedisExpiryPeriod)

        end
        return scrap
      else
        Rails.logger.error @response.code
        Rails.logger.error @response.body
        return nil
      end
    else
      val["type"]="scrap"
      if val["uuid"].nil?
        userData=User.get_user_by_email val["email_id"]
        val["username"]=userData["first_name"]
        val["uuid"]=userData["_id"]["$oid"]
        val["email"]=userData["email_id"]
      end
      val["c_username"]=val["username"]
      val["id"]=val["_id"]["$oid"]
      return val
    end
  end

  def self.get_scraps_from_cache scrap_ids
    return {} if scrap_ids.blank?
    scrap_ids = [scrap_ids] if !scrap_ids.is_a?(Array)
    scrap_ids.compact!
    return {} if scrap_ids.blank?
    scraps = $as_userDatabase.mget(keys: scrap_ids, setname: "scraps", bins: "data") || []

    Hash[scrap_ids.zip(scraps.map do |scrap| if scrap.present?
                                               JSON.parse(scrap)
                                             else
                                               nil
                                             end
    end)].reject{|k,v| v.blank?}

  end

  def self.add_user_fields_to_scrap(scrap, addLove=false, for_profile=nil)
    return scrap if (scrap.blank? || scrap.class != Hash || scrap["email_id"].blank?)

    userData=User.get_user_by_email scrap["email_id"]
    scrap["username"]=userData["first_name"]
    scrap["c_username"]=scrap["username"]
    scrap["uuid"]=userData["_id"]["$oid"]
    scrap["scrap_id"]=scrap["_id"]["$oid"]
    scrap["id"]=scrap["scrap_id"]
    scrap["reviews"] = Reviews.get_reviews "scrap", scrap["id"]
    scrap['reviewCount']= Reviews.get_review_count_by_id "scrap", scrap["id"]
    scrap["name"] = userData["name"]
    if userData["bio"].present?
      userData["bio"]=CGI.unescapeHTML(userData["bio"])
      scrap["bio"] = userData["bio"]
    else
      scrap["bio"] = ""
    end
    scrap["pic"] = userData["pic"]
    scrap["shareUrl"]='/scrap/'+scrap["_id"]["$oid"]
    scrap["email"]=userData["email_id"]
    scrap["type"]="scrap"
    scrap["love_count"]=Love.get_love_of_scrapbook(userData["email_id"], scrap, for_profile) if addLove
    scrap
  end
end

