class Love < ApplicationRecord
  def self.get_love_of_scrapbook emailC, scrap, for_profile = nil
    if emailC.nil? || scrap.nil? || scrap["scrap_id"].nil?
      return nil
    end
    scrapId = scrap["scrap_id"].to_s
    res = $redis_slave.hget('scb:' + emailC, scrapId)
    if res.present?
      realCount = res.to_i
    else
      realCount = 0
    end
    fakeCount = 0
    realCount = (realCount < 5 ? 0 : realCount) if !for_profile.present?
    return (realCount + fakeCount).to_s
  end

end