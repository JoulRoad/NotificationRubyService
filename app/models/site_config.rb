module SiteConfig
    @config = nil
    @version = nil
    @expiry_time = nil

    def self.reload_config
        @version = $as_userDatabase.get(key: "version", setname: "site_config", bins: "default")
        if @version.blank?
            @version = (Time.now.to_f * 1000).to_i.to_s
            $as_userDatabase.set(key: "version", setname: "site_config", value: {"default" => @version})
    end
    @config = $as_userDatabase.get(key: "data", setname: "site_config", bins: "default")
    @expiry_time = Time.now.advance(seconds:60)
end

    def self.get_config
        if @config.nil? || @version.nil? || @expiry_time.nil?
            reload_config
            return @config
        end
        if @expiry_time < Time.now
            @expiry_time = Time.now.advance(seconds:60)
            new_version = $as_userDatabase.get(key: "version",setname: "site_config", bins: "default")
            reload_config if new_version != @version
        end
        @config
    end
end