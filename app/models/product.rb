class Product < ApplicationRecord

  def self.getPricingIndex
    time = Time.now.utc
    ans = time.hour*2
    if time.min >= 30
      ans = ans+1
    end
    return ans
  end

  def self.limeroad_discount_breakup_update breakup, key, value
    return if !breakup.is_a?(Array)
    breakup << {"key" => key, "value" => value}
  end

end