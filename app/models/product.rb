class Product < ActiveRecord::Base
    def self.getPricingIndex
        time = Time.now.utc
        time.hour * 2 + (time.min >= 30 ? 1 : 0)
      end
    
    #   def Product.find_prods_in_cache(ids, price_interval)
    #     ids.each_with_object({}) do |id, ret_map|
    #       key = RequestInfo.if_vernacular && I18n.locale.to_s != "en" ? 
    #               "prodDataWithPrice:#{id}:#{price_interval}:#{I18n.locale}" : 
    #               "prodDataWithPrice:#{id}:#{price_interval}"
    #       ret_map[id] = $lru_cache[key] if $lru_cache[key].present?
    #     end
    #     Hash[story_ids.zip(stories)].reject { |_, v| v.blank? }
    #   end
    def self.getBrandRating(vendor_id)
        return nil unless vendor_id.present?
        begin
            json = VendorScore.get_vendor_score(vendor_id)
            return nil unless json && json["scores"] && json["scores"]["AggregatedScore"]
            score = json["scores"]["AggregatedScore"].to_f
            return nil if score < 0
            score.round(1)
            rescue StandardError => e
                Rails.logger.error(e.inspect)
            nil
        end
    end
    def self.get_products_details_with_price_from_source(ids, price_interval)
        ret_hash = if AerospikeMigrationHelper.switchProductData?
                     if RequestInfo.get_feature_level_data("vernacular", :is_translate_on) && I18n.locale.to_s != "en"
                       result = $as_userDatabase.mget(
                         keys: ids,
                         setname: "upid_data",
                         bins: ["static", "price_#{price_interval}", "qualityRating", I18n.locale.to_s, "static_video", "o2o_video", "feedbackUpid"]
                       )
                       Translate.merge_translated_values(val: result, type: :product)
                     else
                       $as_userDatabase.mget(
                         keys: ids,
                         setname: "upid_data",
                         bins: ["static", "price_#{price_interval}", "qualityRating", "static_video", "o2o_video", "feedbackUpid"]
                       )
                     end
                   end
      
        tmp_arr = if ret_hash.blank?
                    []
                  else
                    ret_hash.inject([]) do |arr, map|
                      arr << (map.present? ? [
                        map["static"],
                        map["price_#{price_interval}"],
                        map["qualityRating"],
                        map["static_video"],
                        map["o2o_video"],
                        map["feedbackUpid"]
                      ] : [nil, nil, nil, nil, nil, nil])
                    end.flatten
                  end
      
        ids.each_with_index.each_with_object({}) do |(id, index), ret_map|
          base = Product::ProductSetnameFieldCount * index
          quality = { "quality" => tmp_arr[base + 2] }
          ret_map[id] = [
            tmp_arr[base],
            tmp_arr[base + 1],
            quality.to_json,
            tmp_arr[base + 3],
            tmp_arr[base + 4],
            tmp_arr[base + 5]
          ]
        end
      end
      def self.get_products_by_product_ids(arr, required_attrs = [], quality = false)
        return {} if arr.blank?
        
        response = {}
        self.class.trace_execution_scoped(["product/get_products_by_product_ids"]) do
          idx = getPricingIndex
          ret = Product.get_products_details_with_price(arr, idx.to_s)
          
          response.merge!(arr.each_with_index.each_with_object({}) do |(id, index), hash|
            base = Product::ProductSetnameFieldCount * index
            static_video_data = ret[base + 3].present? ? JSON.parse(ret[base + 3]) : {}
            
            data = Product.parse_and_process_data(
              ret[base],
              idx,
              JSON.parse(ret[base + 1] || "{}"),
              quality ? JSON.parse(ret[base + 2] || "{}") : {}
            )
            data = data.merge(static_video_data) if static_video_data.present?
            data["rating"] = data["qualityRating"] = data["quality"] if data["quality"].present?
            
            hash[id] = data.present? ? (required_attrs.any? ? required_attrs.each_with_object({}) { |attr, h| h[attr] = data[attr] } : data) : {}
          end)
        end
        
        response
      end
      def self.get_products_details_with_price(ids, price_interval)
        # prod_map = find_prods_in_cache(ids, price_interval)
        # remaining_ids = ids - prod_map.keys
        # if remaining_ids.present?
          prod_map_src = get_products_details_with_price_from_source(remaining_ids, price_interval) || {}
        #   write_prods_to_cache(prod_map_src, price_interval)
        #   prod_map.merge!(prod_map_src)
        # end
        ids.map { |id| prod_map[id] }.flatten
      end
      
      def Product.get_product_details_with_price(id, price_interval)
        get_products_details_with_price([id], price_interval)
      end
      
      def self.get_uip_static_data(product_id)
        ret_arr = get_product_details_with_price(product_id, getPricingIndex)
        ret_val = ret_arr[0]
        return ret_val if ret_arr.size <= 4
      
        # Attempt to parse JSON for the various parts; if parsing fails, default to {}
        ret_arr1 = JSON.parse(ret_arr[0]) rescue {}
        ret_arr2 = JSON.parse(ret_arr[2]) rescue {}
        ret_arr3 = JSON.parse(ret_arr[3]) rescue {}
        ret_arr4 = JSON.parse(ret_arr[4]) rescue {}
        ret_arr5 = JSON.parse(ret_arr[5]) rescue nil
      
        if [ret_arr1, ret_arr2, ret_arr3, ret_arr4].all? { |part| part.is_a?(Hash) }
          ret_val = ret_arr1.merge(ret_arr2).merge(ret_arr3).merge(ret_arr4).to_json
        end
      
        if ret_arr5.is_a?(Hash)
          ret_val = JSON.parse(ret_val).merge(ret_arr5).to_json
        end
      
        ret_val
      end
                
end