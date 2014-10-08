require "bundler/setup"
require "sinatra"
require "sinatra/multi_route"
require "data_mapper"
require "twilio-ruby"
require 'twilio-ruby/rest/messages'
require "sanitize"
require "erb"
require "rotp"
require "haml"
include ERB::Util

set :static, true
set :root, File.dirname(__FILE__)

DataMapper::Logger.new(STDOUT, :debug)
DataMapper::setup(:default, ENV['DATABASE_URL'] || 'postgres://postgres:postgres@localhost/jreyes')

class VerifiedUser
  include DataMapper::Resource

  property :id, Serial
  property :code, String, :length => 10
  property :name, String
  property :phone_number, String, :length => 30
  property :verified, Boolean, :default => false
  property :send_mms, Enum[ 'yes', 'no' ], :default => 'no'

  has n, :messages

end

class Message
  include DataMapper::Resource

  property :id, Serial
  property :body, Text
  property :time, DateTime
  property :name, String

  belongs_to :verified_user

end
DataMapper.finalize
DataMapper.auto_upgrade!

before do
  @twilio_number = ENV['TWILIO_NUMBER']
  @client = Twilio::REST::Client.new ENV['TWILIO_ACCOUNT_SID'], ENV['TWILIO_AUTH_TOKEN']
  puts "num: #{@twilio_number}"
  @mmsclient = @client.accounts.get(ENV['TWILIO_SID'])
  
  if params[:error].nil?
    @error = false
  else
    @error = true
  end

end

def sendMessage(from, to, body, media)
  if media.nil?
    message = @client.account.messages.create(
      :from => from,
      :to => to,
      :body => body
    )
  else
    message = @mmsclient.messages.create(
      :from => from,
      :to => to,
      :body => body,
      :media_url => media,
    )
  end
  puts message.to
end

def createUser(name, phone_number, send_mms, verified)
  user = VerifiedUser.create(
    :name => name,
    :phone_number => phone_number,
    :send_mms => send_mms,
  )
  if verified == true
    user.verified = true
    user.save
  end
  Twilio::TwiML::Response.new do |r|
    r.Message "Awesome, #{name} at #{phone_number} you have been added to the Reyes family babynotify.me account."
  end.text
end

get "/" do
  haml :index
end

get "/signup" do
  haml :signup
end

get '/gotime' do
  haml :gotime
end

get '/notify' do
  p '//////////////////// --------------------'
  p ENV['TWILIO_SID']
  p @client.accounts.get(ENV['TWILIO_SID'])
  @mmsclient.messages.create(
    :from => 'TWILIO',
    :to => '2066505813',
    :body => "Hi Jarod",
  )
end

get '/twilions' do
  haml :twilions
end

get '/success' do
  haml :success
end

get '/kindthings' do
  @messages = Message.all
  haml :messages
end

get '/users/' do
  @users = VerifiedUser.all
  haml :users
end

# Generic webhook to send sms from 'TWILIO'
route :get, :post, '/branded-sms' do
  $DEVICES = {
    "iphone" => {
      "url" => 'https://s3-us-west-2.amazonaws.com/deved/branded-sms_ios7.png',
    },
    "android" => {
      "url" => 'https://s3-us-west-2.amazonaws.com/deved/branded-sms_android.png',
    },
    "windows" => {
      "url" => 'https://s3-us-west-2.amazonaws.com/deved/branded-sms_windows.png',
    }
  }
  @phone_number = Sanitize.clean(params[:From])
  @body = params[:Body].downcase
  deviceList = ($DEVICES.keys).join(',')
  begin
    if deviceList.include?(@body)
      pic = $DEVICES[@body]['url']
      puts pic
      message = @client.account.messages.create(
        :from => 9792726399,
        :to => @phone_number,
        :media_url => pic,
      )
      puts message.to
    else
      @msg = "What kind of device do you have? Reply: 'iphone', 'android', or 'windows' to receive a branded SMS"
      message = @client.account.messages.create(
        :from => 9792726399,
        :to => @phone_number,
        :body => @msg
      )
      puts message.to
      response.text
    end
  rescue
    puts "something went wrong"
  end
  halt 200
end

# Generic webhook to send sms from 'TWILIO'
get '/sms-hook' do
  @user = params[:to]
  if params[:msg].nil?
    @msg = 'Congrats you have just sent an SMS with just a few lines of code.'
  else
    @msg = params[:msg]
  end
  message = @mmsclient.messages.create(
    :from => 'TWILIO',
    :to => @user,
    :body => @msg,
    :media_url => "http://baby-notifier.herokuapp.com/img/sms-pic.png",
  )
  puts message.to
  halt 200
end

# Receive messages twilio app endpoint - inbound
route :get, :post, '/receiver' do
  @phone_number = Sanitize.clean(params[:From])
  @body = params[:Body]
  @time = DateTime.now
  if @phone_number == "+12066505813"
    @users = VerifiedUser.all
    @users.each do |user|
      if user.verified == true
        @phone_number = user.phone_number
        @name = user.name
        @pic = "http://bit.ly/ElliottReyes"

        message = @client.account.messages.create(
            :from => @twilio_number,
            :to => @phone_number,
            :body => @body
          )
        puts message.to
      end
    end
  else
    # Find the user associated with this number if there is one
    @messageUser = VerifiedUser.first(:phone_number => @phone_number)

    # If there is no messageUser lets go ahead and create one
    if @messageUser.nil?
      # If the user did not send a name assume they are a Twilion
      @body = 'Twilion' if @body.empty?
      createUser(@body, @phone_number, 'yes', true)
    else
      # Since the user exists add the message to their profile
      @messageUser.messages.create(
        :name => @messageUser.name,
        :time => @time,
        :body => @body
      )
    end

  end
end

# Register a subscriber through the web and send verification code
route :get, :post, '/register' do
  @phone_number = Sanitize.clean(params[:phone_number])
  
  if @phone_number.empty?
    redirect to("/?error=1")
  else
    if @phone_number.length <= 10
      string = '+1'
      @phone_number = string + @phone_number
    end
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
      message = @client.account.messages.create(
          :from => @twilio_number,
          :to => @phone_number,
          :body => "To complete babynotify.me registration. Your verification code is #{code}."
        )
    end
    erb :register
  rescue
    redirect to("/?error=2")
  end
end

# Send the notification to all of your subscribers
route :get, :post, '/notify_all' do
  @users = VerifiedUser.all
  @baby_name = params[:baby_name]
  @time = params[:time]
  @sex = params[:sex]
  @date = params[:date]
  @weight = params[:weight]

  msg = "Jarod and Sarah have very exciting news! At #{@time} on #{@date} a beautiful little #{@sex} named #{@baby_name} was born. Let the celebrations begin!"
  @users.each do |user|
    @phone_number = user.phone_number
    @name = user.name
    @pic = "http://bit.ly/ElliottReyes"

    messages = ["Hi #{@name}! #{msg}. Picture: #{@pic}", "Mom, Dad and Baby are getting to know each other and aren't available to talk right now. But feel free to respond to this number and they'll get back to you once they're settled at home. In the meantime you can checkout http://losreyeses.tumblr.com/ in the next few days for more pictures."]

    messages.each do |m|
      message = @client.account.messages.create(
        :from => @twilio_number,
        :to => @phone_number,
        :body => m
      )
      puts message.to
    end
  end
  erb :hurray
end

# Endpoint for verifying code was correct
route :get, :post, '/verify' do

  @phone_number = params[:phone_number]
  puts "/////////////////// pn"
  puts @phone_number

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