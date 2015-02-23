require "bundler/setup"
require "sinatra"
require "sinatra/multi_route"
require "data_mapper"
require "pusher"
require "erb"
require "rotp"
require "haml"
require "json"
include ERB::Util

set :static, true
set :root, File.dirname(__FILE__)

DataMapper::Logger.new(STDOUT, :debug)
DataMapper::setup(:default, ENV['DATABASE_URL'] || 'postgres://postgres:postgres@localhost/jreyes')

class User
  include DataMapper::Resource

  property :id, Serial
  property :name, String
  property :points, Integer
  has n, :votes

end

class Vote
  include DataMapper::Resource

  property :id, Serial
  property :first, Text
  property :second, Text
  property :category, String

  belongs_to :user

end

DataMapper.finalize
DataMapper.auto_upgrade!

before do

  puts 'hello'

  Pusher.app_id = ENV["OSCAR_APP_ID"]
  Pusher.key = ENV["OSCAR_KEY"]
  Pusher.secret = ENV["OSCAR_SECRET"]
end

get "/" do
  haml :index
end

get "/import" do
  CSV.foreach("votes.csv", {:headers => true}) do |row|
    user = User.first_or_create(
      :name => row['Name'],
      :points => 0
    )
    @last_vote = ''
    
    row.each do |k, v|
      if k == @last_vote
        vote = user.votes.first(:category => k)
        vote.update(
          :second => v
        )
        vote.save
      else
        user.votes.create(
          :category => k,
          :first => v,
        )
        @last_vote = k
        p @last_vote
      end
      
    end
  end
end

get '/winner' do
  haml :winner
end

# http://baby-notifier.herokuapp.com/branded-sms
# Branded SMS Webhook, first asks for device, then sends MMS
route :get, :post, '/score-points' do
  p "$$$$$$$$$$$$$$ CATEGORY"
  @category = params[:category]
  @winner = params[:winner]
  p @category

  @users = User.all

  @users.each do |user|
    points = user.points
    userVote = user.votes.first(:category => @category)
    if userVote.first == @winner
      
      points = points + 5
      p points
    elsif userVote.second == @winner
      points = points + 2
    end
    user.update(:points => points)
    user.save
  end
  Pusher['oscars'].trigger('winner', {
    message: 'hello world'
  })
  status 200
end

get "/leaderboard.json" do
  content_type :json
  allUsers = User.all
  status 200
  headers \
    "Access-Control-Allow-Origin"   => "*"
  body allUsers.to_json
end

get '/scoreboard' do
  erb :leaderboard
end
