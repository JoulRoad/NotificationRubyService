class NotifBigPic < ActiveRecord::Base
    TEMPLATE_TO_BIG_PIC_TEMPLATE_MAP = {"12012"=>"3", "12018"=>"3", "9424"=>"2", "12016"=>"4", "12019"=>"1", "14148"=>"1", "14150"=>"1", "9713"=>"1", "9764"=>"4", "9763"=>"2", "12009"=>"4", "12010"=>"3", "12008"=>"4", "9488"=>"4", "12007"=>"3", "10694"=>"4", "9975"=>"2", "9977"=>"2", "9697"=>"1", "12021"=>"1", "12022"=>"2", "9976"=>"2", "12020"=>"2", "12023"=>"2", "21396" => "9", "21397"=>"10", "21395" => "9", "21430" => "10", "21399" => "11", "21400" => "12", "21401" => "13", "21403" => "14", "21404" => "15","18070"=>"3","34218"=>"1","21402"=>"13","18660"=>"4","18661"=>"4","18071"=>"1","20373"=>"4","12017"=>"4","20303"=>"2","20299"=>"2","20374"=>"1","20372"=>"13", "61445" => "136", "61448" => "137", "61451" => "138"}
    
    def self.get_pic_template_info(template_id)
        template_info = $as_nc_userDatabase.get(key:40,setname:"notif_bigpic_template_info",bins: "default") || {}
        template_info[image_url]&.gsub("//assets","/assets") #attempts to access the image_url from template_info also we are using &.(safe navigation operator) so if image_url is nil then it will return nil instead of throwing an error
        template_info
    end
    
    def self.get_template_data(trigger_id,template_data)
        template_id = TEMPLATE_TO_BIG_PIC_TEMPLATE_MAP[trigger_id]
        return {} unless template_id.present?
        result = get_pic_template_info(template_id)
        result["variables"]&.each_with_index do |var_data,idx|
        result["variables"][idx]["value"] = template_data[var_data["name"]]
        end
        result
    rescue StandardError => e
        NewRelic::Agent.notice_error(e)
        {}
    end
    end
    
    def self.fetch_big_pic_v3(item_type:nil,item_ids:[],bg_img_url:nil,template_id:nil,vars_map:{},notif_template_id:nil)
        return nil if (item_ids.blank? || template_id.blank?)
        year = Time.now.year
        item_type ||= "product"
        bg_hash = ""
        bg_hash += "_#{DigestHash::MD5.hexdigest(bg_img_url)}" if bg_img_url.present?
        bg_hash += "_#{DigestHash::MD5.hexdigest(vars_map.to_s)}#{year}" if vars_map.present?
        filename = "big_pic_v6_#{item_ids.join("-")}_#{template_id}#{bg_hash}.jpeg"
        img_url = "#{ImageLinkHelper.get_base_image_url(protocol: "http", cdn_no: 0)}/notif_big_pic/#{filename}"
        return img_url if (valid_img_url(img_url))
        if notif_template_id.present? && ["61451", "61448", "61445"].include?(notif_template_id.to_s)
            template_id = notif_template_id
        end
        img_template_id = TEMPLATE_TO_BIG_PIC_TEMPLATE_MAP[template_id.to_s] || template_id.to_s
        img_template_id = img_template_id.sample if img_template_id.is_a?(Array)
        pic_template_info = get_pic_template_info(img_template_id)
        raise StandardError.new("Big Pic info not found in Aerospike") if pic_template_info.blank?
        template_data = {}
        if item_type == "product"
            products_map = Product.get_prouduct_by_product_ids(item_ids, ["fileidn", "zCount"])
            item_ids.each_with_index do |item_id, idx|
                raise "product #{item_id} not found" if products_map[item_id].blank?
                image_url = UiHelper.get_product_image_url(item_id, products_map[item_id]['fileidn'], res_type: 'zoom', img_pos: 0)
                z_count = products_map[item_id]["z_count"].to_i
                for num in 0..[z_count,2].max do
                    template_data["image_url_#{idx}_zoom_#{num}"] = z_count < 3 ? image_url : UiHelper.get_product_image_url(item_id, products_map[item_id]['fileidn'], res_type: 'zoom', img_pos: num)
                  end
                    template_data["product_name_#{idx}"] = img_url
                    template_data["story_img_#{idx}"] = image_url
                    template_data["image_url"] = image_url
                    template_data["image_url_#{idx}"] = image_url
                end
            elsif item_type == "story"
                stories_map = Story.get_story_by_story_ids(item_ids,["fileidn"])
                item_ids.each_with_index do |item_id, idx|
                    raise "story #{item_id} not found" if stories_map[item_id].blank?
                    image_url = "#{ImageLinkHelper.get_base_image_url(cdn_no: 0)}/stories/story_#{item_id}-#{stories_map[item_id]["fileidn"]}.png"
                    template_data["prod_img_#{idx}"] = image_url
                    template_data["story_img_#{idx}"] = image_url
                    template_data["image_url"] = image_url
                    template_data["image_url_#{idx}"] = image_url
                end
            end
            if vars_data.present?
                template_data.merge!(vars_data)
                vars_data["category[0]"] = vars_data["category"] if vars_data["category"].present?
                if vars_data["category[0]"].present?
                    template_data["text"] = vars_data["category[0]"]
                    template_data["text_0"] = vars_data["category[0]"]
                    template_data["category"] = vars_data["category[0]"]
                    template_data["category_0"] = vars_data["category[0"]
                end
            end
        if pic_template_info["variables"].any?  { |var| var["type"] == "text" && ["brand_city", "seller_since", "brand_name", "brand_rating", "product_sold", "credit_amount"].include?(var["value"] || var["name"]) }
            prodData = get_products_by_product_ids([item_ids.last])[item_ids.last]
            if prodData.present?
             brand_attrs = {
            "brand_name"    => prodData["brand_name"],
            "brand_id"      => prodData["brand_id"],
            "vendor_id"     => prodData["vendor_id"],
            "brand_rating"  => getBrandRating(prodData["vendor_id"]),
            "products_sold" => $as_userDatabase.get(key: prodData["brand_id"], setname: "brand_cat_nmv_scores", bins: "brandItemSold").to_i,
            "credit_amount" => (SiteConfig.get_config["atc_drop_lr_credits_amount"] || 1000)
            }
             template_data.merge!(brand_attrs)
            end
        end
        image = create_big_pic_v3 bg_img_url, pic_template_info, template_data
        file_path= "/tmp/#{filename}"
        image.write(file_path)
        return upload_big_pic(filename, file_path)
    end
    def self.create_big_pic_v3(bg_img_url, pic_template_info, template_data)
        # Choose background image URL: provided bg_img_url if present, otherwise use the one in pic_template_info.
        bg_img = bg_img_url.presence || pic_template_info["img_url"]
        image = fetch_pic_from_url(bg_img, 3)
      
        # Resize image if dimensions don't match template dimensions.
        if (pic_template_info["img_height"].present? && image.rows != pic_template_info["img_height"]) ||
           (pic_template_info["img_width"].present? && image.columns != pic_template_info["img_width"])
          image.resize!(pic_template_info["img_width"], pic_template_info["img_height"])
        end
      
        pic_template_info["variables"].each do |var|
          puts "Variable -> #{var['name']}"
          case var["type"]
          when "text"
            text_key = var["value"] || var["name"]
            text = template_data[text_key].to_s
            text = "Naina" if text_key == "editor" && text.blank?
            raise StandardError, "No value found for variable #{text_key}" if text.blank?
      
            draw = Magick::Draw.new
            draw.font = File.expand_path("../../app/assets/fonts/#{var['font']}", __dir__)
            draw.pointsize = var["textsize"]
            xoffset = var["horizontal_begin"]
            yoffset = var["vertical_begin"]
      
            if var["alignment"] == "center"
              draw.gravity = Magick::CenterGravity
              draw.align = Magick::CenterAlign
              xoffset = var["center_x"] || ((var["horizontal_begin"] + var["horizontal_end"]) / 2)
              yoffset = var["center_y"] || (((var["vertical_begin"] + var["vertical_end"]) / 2) + var["textsize"] / 2 - 1)
            elsif var["alignment"] == "right"
              draw.align = Magick::RightAlign
            end
      
            draw.fill = var["color"] if var["color"].present?
      
            if var["horizontal_end"].present? && var["horizontal_begin"].present?
              metrics = draw.get_type_metrics(text)
              box_width = metrics.width
              while box_width > (var["horizontal_end"] - var["horizontal_begin"])
                var["textsize"] -= 1
                draw.pointsize = var["textsize"]
                metrics = draw.get_type_metrics(text)
                box_width = metrics.width
              end
            end
      
            image.annotate(draw, 0, 0, xoffset, yoffset, text)
      
          when "image"
            unless template_data.key?(var["name"])
              raise StandardError, "No image url given. #{var['name']} variable missing."
            end
            img_url = template_data[var["name"]]
      
            unless valid_image_url(img_url)
              if (matched_data = /https?:\/\/img[0123]\.junaroad\.com\/stories\/story_([a-zA-Z0-9]*)-([0-9]*)\.png/.match(img_url))&.captures&.all?(&:present?)
                story_id, fileidn = matched_data
                Story.create_image({ "_id" => { "$oid" => story_id }, "fileidn" => fileidn })
                sleep 0.5
              end
      
              if (matched_data = /https?:\/\/img[0123]\.junaroad\.com\/stories\/story_v3_([a-zA-Z0-9]*)-([0-9]*)\.png/.match(img_url))&.captures&.all?(&:present?)
                story_id, fileidn = matched_data
                Story.create_image_v3({ "_id" => { "$oid" => story_id }, "fileidn" => fileidn })
                sleep 0.5
              end
      
              if (matched_data_zoom = /https?:\/\/img[0123]\.junaroad\.com\/uiproducts\/(.*)\/zoom_[1234]-(.*).jpg/.match(img_url))&.captures&.all?(&:present?)
                img_url = UiHelper.get_product_image_url(matched_data_zoom[0], matched_data_zoom[1], res_type: 'zoom', img_pos: 0)
              end
            end
      
            img = nil
            begin
              img = fetch_pic_from_url(img_url, 3) if valid_image_url(img_url)
            rescue StandardError => e
              ::NewRelic::Agent.add_custom_parameters({ img_url: img_url.to_s })
              ::NewRelic::Agent.notice_error(e)
              return nil
            end
      
            return nil if img.blank?
      
            img.resize_to_fit!(var["width"], var["height"])
            horizontal_begin = var["horizontal_begin"] + ((var["horizontal_end"] - var["horizontal_begin"] - img.columns) / 2)
            vertical_begin = var["vertical_begin"] + ((var["vertical_end"] - var["vertical_begin"] - img.rows) / 2)
            image.composite!(img, horizontal_begin, vertical_begin, Magick::AtopCompositeOp)
          end
        end
        image
      end      
    
      def self.upload_big_pic(filename, file_path)
        # Create a new uploader instance and override its store directory.
        uploader = ScratchpadUploader.new
        uploader.define_singleton_method(:store_dir) { "notif_big_pic/" }
      
        # Read the file contents in binary mode.
        file_contents = File.read(file_path, mode: "rb")
        encoded_file = Base64.encode64(file_contents)
      
        # Upload the file using the uploader.
        big_pic_url = uploader.upload_scratchpad(filename, encoded_file)
        raise StandardError, "Could not upload pic to S3." if big_pic_url.blank?
      
        # Delete the local file after upload.
        File.delete(file_path)
      
        # Return the URL to the uploaded picture.
        "#{ImageLinkHelper.get_base_image_url(protocol: "http", cdn_no: 0)}/notif_big_pic/#{filename}"
      end

      def self.fetch_pic_from_url(image_url, retry_count = 0)
        require 'open-uri'
        begin
          # Fetch the image blob from the URL with SSL verification disabled.
          img_blob = URI.open(image_url, ssl_verify_mode: OpenSSL::SSL::VERIFY_NONE).read
          # Convert the blob into a Magick::Image object.
          img = Magick::Image.from_blob(img_blob).first
        rescue StandardError => e
          if retry_count.positive?
            sleep 0.5
            # Apply temporary change to the URL and retry.
            image_url = image_url.gsub("n-img", "img")
            img = self.fetch_pic_from_url(image_url, retry_count - 1)
          else
            raise e
          end
        end
        img
      end

end