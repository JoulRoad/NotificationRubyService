class Trigger < ApplicationRecord
  def get_real_time_notif_data
    triggerClassName = params[:triggerClassName] || ""
    trigger_type = params[:trigger_type] || "VIP"
    trigger_time = params[:trigger_time].present? ? params[:trigger_time].to_i : 1
    uuid = params[:uuid]
    ruid = params[:ruid].to_s
    @userData = (User.get_user_by_uuid(uuid) || {})
    @is_for_notif = true
    offer_data_flag = ($as_userDatabase.get(key: "offer_data_flag", setname: "triggers_config", bins: "default").to_s) == "true"
    gdp_discount = get_user_gdp_discount_for_notifications uuid
    RequestInfo.gdp_discount = (gdp_discount.present? && !User.is_gdp_discount_blocked?(uuid)) ? gdp_discount : 0
    id = params[:product_ids]
    ugc_type = params[:type]
    if ugc_type.present?
      result = get_real_time_scrap_data(trigger_type, trigger_time, id, ugc_type, uuid)
    else
      # end_time/start_time is used to determine which time of activity should be considered
      # start_time is computed based on trigger_time ()
      #       0 => 0.5 hour
      #       1 => 1 hour
      #       2 => 4 hours
      #       3 => 24 hours
      #       4 => 72 hours
      end_time = params[:timestamp].present? ? params[:timestamp].to_i : (Time.now.to_i*1000).to_i
      start_time = (end_time-((Trigger.get_hours_of_activity()[trigger_time] || 1).hours.to_i*1000))
      uuid = params[:uuid]
      activity = Tracking.get_activity(uuid)

      if params[:trigger_type] == "SESSION"
        x = $as_userDatabase.get(key: "#{uuid}_#{trigger_time}", setname: "session_revival_time", bins: "time")
        y = end_time
        do_not_send_flag_type = nil
        if x.present? && y.present? && Time.at(x/1000).to_date === Time.at(y/1000).to_date
          do_not_send_flag_type = ":already_sent:"
        elsif activity.present? && activity["result"].present?
          activity = activity["result"]
          fullActivity = activity.deep_dup
          activity = activity.reject{|y| y["timestamp"][0].to_i < start_time || y["timestamp"][0].to_i > end_time}
          vipactivity = activity.reject{|y| y["type"] != "product"}
          vipactivity = vipactivity.reject{|y| y["action"][0] != "VIEWED"}
          atcActivity = activity.reject{|y| y["action"][0] != "ADDED_TO_CART"}
          if vipactivity.present? || atcActivity.present?
            do_not_send_flag_type = ":vip_atc_present:"
          end
        end
        if do_not_send_flag_type.present?
          ACTIVITY_LOGGER.push(Event.new({:ev_name=>"session_revival_type", do_extra:uuid, df_type: do_not_send_flag_type,  do_type: "end:#{end_time}"}))
          result = { "event_type" => "do_not_send" }
        else
          result = get_session_trigger_data(uuid, trigger_type, trigger_time, start_time, end_time, activity, fullActivity: fullActivity)
        end

      elsif(trigger_type == "VIP") && (trigger_time == 1 || trigger_time == 2 || trigger_time == 4) # Experiment running only for VIP trigger.
        # Filter activity by start/end time
        if activity.present?
          activity = activity["result"].reject{|y| y["type"] != "product"}
          activity.reject!{|y| y["timestamp"][0].to_i < start_time || y["timestamp"][0].to_i > end_time}
        end

        if activity.present?
          # Extract star_cat and star product from user activity
          # If choosen star prod does not have 3/4 variant stock availale or is alreday sent as star product, choose from ml_similar products
          result = get_vip_first_trigger_data(uuid, trigger_type, trigger_time, end_time, activity, triggerClassName: triggerClassName)
        else
          result = get_real_time_notif_data_old_algo(uuid: uuid)
        end
        if triggerClassName.present? && (triggerClassName == "VipCommMobileWeb")
          star_prod = result["product_data"].values[0] rescue nil
          if star_prod.present? && star_prod["isO2OProduct"].present?
            similar_product_ids = ([star_prod["id"]] + result["similar_products"][star_prod["id"]].map{|product| product["id"]} rescue []).uniq.take(3).map {|pid|
              "#{pid}_product"
            }.join(",") rescue ""
            result["landing_url"][star_prod["id"]] = "https://www.limeroad.com/o2o/vip_multiple?ids=#{similar_product_ids}&append_products=true&directviplanding=true&utm_source=notif"
          end
        end
      elsif(trigger_type.start_with?('CTP'))
        if params[:chop_id].present?
          result = get_ctp_first_trigger_data(params[:chop_id], trigger_type, trigger_time, uuid: uuid)
        else
          result = { "event_type" => "do_not_send" }
        end
      else
        result = get_real_time_notif_data_old_algo(uuid: uuid)
      end

    end

    result["eligible_for_whatsapp"] = is_eligible_for_whatsapp(uuid).to_s
    if result["eligible_for_whatsapp"] == "true"
      result["ask_for_checkout_text"] = "Reply Yes to place your order."
    end
    add_personalised_offer_data(result)
    add_cart_data(uuid, result)

    ACTIVITY_LOGGER.push(Event.new({:ev_name=>"get_real_time_notif_data", do_type:"#{trigger_type}", do_val: "#{trigger_time}", do_extra: "#{triggerClassName}", df_type: "#{do_not_send_flag_type}", df_val: result["eligible_for_whatsapp"].to_s}))
    ud={}
    ud=update_db_val_and_db_type ud, ruid, uuid
    ACTIVITY_LOGGER.update_user_data ud
    respond_to do |format|
      format.json {render :json=> result and return}
    end
  end
