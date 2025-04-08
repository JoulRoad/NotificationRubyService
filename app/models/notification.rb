class Notification < ActiveRecord::Base

  def self.trim_data(data, required_attrs)
    return {} if data.blank? || required_attrs.blank?
    data.slice(*required_attrs)
  end

  def self.delete_pending_notification_variables notifications
    return notifications if !notifications.present?
    final_notifications = []
    notifications.each do |notif|
      result = true
      notif.each_pair do |not_key,not_value|
        res_arr = notif[not_key].scan(/\$\d+/) if notif[not_key].present? && notif[not_key].class==String
        if !res_arr.nil? && res_arr.length>0
          result = false
          break
        end

        flag = 0
        notif[not_key].each do |object|
          object.each_pair do |obj_key,obj_value|
            res_arr = object[obj_key].scan(/\$\d+/) if object[obj_key].present? && object[obj_key].class==String
            if !res_arr.nil? && res_arr.length>0
              flag = 1
              break
            end
          end

        end if notif[not_key].present? && not_key=="letData"
        if flag==1
          result = false
          break
        end

        flag = 0
        notif[not_key].each do |letData|
          letData.each do |object|
            object.each_pair do |obj_key,obj_value|
              res_arr = object[obj_key].scan(/\$\d+/) if object[obj_key].present? && object[obj_key].class==String
              if !res_arr.nil? && res_arr.length>0
                flag = 1
                break
              end
            end
            break if flag==1
          end
        end if notif[not_key].present? && not_key=="letDataList"
        if flag==1
          result = false
          break
        end

        res_arr = notif[not_key]["android"].scan(/\$\d+/) if notif[not_key].present? && not_key=="minVersion" && notif[not_key]["android"].present? && notif[not_key]["android"].class==String
        if !res_arr.nil? && res_arr.length>0
          result = false
          break
        end

        res_arr = notif[not_key]["ios"].scan(/\$\d+/) if notif[not_key].present? && not_key=="minVersion" && notif[not_key]["ios"].present? && notif[not_key]["ios"].class==String
        if !res_arr.nil? && res_arr.length>0
          result = false
          break
        end

      end
      final_notifications.push(notif) if result == true
    end
    return final_notifications
  end

  def fetch_notification_and_trigger_fcm params

    notif_id = params[:id]
    ping = params[:ping]
    uuid = params[:uuid]
    ruid = params[:ruid]
    result = nil

    if uuid.blank?
      respond_to do |format|
        format.json { render :json => {"status" => "fail", "reason" => "no user present"}, :status => 200 and return }
      end
    end


    if ping == "true" && notif_id == "-1"

      is_notif_disabled_right_now = []
      is_notif_disabled_right_now << ($as_userDatabase.exists(redisKey, "polling_notif"))

      if is_notif_disabled_right_now.all?
        respond_to do |format|
          format.json { render :json => {"status" => "fail", "reason" => "disabled for sometime"}, :status => 200 and return }
        end
      end

      #user is not fetched multiple times if already assigned
      current_user ||= User.get_user_by_uuid(uuid)

      if current_user.nil?
        respond_to do |format|
          format.json { render :json => {"status" => "fail", "reason" => "no user present"}, :status => 200 and return }
        end
      end


      token = (Time.now.to_f * 1000).to_i
      notif_tray = fetch_notification_data(current_user, token, uuid, ruid, false)

      val = notif_tray.dig("notifications", 0)

      result = val

      $as_userDatabase.set(key:redisKey , value:"1",setname: "polling_notif", expiration:1800)

      if result.present?
        result["is_fcm_message"] = true
        result["mqtt"] = "polling"
      end
    end

    #only necessary attributes are processed(trim func)
    required_attrs = ["_id", "timestamp", "landingPageUrl", "deep_link_url", "notificationText"]
    respond_to do |format|
      format.json { render json: trim_data(result, required_attrs) }
    end
  end

  def fetch_notification_data(user, token, uuid, ruid, isNotifTab)
    count = 20

    val = $as_userDatabase.by_rank_range_map_bin(key: user["email_id"], setname: "user_emailid_notifications", bin: "default", begin_token: 0, count: count)

    if val.nil?
      val = Array.new
    end

    notificationIds = Array.new
    notificationTimestamps = Array.new
    tmpHash=Hash.new

    val.each_index do |i|
      o =  !val[i][0].is_a?(Hash) ? JSON.parse(val[i][0]) : val[i][0]
      if tmpHash[o["_id"]].nil?
        tmpHash[o["_id"]]=1
        notificationIds.push o["_id"]
        notificationTimestamps.push val[i][1].to_i
      end
    end


    notifications = Array.new
    if notificationIds.size > 0

      val = $as_nc_userDatabase.mget(keys: notificationIds, setname: "user_notification_data", bins: "default")
      if !val.nil?
        val = val.compact
        val.each_index do |i|
          notifications[i]=JSON.parse val[i]
          notifications[i]["_id"] = notificationIds[i]
          notifications[i]["timestamp"] = notificationTimestamps[i]

          notifications[i]["notificationId"] ||= 0
          notifications[i]["tabPriority"] ||= 0

        end
      end
    end

    notifications = Array.new
    notifsAndVariables = $as_nc_userDatabase.get(key: uuid, setname: "notification_variables", bins: "default");
    notifs = Array.new

    if !notifsAndVariables.nil?
      notifIds = Array.new
      notifTimestamps = Array.new
      notifVariables = Array.new
      notifsAndVariables.each do |notificationId, value|
        value = JSON.parse value
        templateId = value['templateId']
        notifIds.push(notificationId + (templateId.nil? ? '' : ":" + templateId.to_s),notificationId)
        notifTimestamps.push(value['timestamp'],value['timestamp'])
        notifVariables.push(value['notificationVars'],value['notificationVars'])
      end

      if notifIds.size > 0
        notificationData = $as_nc_userDatabase.mget(keys: notifIds, setname: "user_notification_data", bins: "default")
        if !notificationData.nil?
          notificationData.each_index do |i|
            if notificationData[i].nil?
              next
            end

            notifs[i] = JSON.parse notificationData[i]
            notifs[i]["timestamp"] = notifTimestamps[i]

            notifs[i]["notificationId"] ||= 0
            notifs[i]["tabPriority"] ||= 0

            if isNotifTab

              ["fullScreenNotif", "notif_ac", "notificationChannelGroup", "notificationChannel","headerSubText"].each do |k|
                notifs[i].delete(k)
              end

            end

            notifVariables[i].each do |key, value|
              User.replace_variables_in_notif_object(notifs[i], '{' + key + '}', value)
            end if !notifVariables[i].nil?
            notifications.push notifs[i]
          end
        end
      end
    end

    begin
      notifications = User.delete_pending_notification_variables notifications
    rescue Exception => e
      ::NewRelic::Agent.notice_error(e)
    end

    notifications = notifications.reject {|x| x["landingPageUrl"].nil? || x["landingPageUrl"].empty?}
    notifications = User.replace_notification_variables notifications, cookies[:_ruid], params[:uuid], user["email_id"], user["name"] if notifications.present? && (defined? cookies) && cookies[:_ruid].present?
    notifications.uniq!

    if isNotifTab
      notifications = notifications.max_by(10) { |x| x['timestamp'] }.sort_by { |x| -x['timestamp'] }
      first2notifs = notifications.first(2).reject {|x| x["timestamp"]<((Time.now.to_f*1000).to_i - 24*60*60*1000) } # clipping age 24 hours

      first2notifs.each do |notification|
        notification["fixed"] = "handpicked";
      end

      if notifications.size > first2notifs.size
        notifications = notifications[first2notifs.size..-1].sort_by { |x| [-x["timestamp"]]  }.first(10-first2notifs.size)
        notifications = first2notifs + notifications
      else
        notifications = first2notifs
      end
    else
      notifications = notifications.sort_by { |x| -x['timestamp'] }.first(10)
    end

    result = Hash.new

    #only the necessary attributes are processed
    required_attrs = ["_id", "timestamp", "landingPageUrl", "deep_link_url", "notificationId"]
    notifications.map! { |notif| trim_data(notif, required_attrs) }


    if notification["landingPageType"] == 25 && !notification["landingPageUrl"].present?
      if notification['letData'].present? && notification['letData'].length > 0 && notification['letData'][0]["landingPageUrl"].present?
        notification["landingPageUrl"] = notification['letData'][0]["landingPageUrl"]
      end
    end

    if notification["landingPageType"] == 25 && !notification["deep_link_url"].present?
      if notification['letData'].present? && notification['letData'].length > 0 && notification['letData'][0]["landingPageUrl"].present?
        notification["deep_link_url"] = notification['letData'][0]["landingPageUrl"]
      elsif notification['landingPageUrl'].present?
        notification["deep_link_url"] = notification['landingPageUrl']
      end
    end

    if notifications.size == 0
      result['bottom_token'] = token
    else
      result['notifications'] = notifications
      result['bottom_token'] = notifications[notifications.size-1]['timestamp']
    end
    result = result.to_json
    begin
      count = 20
      state_regex = Regexp.new('\\{([ ]*)([a-zA-Z0-9_]+)([ ]*)\\}')
      while result[state_regex] != nil && count > 0
        count-=1
        result = result.gsub(result[state_regex],'')
      end
    rescue Exception => e
      ::NewRelic::Agent.notice_error(e)
    end
    result = JSON.parse result
    return result
  end

  def self.replace_notification_variables notifications, ruid, uuid='', email='', user_name='', modulename=''
    return notifications if !notifications.present?

    variables = []

    final_ruid = (ruid.present? ? ruid : "dummy_ruid")
    trim_notif_ids = []
    welcome_series_id = []


    notif_variables = $as_nc_userDatabase.mget(keys: notifications.map{|val| "#{(val["_id"].present? ? val["_id"] : "dummy_id")}:#{final_ruid}"}, setname: "notification_variables", bins: "default")

    templateNames = notifications.map{|val| val["templateName"]}.compact
    notif_templates = templateNames.present? ? $as_userDatabase.mget(keys: templateNames, setname: "notification_templates", bins: 'default') : []
    templateHash = templateNames.each_with_index.inject({nil => nil}) do |hash, tNameIdx|
      tName, idx = tNameIdx
      hash[tName] = notif_templates[idx]
      hash
    end
    variables = notifications.each_with_index.map{|val, i|
      if !notif_variables.present? || (notif_variables.present? && !notif_variables[i].present?)
        notificationTrim = val.values.to_s[/\{.*?\}/]
        if notificationTrim.present? && !notificationTrim.to_s.include?("isnotif") && !notificationTrim.to_s.include?("act_link")  && !notificationTrim.to_s.include?("show")
          trim_notif_ids << val["_id"] if !trim_notif_ids.include?(val["_id"])

        end

      elsif notif_variables.present? && notif_variables[i].present?
        if notif_variables[i].present?
          tmpVar = notif_variables[i]
          tmpVar = tmpVar[0] if notif_variables[i].kind_of?(Array)
        end

        val.values.each_with_index do |notifVal, index|
          variableToChk = notifVal.to_s[/\{.*?\}/]
          if variableToChk.present? && tmpVar.present? && !tmpVar.keys.include?(variableToChk)
            trim_notif_ids << val["_id"]

          end
          if variableToChk.present? && !tmpVar[variableToChk].present?
            welcome_series_id << val["_id"] if !welcome_series_id.include?(val["_id"]) && variableToChk.include?("arpan")
            trim_notif_ids << val["_id"] if !trim_notif_ids.include?(val["_id"]) && variableToChk.include?("landing")

          end
        end
      end
      [notif_variables[i],templateHash[val["templateName"]]]
    }.flatten


    variables.each_index do |i|
      variable_hash = variables[i]
      if (i % 2 == 0)
        if notifications[i/2]["templateName"].present? && notifications[i/2]["templateName"] == "best_selling_html"
          notifications[i/2]["html"] = User.get_best_selling_notification_html_template notifications[i/2]["_id"], ruid, variable_hash
          next
        elsif notifications[i/2]["templateName"].present? && notifications[i/2]["templateName"].starts_with?('App_Referrer')
          notifications[i/2]["html"] = User.replace_referrer_notification_variables uuid, variables[i+1], email, user_name
        else
          notifications[i/2]["html"] = variables[i+1] if variables[i+1].present?
        end
      else
        next
      end
      keys = variable_hash.keys.sort.reverse if variable_hash.present?
      keys.each do |key|
        value = variable_hash[key]
        val = notifications[i/2]
        replace_variables_in_notif_object(val, key, value)
        notifications[i/2] = val
      end if keys.present?
    end
    finalNotifs = []
    notifications.each do |notif|
      finalNotifs << notif if (!welcome_series_id.include?(notif["_id"]) && !trim_notif_ids.include?(notif["_id"]) && notif["landingPageUrl"].present?)
    end
    if modulename.present?
      finalNotifs =  notifications
    end
    return finalNotifs
  end

  def self.replace_notification_html_template_variables notification_id, template_value, ruid
    return template_value if !template_value.present?

    variables_hash=$as_nc_userDatabase.get(key: "#{notification_id}:#{ruid}", bins: "default", setname: "notification_variables")

    if variables_hash.present?
      keys = variables_hash.keys.sort.reverse
      keys.each do |key|
        template_value.gsub!(key,variables_hash[key]) if variables_hash[key].present? && variables_hash[key].class==String
      end
    end
    return template_value
  end

  def self.get_best_selling_notification_html_template notification_id, ruid, variables_hash = nil

    if variables_hash.nil?
      variables_hash = $as_nc_userDatabase.get(key: "#{notification_id}:#{ruid}", bins: 'default', setname: 'notification_variables')
    end

    productids = variables_hash['$1']
    @categoryUrl = variables_hash['$2']

    if productids.present?
      productarray = productids.split(",")
    end

    if productarray.present?
      product_data_hash = Product.get_products_by_product_ids productarray
    end

    @templateData = Array.new
    productarray.each do |val|
      temp = Hash.new
      if product_data_hash[val]["seo"].present? && product_data_hash[val]["seo"]["seoUrl"].present?
        temp['href'] = 'https://www.limeroad.com' + product_data_hash[val]["seo"]["seoUrl"]
      else
        temp['href'] = 'https://www.limeroad.com/products/' + val
      end

      mapped_word = ImageLinkHelper.get_mapped_word "zoom_0"
      temp['image_url'] = "#{ImageLinkHelper.get_base_image_url}/uiproducts/" + val.to_s + "/#{mapped_word}-" + product_data_hash[val]["fileidn"].to_s + ".jpg"
      temp['selling_price'] = product_data_hash[val]['selling_price']
      @templateData.push temp
    end

    template = ERB.new File.read("app/views/notification/best_selling.html.erb"), nil, "%"


    binding_data = binding
    binding_data.instance_variable_set('@templateData',@templateData)

    if @categoryUrl.present?
      binding_data.instance_variable_set('@categoryUrl',@categoryUrl)
    end

    response = template.result(binding_data)
    return response
  end

  def self.replace_referrer_notification_variables uuid, template_value, email, user_name
    return template_value if !template_value.present?
    template_value.gsub!('user_name', user_name)
    templateData = $redis.hget('referred_user', email).split("~")
    template_value.gsub!('referrer_name', templateData[1])
    template_value.gsub!('credit', templateData[2]) if details.present?
    return template_value
  end

  def self.replace_variables_in_notif_object(notifObject, key, value)
    notifObject.each_pair do |not_key, not_value|
      notifObject[not_key].gsub!(key, value) if notifObject[not_key].present? && notifObject[not_key].class==String

      notifObject[not_key].each do |object|
        object.each_pair do |obj_key, obj_value|
          object[obj_key].gsub!(key, value) if object[obj_key].present? && object[obj_key].class==String
        end
      end if notifObject[not_key].present? && not_key=="letData"

      notifObject[not_key].each do |letData|
        letData.each do |object|
          object.each_pair do |obj_key, obj_value|
            object[obj_key].gsub!(key, value) if object[obj_key].present? && object[obj_key].class==String
          end
        end
      end if notifObject[not_key].present? && not_key=="letDataList"

      notifObject[not_key]["android"].gsub!(key, value) if notifObject[not_key].present? && not_key=="minVersion" && notifObject[not_key]["android"].present? && notifObject[not_key]["android"].class==String
      notifObject[not_key]["ios"].gsub!(key, value) if notifObject[not_key].present? && not_key=="minVersion" && notifObject[not_key]["ios"].present? && notifObject[not_key]["ios"].class==String
    end
  end

end