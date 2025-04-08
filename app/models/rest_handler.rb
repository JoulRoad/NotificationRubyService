class RestHandler

  @url=""
  @method="GET"
  @sendObj=""
  def initialize initObj
    initObj = HashWithIndifferentAccess.new(initObj)
    @url=initObj["url"]
    @query =  initObj["query"]
    @method=initObj["method"]
    @sendObj=initObj["requestObj"]
    @post_data =  initObj["postData"]
    @content_type = initObj["contentType"]
    @body  = initObj["body"]
    @authorization = initObj["authorizationKey"]
    # if @query.present?
    # 	@query = GlobalDiscountPlatformHelper.update_solr_query_with_gdp_price_ranges @query if @url.to_s.downcase.include?('solr/sitename') ||  @url.to_s.downcase.include?('solr/newscrap')
    # end
  end

  def post_process_response response, hourChange
    hide_prohibited_offers response, hourChange
    update_new_user_discount response
    force_add_exclusive_for_lr_studio response
    #update_response_for_gdp response
    #update_response_for_gst response
    add_gold_price response, hourChange
  end

  def add_gold_price response, hourChange
    if SiteUtils.should_pitch_gold_v2? && response.present? && response.is_a?(Hash) && response['response'].present? && response['response']['docs'].present? && @url.to_s.downcase.include?('solr/sitename')
      Product.update_products_for_gold_pricing(response['response']['docs'], hourChange)
    end
  end

  def update_response_for_gdp response
    response['response']['docs'].each do |product|
      Product.update_products_for_global_discount_percentage product
    end if RequestInfo.get_feature_level_data("gst", "is_gst_on") && response.present? && response.is_a?(Hash) && response['response'].present? && response['response']['docs'].present? && @url.to_s.downcase.include?('solr/sitename')
  end

  def hide_prohibited_offers response, hourChange=nil
    offer_key = "offers_#{Product.getPricingIndex}"
    response['response']['docs'].each do |product|
      product[offer_key] = [] if product[offer_key].present? && (User.offer_not_available?(product[offer_key]) || ["Deals","Brand Deal"].include?(product[offer_key].first))
      product["offers"] = [] if product["offers"].present? && (User.offer_not_available?(product["offers"]) || ["Deals","Brand Deal"].include?(product["offers"].first))
    end if response.present? && response.is_a?(Hash) && response['response'].present? && response['response']['docs'].present? && @url.to_s.downcase.include?('solr/sitename')
  end

  def force_add_exclusive_for_lr_studio response
    response['response']['docs'].each do |product|
      brandid = product["brandid"] || product["brand_id"] rescue nil
      next if product.blank? || brandid.blank? || !Constants::ExclusiveBrands.include?(brandid.to_s)
      product["is_showcased"] = true
    end if response.present? && response.is_a?(Hash) && response['response'].present? && response['response']['docs'].present? && @url.to_s.downcase.include?('solr/sitename')
  end

  def update_new_user_discount response
    response['response']['docs'].each do |product|
      #ProductUtils.get_new_user_price_discount_new product
      #ProductUtils.get_new_user_price_discount product if (Product.should_show_new_user_discount(product) == "1" ) && !product["new_user_discount_price"].present? || (product["new_user_discount_price"].present? && product["new_user_discount_price"] == 0)
      ProductUtils.get_updated_product_price product
    end if response.present? && response.is_a?(Hash) && response['response'].present? && response['response']['docs'].present? && @url.to_s.downcase.include?('solr/sitename')
  end

  # def update_response_for_gst response
  # 	return if (!RequestInfo.get_feature_level_data("gst", "is_gst_on"))

  # 	response['response']['docs'].each do |product|
  # 		Product.remove_gdp_sent_by_service product
  # 	end if response.present? && response.is_a?(Hash) && response['response'].present? && response['response']['docs'].present? && @url.to_s.downcase.include?('solr/sitename')
  # end

  def sendCall
    if @method=="GET"
      return sendGETCall
    elsif @method=="POST"
      return sendPOSTCall
    end
  end

  def send_post_call time_out=1, encoded=false, hourChange=nil
    begin
      ::NewRelic::Agent.add_custom_parameters({ "function" => "send_post_call" })
      ::NewRelic::Agent.add_custom_parameters({ "query" => @query })
      ::NewRelic::Agent.add_custom_parameters({ "post_data" => @post_data })
      ::NewRelic::Agent.add_custom_parameters({ "hourChange" => hourChange})
      ::NewRelic::Agent.add_custom_parameters({ "encoded" => encoded})
      ::NewRelic::Agent.add_custom_parameters({ "url" => @url})
    rescue
    end
    if !encoded
      query = URI.encode(@query) if @query.present?
    else
      if @query.present?
        if hourChange.present?
          add_time_to_query hourChange
        end
        #if RequestInfo.is_api_call && RequestInfo.new_ab_data["AB_59"].present? && RequestInfo.new_ab_data["AB_59"].to_i == 1
        #	change_query_to_new_cutsize_logic
        #end
        query = @query
      end
    end
    uri = URI.parse(@url)
    response=nil
    begin
      http = Net::HTTP.new(uri.host, uri.port)
      http.read_timeout = time_out
      http.use_ssl = (uri.scheme == "https")
      http.start do |http|
        uri.merge!(query) if query.present?
        request = Net::HTTP::Post.new uri.request_uri
        request.add_field('Content-Type', @content_type) if @content_type.present?
        request.add_field('authorization', @authorization)	if @authorization.present?
        request.set_form_data(@post_data) if @post_data.present?
        request.body =  @body if @body.present?
        response = http.request request
      end
    rescue Exception=>e
      Rails.logger.error e.message
      Rails.logger.error e.backtrace.join("\n")
      Rails.logger.error "query:   " + @query.inspect
      Rails.logger.error "post_data:   " + @post_data.inspect
      Rails.logger.error "url:   " + @url.inspect
      ::NewRelic::Agent.notice_error(e)
      response = nil
    end
    if response.present? && response.code == '200' && response.body.present?
      begin
        if hourChange.present?
          response.body = remove_time_from_result response.body,hourChange
          (response.body).gsub! 'not_show', 'show'
        end
        response = JSON.parse(response.body)
      rescue Exception=>e
        response = response.body
      end
      post_process_response(response, hourChange)
      #if response.present? && response.class == Hash && response["responseHeader"].present? && response["responseHeader"]["partialResults"].present? && response['responseHeader']['QTime'].present?
      #	$badQueryLogger.error "Slow query post with time : #{response['responseHeader']['QTime']} and query : #{@query}"
      #  date = Time.now.strftime("%d/%m/%Y/%H")
      #  $redis.hincrby("slow_query_log_post",date, 1)
      #end
    elsif response.present? && response.code == '204'
      response = "success"
    else
      if response.present? && (response.code != '200' || !response.body.present?)
        Rails.logger.error "query:::   " + @query.inspect
        Rails.logger.error "post_data:::   " + @post_data.inspect
        Rails.logger.error "url:::   " + @url.inspect
        Rails.logger.error "response:::   " + response.inspect
        Rails.logger.error "response body:::   " + response.body.inspect
        ::NewRelic::Agent.add_custom_parameters(:request_object => self, :response => response)
        ::NewRelic::Agent.notice_error(e)
      end
      response = nil
    end
    return response
  end

  def send_get_call time_out=1, obj={}
    query = new_encoder(@query,obj) if @query.present?
    uri = URI.parse(@url)

    response=nil
    begin
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.read_timeout = time_out
      http.start do |http|
        uri.merge!(query)
        request = Net::HTTP::Get.new uri.request_uri
        response = http.request request
      end
    rescue Exception=>e
      Rails.logger.error e.message
      Rails.logger.error e.backtrace.join("\n")
      Rails.logger.error "query:   " + @query.inspect
      Rails.logger.error "url:   " + @url.inspect
      ::NewRelic::Agent.add_custom_parameters({:caller => caller[0]})
      ::NewRelic::Agent.notice_error(e)
      response = nil
    end
    if response.present? && response.code == '200' && response.body.present?
      if response.body == "Done"
        response = true
      else
        response = JSON.parse(response.body)
        post_process_response(response, nil)
      end
    else
      if response.present? && ((response.code.present? && !response.code.to_s.starts_with?('20')) || !response.body.present?)
        Rails.logger.error "query:::   " + @query.inspect
        Rails.logger.error "url:::   " + @url.inspect
        Rails.logger.error "response:::   " + response.inspect
        Rails.logger.error "response body:::   " + response.body.inspect
        ::NewRelic::Agent.add_custom_parameters(:request_object => self, :response => response)
        ::NewRelic::Agent.notice_error(e)
      end
      response = nil
    end

    return response
  end

  def send_get_call_solr time_out=1, encoded=false, hourChange=nil
    begin
      ::NewRelic::Agent.add_custom_parameters({ "function" => "send_get_call_solr" })
      ::NewRelic::Agent.add_custom_parameters({ "query" => @query })
      ::NewRelic::Agent.add_custom_parameters({ "hourChange" => hourChange})
      ::NewRelic::Agent.add_custom_parameters({ "encoded" => encoded})
      ::NewRelic::Agent.add_custom_parameters({ "url" => @url})
    rescue
    end
    if !encoded
      query = URI.encode(@query) if @query.present?
    else
      if @query.present?
        if hourChange.present?
          add_time_to_query hourChange
        end
        #if RequestInfo.is_api_call && RequestInfo.new_ab_data["AB_59"].present? && RequestInfo.new_ab_data["AB_59"].to_i == 1
        #	change_query_to_new_cutsize_logic
        #end
        query = @query
      end
    end
    uri = URI.parse(@url)
    response=nil
    begin
      Net::HTTP.start(uri.host, uri.port, :read_timeout => time_out) do |http|
        uri.merge!(query)
        request = Net::HTTP::Get.new uri.request_uri
        response = http.request request
      end
    rescue Exception=>e
      Rails.logger.error "query:::   " + @query.inspect
      Rails.logger.error "response:::   " + response.inspect
      Rails.logger.error "url:::   " + @url.inspect
      ::NewRelic::Agent.add_custom_parameters({:caller => caller[0]})
      ::NewRelic::Agent.notice_error(e)
      response = nil
    end
    if response.present? && response.code == '200' && response.body.present?
      if response.body == "Done"
        response = true
      else
        if hourChange.present?
          response.body = remove_time_from_result response.body,hourChange
          (response.body).gsub! 'not_show', 'show'
        end
        response = JSON.parse(response.body)
        post_process_response(response, hourChange)
        #if response.present? && response.class == Hash && response["responseHeader"].present? && response["responseHeader"]["partialResults"].present? && response['responseHeader']['QTime'].present?
        #	$badQueryLogger.error "Slow query get with time : #{response['responseHeader']['QTime']} and query : #{@query}"
        #	date = Time.now.strftime("%d/%m/%Y/%H")
        #	$redis.hincrby("slow_query_log_get",date, 1)
        #end
      end
    else
      if response.present? && (response.code != '200' || !response.body.present?)
        Rails.logger.error "query::::   " + @query.inspect
        Rails.logger.error "response::::   " + response.inspect
        Rails.logger.error "url::::   " + @url.inspect
        ::NewRelic::Agent.add_custom_parameters(:request_object => self, :response => response)
        ::NewRelic::Agent.notice_error(e)
      end
      response = nil
    end

    return response
  end


  def sendGETCall time_out=1
    str=serializedVal
    if str.present?
      if @url.include? "?"
        str=@url+"&"+str
      else
        str=@url+"?"+str
      end
    else
      str = @url
    end
    str = URI.encode(str)
    uri = URI.parse str
    response=nil
    begin
      Net::HTTP.start(uri.host, uri.port, :read_timeout => time_out) do |http|
        request = Net::HTTP::Get.new uri.request_uri
        response = http.request request
        post_process_response(response, nil) if response.code == 200
      end
    rescue
    end
    return response
  end


  def sendPOSTCall
    uri = URI.parse @url
    response=nil
    begin
      Net::HTTP.start(uri.host, uri.port) do |http|
        request = Net::HTTP::Post.new uri.request_uri
        request.set_form_data(@sendObj)
        response = http.request request
        post_process_response(response, nil) if response.code == 200
        response
      end
    rescue Errno::ECONNREFUSED
      return response
    end
  end

  def serializedVal
    str=""
    if @sendObj.present?
      @sendObj.each do |key,val|
        if str.empty?
          str+=key.to_s+"="+val.to_s
        else
          str+="&"+key.to_s+"="+val.to_s
        end
      end
    end
    return str
  end

  def new_encoder query,obj={}
    query=URI.encode(query)
    if obj.present?
      obj.each do |key,value|
        query.gsub!(key,value)
      end
    end
    return query
  end

  def change_query_to_new_cutsize_logic
    if !(@query.include?("threeQuarterStock_i:") || @query.include?("threeQuarterStock_i%3A")) && @query.include?("11201585")
      @query.gsub!("threeQuarterStock_i", "div(sub(cutSize,mod(cutSize,20)),20)")
    end
  end

  def add_time_to_query hour
    if APP_CONFIG['content'].present?
      fields = APP_CONFIG['content']['fields']
    else
      fields = []
    end
    fields.each do |f|
      if APP_CONFIG["types_dynamic_solr_fields"].include?(f)
        @query.gsub!(f, f+hour+"_f")
      else
        @query.gsub!(f, f+hour)
      end
      if @post_data.present?
        postData = @post_data.to_json
        APP_CONFIG["types_dynamic_solr_fields"].include?(f) ? postData.gsub!(f, f+hour + "_f") : postData.gsub!(f, f+hour)
        @post_data = JSON.parse(postData)
      end
    end
  end

  def remove_time_from_result result, hour
    if APP_CONFIG['content'].present?
      fields = APP_CONFIG['content']['fields']
    else
      fields = []
    end
    fields.each do |f|
      if APP_CONFIG["types_dynamic_solr_fields"].include?(f)
        result.gsub!(f+hour +"_f", f)
      else
        result.gsub!(f+hour, f)
      end
    end
    return result
  end

  def force_add_exclusive_for_lr_studio response
    response['response']['docs'].each do |product|
      brandid = product["brandid"] || product["brand_id"] rescue nil
      next if product.blank? || brandid.blank? || !Constants::ExclusiveBrands.include?(brandid.to_s)
      product["is_showcased"] = true
    end if response.present? && response.is_a?(Hash) && response['response'].present? && response['response']['docs'].present? && @url.to_s.downcase.include?('solr/sitename')
  end

  #solr
  def add_gold_price response, hourChange
    if SiteUtils.should_pitch_gold_v2? && response.present? && response.is_a?(Hash) && response['response'].present? && response['response']['docs'].present? && @url.to_s.downcase.include?('solr/sitename')
      Product.update_products_for_gold_pricing(response['response']['docs'], hourChange)
    end
  end

end