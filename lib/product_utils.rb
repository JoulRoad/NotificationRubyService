module ProductUtils

  def self.get_updated_product_price data, auto_price_strike_off_on_vip: false, offers_for_vip: false
    return if data.blank?
    if data.present?
      upid  = data["uiproduct_id"] || data["id"]
      if data["selling_price"].present?
        brand_id = data["brand_id"] || data["brandid"]
        if Constants::LRS_DISCOUNTED_UPIDS.include?(upid) && SiteUtils.discount_for_LRS_upids().to_i > 0 && data["lrs_rounded_pricing_done"].blank?
          discount = SiteUtils.discount_for_LRS_upids().to_i
          discounted_price = (data["selling_price"].to_i * (100-discount)/100).to_i
          data["lrs_rounded_pricing_done"] = true
        end
        discounted_price ||= data["selling_price"].to_i
        discount_for_rounded_price = self.get_logical_rounded_price_discount discounted_price, data
        final_discount_from_sp = (data["selling_price"].to_i - discounted_price) + discount_for_rounded_price
        self.update_pricing_component(data, final_discount_from_sp ,nil,0,'pxd',discount_logic: "round_price") if final_discount_from_sp.present?
        self.set_offer_price_v1 data,offers_for_vip,auto_price_strike_off_on_vip
      end
      if data["variant_list"].present?
        data["variant_list"].each_value do |variant|
          brand_id = data["brand_id"] || data["brandid"]
          if Constants::LRS_DISCOUNTED_UPIDS.include?(upid) && SiteUtils.discount_for_LRS_upids().to_i > 0 && variant["lrs_rounded_pricing_done"].blank?
            discount = SiteUtils.discount_for_LRS_upids().to_i
            variant_discounted_price = (variant["selling_price"].to_i * (100-discount)/100).to_i
            variant["lrs_rounded_pricing_done"] = true
          end
          variant_discounted_price ||= variant["selling_price"].to_i
          variant_discount_for_rounded_price = self.get_logical_rounded_price_discount variant_discounted_price, data
          final_variant_discount_from_sp = (variant["selling_price"].to_i - variant_discounted_price) + variant_discount_for_rounded_price
          self.update_pricing_component(variant,final_variant_discount_from_sp,nil,0,'pxd',discount_logic: "round_price", varient_parent_upid: upid) if variant["selling_price"].present?
          self.set_offer_price_v1 variant,offers_for_vip,auto_price_strike_off_on_vip if offers_for_vip || auto_price_strike_off_on_vip
        end
      end
    end
  end

  def self.get_logical_rounded_price_discount sp , data
    discount_for_rounded_price = 0
    mrp = data["mrp"].present? ? data["mrp"] : data["price"]
    mrp = mrp.to_i if mrp.present?
    # return rounded_price if (sp.blank? || sp < 240) || (mrp.blank? || mrp == 0)
    return discount_for_rounded_price if (sp.blank? || sp <= 249) || (mrp.blank? || mrp == 0)
    last_digit = sp % 10
    return 0 if last_digit == 9
    sell_price = sp.to_i
    # if sell_price.between?(601,608)
    #     rounded_price = -(9-last_digit)
    if last_digit.between?(0,4)
      discount_for_rounded_price = (last_digit+1) #(9-last_digit)
    elsif last_digit.between?(5,8)
      discount_for_rounded_price = last_digit - 9
    end
    if mrp.present? && discount_for_rounded_price.present? && ((mrp < (sp-discount_for_rounded_price)))
      if last_digit < 9
        discount_for_rounded_price = last_digit - 9
      end
    end
    return 0 if discount_for_rounded_price.to_i == 1
    discount_for_rounded_price
  end

  def self.update_pricing_component data,discount_price,second,gst_to_charge,type, discount_logic: "", varient_parent_upid: ""
    is_round_price_pxd = discount_logic.present? && discount_logic == "round_price"
    vip_special_discount = false
    data["discounted"] = "true"
    mrp = data["mrp"].present? ? data["mrp"] : data["price"]
    mrp = mrp.to_i if mrp.present?
    return if mrp.nil? || mrp == 0

    data["price_component"] = "" if data["price_component"].present? && data["price_component"].to_i == 0 && !RequestInfo.is_ios_app
    if mrp < ( data["selling_price"] - discount_price )
      discount_price = data["price_component"].present? ? (-data["price_component"]) : 0
    end
    data["price_component"] = data["price_component"].to_i + discount_price if data["price_component"].present?
    data["price_component"] =  discount_price if data.key?("price_component") && data["price_component"].blank? && discount_price.present? && discount_price.to_i > 0
    if is_round_price_pxd
      data["selling_price"] = data["price_component"].present? ? mrp.to_i - data["price_component"].to_i : ( data["selling_price"] - discount_price )
      data["discount_percent"] = (((mrp - data["selling_price"])/mrp.to_f)*100).round
    else
      data["selling_price"] = data["price_component"].present? ? mrp.to_i - data["price_component"].to_i : ( data["selling_price"] - discount_price )
      data["discount_percent"] = (data["price_component"].present? ) ? ((data["price_component"].to_f/mrp.to_f)*100).ceil : (((mrp - data["selling_price"])/mrp.to_f)*100).ceil
    end
    if !type.blank?
      Product.limeroad_discount_breakup_update data["limeroad_discount_breakup"], type, discount_price
    end

    @special_discount_price = 0

    self.update_special_price_component data, varient_parent_upid, mrp

    @eoss_discount = 0
    self.update_omni_eoss_price_component data, varient_parent_upid, mrp

    discount_price += @special_discount_price if discount_price.present? && @special_discount_price.present? && @special_discount_price > 0
    discount_price += @eoss_discount if discount_price.present? && @eoss_discount.to_i > 0
    data["limeroad_discount"] =  data["limeroad_discount"].present? ? data["limeroad_discount"].to_i + discount_price : discount_price

    if second.present?
      data["new_user_discount_price#{second}"] = discount_price
      data["new_user_discount_price"] += discount_price
    else
      data["new_user_discount_price"] = discount_price
    end
    data["gst_to_charge"] = gst_to_charge
  end

  def self.update_special_price_component data, varient_parent_upid , mrp
    if self.is_vip_special_discount_avl?
      cached_data = RequestInfo.get_feature_level_data("special_vip_disc_data")
      uuid = RequestInfo.current_authenticated_user.present? && RequestInfo.current_authenticated_user.uuid.present? ? RequestInfo.current_authenticated_user.uuid : ""
      if cached_data.blank? && uuid.present?
        cached_data = $as_userDatabase.get(key: uuid, setname: "pxd_spsl", bin: ["upid","timer"])
        if cached_data.present?
          RequestInfo.set_feature_level_data("special_vip_disc_data", cached_data)
        else
          RequestInfo.set_feature_level_data("special_vip_disc_data", "nil")
        end
      end
      id  = (data["uiproduct_id"] || data["id"]) || varient_parent_upid
      should_allow = cached_data.present? && cached_data != "nil" &&  cached_data["upid"].present? && cached_data["timer"].present? &&  cached_data["timer"].to_i > Time.now.to_i
      if should_allow && id.present? && cached_data["upid"].to_s == id.to_s
        special_discount_price = 0
        bucket = RequestInfo.get_AB(Constants::VIPSpecialPriceV2Exp).to_i
        if bucket == 1
          special_discount_price = self.get_rounded_special_discount_price data["selling_price"].to_i
        else
          if data["selling_price"].present? && data["selling_price"].to_i < 500
            special_discount_price = (data["selling_price"].to_i * 0.1).to_i
          else
            special_discount_price = 50
          end
        end
        if special_discount_price.present? && special_discount_price > 0
          @special_discount_price = special_discount_price
          Product.limeroad_discount_breakup_update data["limeroad_discount_breakup"], "vspd", special_discount_price
          data["price_component"] = data["price_component"] + special_discount_price if data["price_component"].present?
          data["price_component"] =  special_discount_price if data["price_component"].blank? && special_discount_price.present?
          data["selling_price"] = data["price_component"].present? ? mrp.to_i - data["price_component"].to_i : ( data["selling_price"] - special_discount_price )
          data["discount_percent"] = (((mrp - data["selling_price"])/mrp.to_f)*100).round
        end
      end
    end
  end

  def self.is_vip_special_discount_avl?
    return false #decided to remove this on 13th Feb cause of high aerospike calls
    (SiteUtils.is_available_for_api?("android", "6.9.2") || RequestInfo.is_touch) && RequestInfo.get_AB("vip_sp_2").to_i == 1 && !SiteUtils.show_new_offer_price_strike_off #TODO changes if required
  end

  def self.update_omni_eoss_price_component data, varient_parent_upid , mrp
    return if RequestInfo.omni_eoss_prod_pxd_map.blank? || !RequestInfo.vmart_store_user.present? || !OmniUtils::EndOfSeasonSale.is_end_of_season_sale_enabled?
    id  = (data["uiproduct_id"] || data["id"]) || varient_parent_upid
    omni_eoss_prod_pxd_map = RequestInfo.omni_eoss_prod_pxd_map
    if omni_eoss_prod_pxd_map.present? && omni_eoss_prod_pxd_map[id].present?
      discount_price = omni_eoss_prod_pxd_map[id]
      if discount_price.present? && discount_price > 0
        @eoss_discount = discount_price
        data["price_component"] = data["price_component"].to_i + discount_price if data["price_component"].present?
        data["price_component"] =  discount_price if data["price_component"].blank? && discount_price.present?
        data["selling_price"] = data["price_component"].present? ? mrp.to_i - data["price_component"].to_i : ( data["selling_price"] - discount_price )
        data["discount_percent"] = (((mrp - data["selling_price"])/mrp.to_f)*100).round
        Product.limeroad_discount_breakup_update data["limeroad_discount_breakup"], "omni_eoss", discount_price
      end
    end
  end

  def self.set_offer_price_v1 data, offers_for_vip = false, auto_price_strike_off_on_vip=false
    begin
      upid  = data["uiproduct_id"] || data["id"]
      session_check = upid.present? && RequestInfo.atc_item_for_auto_strike_through.present? && RequestInfo.atc_item_for_auto_strike_through.to_s == upid.to_s
      normal_offers = offers_for_vip || SiteUtils.show_offer_price_on_nup?
      auto_strike_through = SiteUtils.show_price_strike_off || auto_price_strike_off_on_vip || session_check
      delete_existing_attr = false
      if (normal_offers || auto_strike_through)
        src = (auto_strike_through) ? "price_strike_off" : "normal_offers"
        #if (data["is_sp_striked"].blank? && auto_strike_through) || (data["offer_price"].blank? && normal_offers)
        self.update_offer_price_for_the_user data["selling_price"], data, src, from_vip: offers_for_vip
        data["offer_price"] = "" if data["offer_price"].present? and data["offer_price"].to_i == 0
        if auto_strike_through and data["offer_price"].present? # to cutoff the selling price
          if data["is_sp_striked"].blank?
            offer_discount = (data["selling_price"] - data["offer_price"])
            original_selling_price = data["selling_price"].to_i
            data["selling_price"] = data["offer_price"].to_i
            data["offer_price"] = nil
            #self.update_pricing_component(data,(rounded_price + offer_discount) ,nil,0,'pxd',discount_logic: "round_price") if rounded_price.present?
            data["is_sp_striked"] = original_selling_price
            data["offer_discount_text"] = "Extra #{offer_discount}"
            mrp = data["mrp"].present? ? data["mrp"] : data["price"]
            data["discount_percent"] = (((mrp - data["selling_price"])/mrp.to_f)*100).ceil if data["mrp"].present? && data["mrp"].to_i > data["selling_price"].to_i
          else
            data["offer_price"] = nil # to remove further offer if its sp is already striked
          end
        else
          delete_existing_attr = true if (auto_strike_through || normal_offers) && data["offer_price"].blank?
        end
        #end
      else
        delete_existing_attr = true
      end
      if delete_existing_attr
        if data["offer_price"].present?
          data.delete("offer_price")
        end
        if data["offer_coupon"].present?
          data.delete("offer_coupon")
        end
        if data["offer_discount_text"].present?
          data.delete("offer_discount_text")
        end
        if data["is_sp_striked"].present?
          data["selling_price"] = data["is_sp_striked"]
          data.delete("is_sp_striked")
        end
      end
    rescue
    end
  end

  def self.update_offer_price_for_the_user price, prod_details, src = "normal_offers", from_vip: false
    return if price.blank? or prod_details.blank?
    if prod_details["is_sp_striked"].present?
      price =  prod_details["selling_price"] = prod_details["is_sp_striked"]
      prod_details.delete("is_sp_striked")
    end
    offers = RequestInfo.user_personalized_offers
    return if offers.blank?
    prod_offers = prod_details["offers"]
    prod_offers = [prod_offers] if prod_offers.present? and prod_offers.class == String
    prod_offers = prod_offers.map{|i| i.downcase} if prod_offers.present?
    max_discount = 0
    coupon_code = ""
    is_buyer = RequestInfo.has_user_ordered.to_i == 1
    config = OffersHelper::OfferConfig::OFFER_CONFIG_KEY
    offer_type_key = OffersHelper::OfferType::KEY
    offer_text_key = OffersHelper::OfferConfig::OFFER_TEXT
    discount_list = []
    # Rails.logger.error "upid -> #{prod_details["id"]}  offers -> #{offers.count}"
    offers.each do |offer|
      offer_config = offer.dig(config)
      next if offer_config.blank?
      offer_type = offer_config.dig(offer_type_key)
      offer_text = offer.dig(offer_text_key)
      discount = 0
      constraints = offer_config.dig("constraints")
      if src!= "price_strike_off" and OffersHelper::OfferConfig.is_valid_buy_x_get_y_offer?(offer) and prod_offers.present? and offer_text.present? and prod_offers.include? offer_text
        x = offer_text.split(" ")[1].to_i rescue 0
        y = offer_text.split(" ")[-2].to_i rescue 0
        if x > 0 and y > 0
          discount = (y.to_f/(x+y).to_f)* (price)
        end

      elsif offer_type == OffersHelper::OfferType::CART_DISCOUNT
        constraints = offer_config.dig("constraints")
        next if constraints.blank?
        constraints.each do |constraint|
          if constraint["is_flat_discount"].to_s == "true"
            discount = [discount, (price.to_f >= constraint["min_txn_amount"].to_f ? constraint["discount_val"].to_f : 0 )].max()
          end
        end
      end
      obj = {:discount => discount, :priority => (is_buyer) ? 0 : OffersHelper::OfferConfig::OFFER_PRIORITY_FOR_NB[offer_type] || 0, :coupon_code => offer_config.dig("coupon", "coupon_code"), :offer_price => price - discount.to_f }
      obj[:offer_detail] = offer if from_vip
      discount_list << obj if discount > 0
      if discount > max_discount
        max_discount = discount
        coupon_code = offer_config.dig("coupon", "coupon_code")
      end
    end
    if discount_list.present?
      discount_list.sort_by!{ |h| [h[:priority], h[:offer_price]]}
      offer_price = discount_list.first[:offer_price]
      coupon_code = discount_list.first[:coupon_code]
      prod_details["offer_price"] = offer_price.to_i
      prod_details["offer_coupon"] = coupon_code
      prod_details["vip_offer_details"] = discount_list.first[:offer_detail] if from_vip
    else
      if prod_details.present? && prod_details["offer_price"].present?
        prod_details.delete("offer_price")
      end
    end
    return
  end

end