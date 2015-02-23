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
  Pusher.app_id = ENV["OSCAR_APP_ID"]
  Pusher.key = ENV["OSCAR_KEY"]
  Pusher.secret = ENV["OSCAR_SECRET"]
end

get "/" do
  haml :index
end

get "/import" do
  # import the people and votes from an exported csv from a Google doc.
  CSV.foreach("votes.csv", {:headers => true}) do |row|

    # create a user from the row name
    user = User.first_or_create(
      :name => row['Name'],
      :points => 0
    )

    # hack to track which vote the person is using.
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

# Post for the winner form. Adds points to the user profiles
route :get, :post, '/score-points' do
  @category = params[:category]
  @winner = params[:winner]

  @users = User.all

  @users.each do |user|
    points = user.points
    userVote = user.votes.first(:category => @category)

    if userVote.first == @winner
      points = points + 5
    elsif userVote.second == @winner
      points = points + 2
    end

    user.update(:points => points)
    user.save
  end

  # Trigger event on pusher to update the leaderboard
  Pusher['oscars'].trigger('winner', {
    message: 'hello world'
  })

  status 200
end

# Form to input the winner of each category
# TODO: refactor as a list of selects?
get '/winner' do
  haml :winner
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
