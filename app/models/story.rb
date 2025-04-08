class Story < ApplicationRecord
  def self.get_story_by_id(story_id, email = nil, items_paginate = -1, offset = 0, is_edit = nil, user_uuid = nil, currHour = 24, priceRange = nil, skip_cache = false, action: nil, is_scratch_pad: false, dont_skip_scrap: false, fixed_product_ids: [])
    default_response = {}
    return default_response if story_id.blank? || story_id.to_i == -1
    story_id = story_id.split("?")[0]
    story_data = skip_cache ? nil : Story.get_story_from_cache_by_id(story_id)
    if story_data.blank?
      query = "story/get_story_by_id?story_id=#{story_id}"
      uri = ServicesConfig.config['final_user_service_url']
      rest_handler = RestHandler.new({ "url" => uri, "query" => query })
      story_data = rest_handler.send_get_call(0.5)
      if story_data.present?
        story_data["items"] = story_data["items"].take(100) if story_data["items"].present?
        Story.set_story_in_cache(story_data['_id']['$oid'], story_data.to_json, expiration: APP_CONFIG["story"]["redis_expiry_time"].to_i.days.to_i)
      else
        return default_response
      end
    else
      story_data = JSON.parse story_data
    end
    if story_data.present? && story_data["items"].present? && story_data["items"].size > 100
      story_data["items"] = story_data["items"].take(100)
      Story.set_story_in_cache(story_id, story_data.to_json, expiration: APP_CONFIG["story"]["redis_expiry_time"].to_i.days.to_i)
    end

    firstProduct = catid = catInitial = ""
    reOrdereing = true
    firstProduct = story_data['items'][0]["item_id"] if story_data.present? && story_data['items'].present? && story_data['items'][0].present?
    if story_data['items'].present? && story_data['items'][0].present?
      itms = story_data['items']
      itms.each do |it|
        if it['item_type'] == "scrap"
          reOrdereing = false
          break
        end
        if it['item_type'] == "product"
          catid = it['item_category'] if !catid.present?
        end
      end
    end
    # catid = story_data['items'][0]['item_category'] if story_data['items'].present? && story_data['items'][0].present? && story_data['items'][0]['item_type'] == "product"
    if catid.present?
      if catid.include?("[")
        catid = JSON.parse(catid)
        catid = catid[0]
      end
      catInitial = catid
      catid = catid.split(".")[-1] if catid.present?
    end
    priceScores = User.get_cat_price_scores user_uuid, catInitial
    if RequestInfo.if_slow_internet && !user_uuid.present?
      quizCookie = RequestInfo.kyc_quiz_cookie
      occasion = quizCookie[:occasion]
      price = quizCookie[:price]
      if occasion.present? && price.present?
        priceScores = get_logged_out_user_catprice occasion, price
        # Rails.logger.error "priceScores :#{priceScores}"
      end
    end
    priceScores = [] if ((user_uuid.present? && story_data["uuid"].present? && story_data["uuid"] == user_uuid) || (!reOrdereing))
    if priceRange.present?
      priceScores = priceRange
    end
    priceScores = priceScores.take(2)

    stories_items_count = story_data["items"].count { |item| item["item_type"].to_s == "product" }

    if SiteUtils.should_remove_oos_upids_and_reorder_by_rating?
      ProductVisibilityFilter.filter_visible_products_in_story(story_data["items"])
    else
      story_data = shuffle_story_data story_data, priceScores, currHour, action: action, is_scratch_pad: is_scratch_pad, fixed_product_ids: fixed_product_ids
      # if story_data["items"].present? && firstProduct.present? && !story_data["items"].empty?
      #     firstItem = story_data["items"].find{|h| h['item_id'] == firstProduct}
      #     story_data["items"].unshift firstItem
      #     story_data["items"] = story_data["items"].compact.uniq {|e| e['item_id'] }
      # end
    end

    extra_params = {
      "total_upids" => stories_items_count,
      "available_upids" => story_data["items"].count { |item| item["item_type"].to_s == "product" }
    }
    ACTIVITY_LOGGER.push(Event.new({ :ev_name => "stories_hygiene", :do_type => "stories", :do_val => "#{story_id}", :do_extra => extra_params }))

    story_data['item_count'] = story_data['items'].length
    if offset == 0
      story_data = Story.add_user_fields_to_story(story_data, true)
      story_data['story_tags'] = Story.get_tag_arr story_data['story_tags']
      story_data['story_title'] = CGI.unescapeHTML(story_data['story_title']) rescue story_data['story_title'] if story_data['story_title'].present?
      story_data['share_msg'] = CGI.unescapeHTML(story_data['share_msg']) rescue story_data['share_msg'] if story_data['share_msg'].present?
      story_data['remaining_story_item_ids'] = Story.get_story_items story_data['items'][items_paginate..-1] if items_paginate != -1
    end
    story_data["story_color"] = "ffffff"
    story_data["items"].shift if story_data["items"].present? && story_data['items'][0].present? && story_data['items'][0]['item_type'] != "product" && !RequestInfo.is_api_call && dont_skip_scrap.to_s == "false"
    story_data['items'] = story_data['items'][offset, items_paginate] if items_paginate != -1 && is_edit.nil?
    story_data = Story.add_item_info(story_data)
    story_data = Story.fill_in_scrap_data story_data, email
    story_data = Story.add_story_item_dyn_data(story_data, email)
    if story_data["items"].present? && SiteUtils.should_show_order_count_and_rating_on_story_vip?
      Product.add_rating_to_products story_data["items"]
      Product.add_order_count_to_products story_data["items"]
    end

    story_data['hero_product_category'] = (story_data['items'][0]['category'] if story_data['items'].present? && story_data['items'][0].present? && story_data['items'][0]['item_type'] == "product") || ""
    return story_data
  end

  def self.get_story_from_cache_by_id story_id
      $as_userDatabase.get(key: story_id, setname: "stories", bins: "default")
  end

end