class ApplicationController < ActionController::API

  def has_user_ordered
    return @hasUserOrdered if @hasUserOrdered.present?
    hasOrdered,type=Checkout.determine_has_user_ordered get_ruid,current_user.uuid
    if !hasOrdered.nil?
      @hasUserOrdered = 1
    else
      @hasUserOrdered = 0
    end
    if type == "uuid"
      @hasUuidOrdered = 1
    end
    return @hasUserOrdered
  end


  def get_ruid
    if cookies[:_ruid].nil?
      return ''
    end
    return cookies[:_ruid]
  end

  def current_user
    get_session_var("user_info")
  end

  def get_session_var var,webview=false
    if @sessionLocalHash.nil?
      @sessionLocalHash=Hash.new
    end
    if @sessionLocalHash.has_key? var
      x = @sessionLocalHash[var]
    elsif (is_api_call || webview) && !params[:uuid].nil? && !params[:uuid].empty?
      x=SessionHandler.get_api_session_string params[:uuid],params[:device_id],var
    elsif is_api_call && params[:uuid].nil?
      x=SessionHandler.get_ruid_api_session_string cookies[:_ruid], params[:device_id],var
    else
      x=session[var]
    end
    if var == "product_price_map" && x.present? && x.is_a?(Hash) && x.size > 100
      orig_val = x.deep_dup
      begin
        x = Hash[x.sort_by{|k,v| -(v[3]||0)}.first(100)]
      rescue StandardError => e
        x = orig_val
        exp = Exception.new("Debug Exception : " + e.message)
        exp.set_backtrace(e.backtrace)
        ::NewRelic::Agent.notice_error(exp)
      end
    end
    @sessionLocalHash[var] = x
    x
  end

  def is_api_call
    if request.env["REQUEST_URI"].starts_with? "/api/"
      return true
    else
      return false
    end
  end

end
