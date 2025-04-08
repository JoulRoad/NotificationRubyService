class SessionHandler

  def self.get_api_session_string uuid,device_id,var
    return SessionHandler.get_session_string "user:"+uuid.to_s+":device_id:"+ device_id.to_s + ":mobile_session",var.to_s
  end

  def self.get_session_string session_hash_key,var
    @@session_hash_key =  session_hash_key
    val  = @@app_session[var]
    if !@@is_session_loaded_from_redis
      whole_session = nil

      begin
        as_opts = get_aerospike_session_key_setname(@@session_hash_key)
        whole_session = $as_userDatabase.get(as_opts.merge({bins: "default"})) || {}
      rescue Exception => e
        ::NewRelic::Agent.notice_error(e)
      end
      @@is_session_loaded_from_redis = true
      whole_session.each{ |key,val| @@app_session[key]  = val if !@@app_session.has_key?(key) }
      val =  @@app_session[var]
      return get_yml_val(val)
    else
      return  get_yml_val(val)
    end
    # redis.expire(var,1800) ##Here the session expiry is set - also set it in javascript - JR.Constants.session_expiry
    # ShoppingCart.new
  end

  def self.get_yml_val val
    return val if !val.present?
    begin
      val=YAML.load(val)
      return val
    rescue
      return val
    end
  end

  def self.get_ruid_api_session_string ruid,device_id,var
    return SessionHandler.get_session_string "userRuid:"+ruid.to_s+":device_id:"+ device_id.to_s + ":mobile_session" ,var.to_s
  end

end