class UserMailer < ActionMailer::Base
  default :from => "limeroadcom@gmail.com"
  helper_method :current_authenticated_user
  def welcome_email(user)
    @user=user
    mail(:to => 'neeraj.bagdia@gmail.com', :subject => "Your Order has been placed!")
  end
  def current_authenticated_user
    return @user
  end
end