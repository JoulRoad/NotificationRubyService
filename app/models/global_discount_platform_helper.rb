class GlobalDiscountPlatformHelper
  def get_user_gdp_discount_for_notifications uuid
    User.get_user_global_discount uuid
  end
end