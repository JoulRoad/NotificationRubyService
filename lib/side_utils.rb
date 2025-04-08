module SideUtils

  def self.discount_for_LRS_upids()
    bucket = RequestInfo.get_AB(Constants::LRSDicountedPriceExp).to_i
    case bucket
    when 1
      30
    else
      0
    end
  end

  def self.show_offer_price_on_nup?
    return true if self.qr_code_timer_promo_note?({})
    # experiment_name = Constants::PrepaidNudgeExp
    # experiment_2 = Constants::StrikeOffAutoApplyExp
    exclude_gold = !RequestInfo.is_active_gold_member
    return exclude_gold #&& !(RequestInfo.get_AB(experiment_name).to_i == 1 && RequestInfo.get_AB(experiment_2).to_i == 1)
  end

  def self.show_price_strike_off strike_off_mandatory:true
    return false
  end

  def self.should_pitch_gold_v2?
    gold_v2_config = RequestInfo.get_feature_level_data("site_config", "gold_pitch_v2")
    return gold_v2_config.present? && gold_v2_config["show_pricing"].to_i == 1 && SiteUtils.is_available_for_api?("android", "6.0.4")
  end

  def self.is_available_for_api? os, version
    if RequestInfo.is_api_call && (Gem::Version.new(RequestInfo.app_version) >= Gem::Version.new(version))
      return ((os == "android") && RequestInfo.is_android_app) || ((os == "ios") && RequestInfo.is_ios_app)
    else
      return false
    end
  end

end