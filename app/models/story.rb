class Story < ActiveRecord::Base
    # def self.set_expiry_for_stories(stories, expiration: APP_CONFIG["story"]["redis_expiry_time"].to_i.days.to_i)
    #     stories.each do |story|
    #       $as_userDatabase.touch(key: story["story_id"], setname: "stories", expiration: expiration)
    #     end
    #   end
    def self.get_stories_from_cache_by_ids(story_ids)
         return {} if story_ids.blank?
        # stories = if RequestInfo.get_feature_level_data("vernacular",:is_translate_on) && I18n.locale.to_s != "en"
        #     as_stories = $as_userDatabase.mget(keys:story_ids,setname:"stories",bins:["default",I18n.locale.to_s])
        #     Translate.merge_translated_values(val:as_stories,type: :story)
        # else
           stories = $as_userDatabase.mget(keys:story_ids,setname:"stories",bins:["default"])
        #end
        Hash[story_ids.zip(stories)].reject { |_, v| v.blank? }
    end

    def self.set_stories_in_cache(story_map)
      # Retrieve expiration from configuration (in seconds)
      expiration = APP_CONFIG["story"]["redis_expiry_time"].to_i.days.to_i
      
      story_map.each do |id, story|
        begin
          $as_userDatabase.set(
            key: id,
            setname: "stories",
            value: { "default" => story },
            expiration: expiration
          )
        rescue Aerospike::Exceptions::Aerospike => e
          Rails.logger.error("Error setting story #{id}: #{e.message}")
          # Reraise the exception unless it's due to a record being too big.
          raise e unless e.message == "Record too big"
        end
      end
      
      # If vernacular translation is enabled and the locale isn't English,
      # merge translated values for each story.
      # if RequestInfo.get_feature_level_data("vernacular", :is_translate_on) && I18n.locale.to_s != "en"
      #   story_data = story_map.values.map { |v| { "default" => v } }
      #   Translate.merge_translated_values(val: story_data, type: :story)
      # end
    end
    
  def self.get_full_stories_by_stories_ids(story_ids,email: nil,basic_info: false,attr[])
    story_data = get_stories_by_story_ids(story_ids,email,basic_info,attr[])
    story_data.each_with_object({}) do |story,stories_map| #each_with_object ek iterator method hota hai ruby mein 
        if story.present? && story['story_id'].present?
            stories_map[story['story_id']] = story
        end
    end
  end
  def self.get_trimmed_stories_from_mongo_by_story_ids(story_ids, email)
    return nil if story_ids.blank? || !story_ids.is_a?(Array)
  
    query_params = { story_ids: story_ids }
    query_string = URI.encode_www_form(query_params)
    
    base_url = ServicesConfig.config['final_user_service_url']
    uri = URI.join(base_url, "story/get_stories_by_id?#{query_string}")
  
    response = nil
    begin
      response = Net::HTTP.get_response(uri)
    rescue Errno::ECONNREFUSED
      return []
    end
  
    if response&.code == "200"
      stories = begin
                  JSON.parse(response.body)
                rescue JSON::ParserError
                  []
                end
      if stories.present?
        stories = stories.map { |story| story }
      end
      stories
    else
      []
    end
  end
  
  
  def self.get_stories_by_story_ids(story_ids, email: nil, basic_info: false, attr: [])
    result = []
    return result if story_ids.blank?
    # Fetch stories from cache
    cached_stories_map = get_stories_from_cache_by_ids(story_ids)
    # Determine which stories are missing from cache
    stories_in_cache = cached_stories_map.keys
    stories_not_in_cache = story_ids.reject { |story| story == "-1" } - stories_in_cache
    if stories_not_in_cache.blank?
      result = stories + (story_ids.last == "-1" ? ["-1"] : [])
    else
      more_stories = Story.get_trimmed_stories_from_mongo_by_story_ids(stories_not_in_cache, email)
      if more_stories.blank?
        result = stories + (story_ids.last == "-1" ? ["-1"] : []) if more_stories.blank?
      else
        result = stories + more_stories + (story_ids.last == "-1" ? ["-1"] : [])
      end
    end
    # Filter out special marker and return only the specified attributes using slice
    result = result.select { |story| story != "-1" }.map { |story| story.slice(*attr) }
    result
  end  
end