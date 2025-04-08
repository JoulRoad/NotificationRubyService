class Reviews < ApplicationRecord
  def self.get_reviews type,id, count: nil, fetch_total_count: false
    if id.nil?
      return nil
    end
    get_reviews_from_source(type, id, count: count, fetch_total_count: fetch_total_count)
  end

  def self.get_reviews_from_source type, id, count: nil, fetch_total_count: false
    respMap = get_reviews_for_multiple_from_source(type, [id], count: count, fetch_total_count: fetch_total_count)
    respMap[id]
  end

  def self.get_reviews_for_multiple_from_source type, ids, count: nil, fetch_total_count: false
    retMap = {}
    return retMap if ids.blank? || type.blank?

    setname = AerospikeMigrationHelper.get_reviews_setname type
    ids.each do |id|
      retMap[id] = {}
      retObj = $as_userDatabase.get_by_rank_range(key: id.to_s, setname: setname, rank: 0, bin: "default", count: count, return_type: :key, fetch_size: fetch_total_count)
      if fetch_total_count.present?
        retMap[id]["reviews"] = retObj.first
        retMap[id]["count"] = retObj.last
      else
        retMap[id]["reviews"] = retObj
      end
    end

    reviewsMap = {}
    retMap.each do |id, map|
      reviews = map["reviews"]
      if reviews.blank?
        reviewsMap[id] = nil
      else

        process_review reviews

        if fetch_total_count.present?
          reviews.each do |review|
            review["count"] = map["count"]
          end
        end

        reviewsMap[id] = reviews
      end
    end

    return reviewsMap
  end

  def self.process_review reviews
    ret_reviews = []
    reviews.each_index do |i|
      next if reviews[i].blank?
      reviews[i]=JSON.parse reviews[i]
      reviews[i]["text"]=CGI.unescapeHTML(reviews[i]["text"])
    end
    reviewers = []
    reviews.each do |review|
      reviewers << review["meta"]["uuid"] if review.present?
    end
    user_data_map =  User.get_users_by_uuids reviewers
    reviews.each do |review|
      if review.blank?
        ret_reviews << nil
      else
        user=user_data_map[review["meta"]["uuid"]]
        if user.nil?
          review["meta"]["user_name"]="A User"
        else
          review["meta"]["pic"]=user["pic"]
          review["meta"]["tnpic"]=user["tnpic"]
          review["meta"]["user_name"]=User.get_name user
        end
        ret_reviews << review
      end
    end
    ret_reviews
  end

  def self.get_review_count_by_id type,id
    return 0 if !id.present? || !type.present?
    return get_review_count(type, [id.to_s])[0]
  end

  def self.get_review_count type,ids
    if ids.nil? || ids.empty?
      return nil
    end

    res = []
    setname = AerospikeMigrationHelper.get_reviews_setname type
    ids.each do |id|
      res << $as_userDatabase.map_bin_size(key: id.to_s, setname: setname)
    end
    return res

  end
end