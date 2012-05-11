require 'rubygems'
require 'sinatra'
require 'haml'
require 'twitter'
require 'octopi'

configure do
  require 'redis'
  uri = URI.parse(ENV["REDISTOGO_URL"] || "127.0.0.1")
  REDIS = Redis.new(:host => uri.host, :port => uri.port, :password => uri.password)
end

helpers do
  def convert_to_html(s)
    url_pattern   = /( |^)http:\/\/([^\s]*\.[^\s]*)( |$)/
    user_pattern  = /( |^)@(\w+)/
    tag_pattern   = /( |^)#(\w+)/

    while s =~ tag_pattern
      s.sub! "##{$2}", "<span class='tweet tag'>##{$2}</span>"
    end

    while s =~ user_pattern
      s.sub! "@#{$2}", "<a href='http://twitter.com/#{$2}' >@#{$2}</a>"
    end

    while s =~ url_pattern
      name = $2
      s.sub! /( |^)http:\/\/#{name}( |$)/, " <a href='http://#{name}' >#{name}</a> "
    end

    s
  end
  
  def shorten(text, length)
    if text.length > length
      text[0..length-3] + "..."
    else
      text
    end
  end
  
  def retrieve_tweets
    begin
      if cached_tweets = REDIS.get("tweets")
        YAML::load(cached_tweets)
      else
        unformatted_tweets = Twitter.user_timeline("enricogenauck", :count => 4, :trim => true)
        tweets = unformatted_tweets.collect{ |tweet| convert_to_html(tweet.text) }
        REDIS.set("tweets", tweets.to_yaml)
        tweets
      end
    rescue Twitter::BadRequest
      []
    end
  end
  
  def retrieve_commits
    if raw_commits = REDIS.get("commits")
      YAML::load(raw_commits)
    else
      begin
        commits = Octopi::Repository.find(:user => "enricogenauck").
                                     map(&:commits).map{|commits| commits.
                                     sort_by(&:authored_date).last}.flatten
        commits = commits.sort_by(&:authored_date).reverse
      rescue
        commits = []
      end
      one_day_livetime = 24 * 60 * 60
      REDIS.setex("commits", one_day_livetime, commits.to_yaml)
      commits
    end    
  end
  
  def link_to(args = {})
    path = "/" + args[:section]
    uri = "http://www." + args[:host] + path
    "<a href=#{uri}>#{args[:host]}<small>#{path}</small></a>"
  end
end

get '/' do
  @tweets = retrieve_tweets
  @commits = retrieve_commits

  haml :index
end