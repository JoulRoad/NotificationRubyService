class NotificationController < ApplicationController
    def fetch_big_pic_v3
      result = {}
      notif_template_id = params[:notif_template_id]
      template_id = params[:template_id]
      item_ids = params[:item_ids]
      if item_ids.is_a?(String)
        item_ids = item_ids.split(",")
      end
      item_type = params[:item_type] || "product"
      bg_img_url = params[:bg_img_url]
      vars_map = params[:vars_map] || {}
      if vars_map.is_a?(String)
        begin
          vars_map = JSON.parse(vars_map)
        rescue Exception => e
          vars_map = {}
        end
    end
    vars_map.each do |k, v|
      v.upcase!
    end
    if item_ids.size == 1 && item_type == "product" && vars_map.blank?
      prod = Product.get_uip_static_data(item_ids[0])
      prod = JSON.parse(prod)
      if prod.present?
        vars_map["category[0]"] = prod["classification"].split("/").last.humanize.upcase
        price_info = Product.get_specific_product_price_info(item_ids[0],Product.getPricingIndex)
        if price_info.present && prod["base_variant_id"].present && price_info[prod["base_variant_id"]].present
          vars_map["mrp_0"] = price_info[prod["base_variant_id"]]["mrp"] if price_info[prod["base_variant_id"]]["mrp"].present?
          vars_map["price_0"] = price_info[prod["base_variant_id"]]["sp"] if price_info[prod["base_variant_id"]]["sp"].present?
        end
      end
  end
      url = NotifBigPic.fetch_big_pic_v3(notif_template_id, template_id, item_ids, item_type, bg_img_url, vars_map)
      ACTIVITY_LOGGER.push(
      Event.new({
        ev_name: "fetch_big_pic_v3",
        df_val:  result.to_json,
        do_val:  {
          item_type:  item_type,
          item_id:    item_ids.join(","),
          bg_img_url: bg_img_url,
          vars_map:   vars_map,
          template_id: template_id
        }.to_json
      })
    )
    render plain: url
  end
end