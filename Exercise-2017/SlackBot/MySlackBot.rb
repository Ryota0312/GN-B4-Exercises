# coding: utf-8
$LOAD_PATH.unshift(File.dirname(__FILE__))

require 'sinatra'
require 'SlackBot'
require 'json'
require 'net/https'
require 'uri'

class GoogleGeocode
  def initialize
    @base_url = 'https://maps.googleapis.com/maps/api/geocode/json'
    @api_key='AIzaSyALN7jZSORUTLd2XPV5QC2447OX-WjNp-o'
  end
 

  def get_location(address, options={})
    url="#{@base_url}?address=#{URI.encode(address)}&key=#{@api_key}&language=ja"
    uri = URI.parse(url)
    res = nil

    Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      res = http.get(uri)
    end

    return res
  end
end

class MySlackBot < SlackBot
  def test_respond(params, options={})
    user_name = params[:user_name] ? "@#{params[:user_name]}" : ""
    msg=params[:text]
    msg=msg.match(/[^「]*「(.*)」と言って$/)
    return {text: "#{user_name} #{msg[1]}"}.merge(options).to_json
  end

  def get_map(params, options={})
    user_name = params[:user_name] ? "@#{params[:user_name]}" : ""
    address = params[:text]
    geocode=GoogleGeocode.new
    ret = geocode.get_location(address)
    status = JSON.parse(ret.body)
    addr = status['results'][0]['formatted_address']
    lat = status['results'][0]['geometry']['location']['lat']
    lng = status['results'][0]['geometry']['location']['lng']

    return {text: "#{user_name} #{addr}:#{lat},#{lng}"}.merge(options).to_json
  end
end

slackbot = MySlackBot.new

set :environment, :production


get '/' do
  "SlackBot Server"
end

post '/slack' do
  content_type :json
  #slackbot.test_respond(params, {username: "NBot", link_names: true})
  slackbot.get_map(params, {username: "NBot", link_names: true})
end

