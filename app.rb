require "bundler/setup"
require "sinatra"
require "sinatra/multi_route"
require "data_mapper"
require "twilio-ruby"
require "sanitize"
require "erb"
require "rotp"
include ERB::Util

DataMapper::Logger.new(STDOUT, :debug)
DataMapper::setup(:default, "sqlite3://#{Dir.pwd}/dev.db")

class VerifiedUser
  include DataMapper::Resource

  property :id, Serial
  property :code, String, :length => 10
  property :name, String
  property :phone_number, String, :length => 30
  property :verified, Boolean, :default => false
  property :send_mms, Enum[ :yes, :no ], :default => :no

end
DataMapper.finalize
DataMapper.auto_upgrade!

before do
  @twilio_number = ENV['TWILIO_NUMBER']
  @client = Twilio::REST::Client.new ENV['TWILIO_ACCOUNT_SID'], ENV['TWILIO_AUTH_TOKEN']

  if params[:error].nil?
    @error = false
  else
    @error = true
  end

end

get "/" do
  erb :index
end

get '/notify' do
  Twilio::TwiML::Response.new do |r|
    r.Say 'The baby is Here!'
  end.text
end

route :get, :post, '/register' do
  @phone_number = Sanitize.clean(params[:phone_number])
  if @phone_number.empty?
    redirect to("/?error=1")
  end

  begin
    if @error == false
      user = VerifiedUser.create(
        :name => params[:name],
        :phone_number => @phone_number,
        :send_mms => params[:send_mms]
      )

      if user.verified == true
        @phone_number = url_encode(@phone_number)
        redirect to("/verify?phone_number=#{@phone_number}&verified=1")
      end
      totp = ROTP::TOTP.new("drawtheowl")
      code = totp.now
      user.code = code
      user.save

      @client.account.sms.messages.create(
        :from => @twilio_number,
        :to => @phone_number,
        :body => "Your verification code is #{code}")
    end
    erb :register
  rescue
    redirect to("/?error=2")
  end
end

get '/users/' do
  @users = VerifiedUser.all
  print @users
  print VerifiedUser.all.count
  erb :users
end

route :get, :post, '/verify' do

  @phone_number = Sanitize.clean(params[:phone_number])

  @code = Sanitize.clean(params[:code])
  user = VerifiedUser.first(:phone_number => @phone_number)
  if user.verified == true
    @verified = true
  elsif user.nil? or user.code != @code
    @phone_number = url_encode(@phone_number)
    redirect to("/register?phone_number=#{@phone_number}&error=1")
  else
    user.verified = true
    user.save
  end
  erb :verified
end