require "bundler/setup"
require "sinatra"
require "sinatra/multi_route"
require "data_mapper"
require "twilio-ruby"
require 'twilio-ruby/rest/messages'
require "sanitize"
require "erb"
require "rotp"
include ERB::Util

set :static, true
set :root, File.dirname(__FILE__)

DataMapper::Logger.new(STDOUT, :debug)
DataMapper::setup(:default, ENV['DATABASE_URL'] || 'postgres://localhost/baby_notify')

class VerifiedUser
  include DataMapper::Resource

  property :id, Serial
  property :code, String, :length => 10
  property :name, String
  property :phone_number, String, :length => 30
  property :verified, Boolean, :default => false
  property :send_mms, Enum[ 'yes', 'no' ], :default => 'no'

end
DataMapper.finalize
DataMapper.auto_upgrade!

before do
  @twilio_number = ENV['TWILIO_NUMBER']
  @client = Twilio::REST::Client.new ENV['TWILIO_ACCOUNT_SID'], ENV['TWILIO_AUTH_TOKEN']
  @mmsclient = @client.accounts.get('AC648d937704b94309822578b85ff1227f')
  
  if params[:error].nil?
    @error = false
  else
    @error = true
  end

end

get "/" do
  haml :index
end

get '/gotime' do
  haml :gotime
end

get '/notify' do
  Twilio::TwiML::Response.new do |r|
    r.Say 'The baby is Here!'
  end.text
end

get '/hurray' do
  erb :hurray
end

get '/success' do
  haml :success
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
  haml :users
end

route :get, :post, '/notify_all' do
  @users = VerifiedUser.all
  @baby_name = params[:baby_name]
  @time = params[:time]
  @sex = params[:sex]
  @date = params[:date]
  @weight = params[:weight]

  msg = "Jarod and Sarah have very exciting news! At #{@time} on #{@date} a beautiful little #{@sex} named #{@baby_name} was born. Let the celebrations begin!"
  @users.each do |user|
    if user.verified == true
      @phone_number = user.phone_number
      @name = user.name
      if user.send_mms == 'yes'
        message = @mmsclient.messages.create(
          :from => 'TWILIO',
          :to => @phone_number,
          :body => "Hi #{@name}! #{msg}",
          :media_url => "http://www.topdreamer.com/wp-content/uploads/2013/08/funny_babies_faces.jpg"
        )
      else
        message = @client.account.messages.create(
          :from => @twilio_number,
          :to => @phone_number,
          :body => "#{@name}! #{msg}"
        )
      end
      puts message.to
    end
  end
  erb :hurray
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

route :get, :post, '/addPhone' do
  @phone_number = Sanitize.clean(params[:phone_number])
  user = VerifiedUser.create(
    :name => 'Twilion',
    :phone_number => @phone_number,
    :send_mms => 1,
    :verified => true,
  )
  user.save
  Twilio::TwiML::Response.new do |r|
    r.Message 'Awesome, you have been added to the Reyes family babynotify.me account.'
  end.text
end