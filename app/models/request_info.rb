class RequestInfo
  def self.get_AB expName
    if expName.nil?
      return 0
    end
    if !@@ab_data.present?  || @@ab_data[expName].nil?
      return 0
    else
      return @@ab_data[expName].to_i
    end
  end

  def self.get_feature_level_data(feature_name, field_name = nil)
    return if feature_name.blank? || @@features_data.blank? || @@features_data[feature_name].blank?

    if field_name.nil?
      @@features_data[feature_name]
    else
      @@features_data[feature_name][field_name]
    end
  end

  def self.set_feature_level_data(feature_name, opts)
    return if feature_name.nil? || opts.blank? || !opts.is_a?(Hash)

    @@features_data = {} if @@features_data.nil?

    if @@features_data[feature_name].nil?
      @@features_data[feature_name] = opts
    else
      @@features_data[feature_name].merge! opts
    end
  end

end