end

def get_real_time_scrap_data(trigger_type, trigger_time, id, ugc_type, uuid)
  data = {}
  begin
    if id.present? && ugc_type.to_i == 2
      ugc_data = Scrapbook.get_scrap_by_id(id)
      first_item = nil
      if ugc_data.present?
        data['product_ids'] = ugc_data['products'].reject{|product| product["product_id"].blank?}.map{|product| product["product_id"]}.first(6) rescue []
        ugc_data['products'].each do |prod|
          if(prod['product_id'])
            first_item = prod
            break
          end
        end
        if first_item.present?
          data['hero_product'] = first_item
          if first_item["conditions"].present? && first_item["conditions"]["cat_name"].present?
            data['hero_cat'] = first_item['conditions']['cat_name']
          end
        end
        data['ugc_name'] = nil
      end
    elsif id.present? && ugc_type.to_i == 3
      ugc_data = Story.get_story_by_id(id)
      data['hero_cat'] = nil
      cat_data = nil
      if ugc_data.present?
        data['product_ids'] = ugc_data['items'].select{|item| item["item_type"]=="product"}.map{|item| item["id"]}.first(6) rescue []
        first_item = ugc_data['items'][0]
        ugc_data['items'].each do |item|
          if item.present? && ((item['item_type'] == 'product') || ((item['item_type'] == 'scrap') && item['products'].present?))
            first_item = item
            break
          end
        end

        if(first_item.present? && (first_item['item_type'] == 'product'))
          cat_data = Category.get_cat_details(first_item['category'].split(".")[-1]) if first_item['category'].present?
          if cat_data.present?
            data['hero_cat'] = cat_data['name'].downcase
          end
          data['hero_product'] = first_item
        elsif(first_item.present? && (first_item['item_type'] == 'scrap'))
          first_item['products'].each do |prod|
            if(prod['product_id'])
              data['hero_product'] = prod
              if prod["conditions"].present? && prod["conditions"]["cat_name"].present?
                data['hero_cat'] = prod['conditions']['cat_name']
              end
              break
            end
          end
        end
        data['ugc_name'] = ugc_data['story_title']
      end
    end
    if id.blank?
      data = {"status"=>"fail","reason"=>"id not found"}
    elsif ugc_data.blank?
      data = {"status"=>"fail","reason"=>"ugc does not exist"}
    else
      data['ugc_type'] = ugc_data['type']
      data['creator_name'] = ugc_data['name']
      data['creator_email'] = ugc_data['email']
      data['fileidn'] = ugc_data['fileidn']
      end_time = (Time.now.to_i*1000).to_i
      data['landing_url'] = get_landing_url_for_new_algo(end_time)
    end
  rescue Exception => e
    data = {"status"=>"fail","reason"=>"some error occured"}
    ::NewRelic::Agent.notice_error(e)
  end
  return data
end