class NotificationController < ApplicationController
  def fetch_notification_and_trigger_fcm
    result = Notification.fetch_notification_and_trigger_fcm params
    render json: result
  end
end