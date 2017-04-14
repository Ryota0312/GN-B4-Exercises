# coding: utf-8
$LOAD_PATH.unshift(File.dirname(__FILE__))

require 'sinatra'
require 'SlackBot'
require 'json'
require 'net/https'
require 'uri'

# Get information from json as hash format.
class GetInfoFromJson
  def get_location_info(json)
    status = JSON.parse(json.body)
    if status['status']!='OK'
      return nil
    end
    addr = status['results'][0]['formatted_address']
    lat = status['results'][0]['geometry']['location']['lat']
    lng = status['results'][0]['geometry']['location']['lng']

    location = { "address" => addr,"latitude" => lat,"longitude" =>lng }

    return location
  end

  def get_places_info(json, num)
    status = JSON.parse(json.body)
    if status['status']!='OK'
      return nil
    end
    places = Array.new(num)
    for i in 0..num-1 do
      name = status['results'][i]['name']
      addr = status['results'][i]['vicinity']
      lat = status['results'][i]['geometry']['location']['lat']
      lng = status['results'][i]['geometry']['location']['lng']
      places[i] = { "name" => name, "address" => addr, "latitude" => lat, "longitude" => lng }
    end
    
    return places
  end
end

class HttpRequest
  def http_get(url)
    uri = URI.parse(url)
    res = nil

    Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      res = http.get(uri)
    end

    return res
  end

  def http_post(url, request)
    uri = URI.parse(url)
    res = nil
    json = request.to_json

    Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      res = http.post(uri.request_uri, json, { "Content-Type" => "application/json" })
    end

    return res
  end

  # Set parameters in query format to base URL
  def set_params(base_url, params)
    for item in params
      if item[1].instance_of?(Array)
        for elem in item[1]
          query = "#{query}#{item[0]}=#{elem}&"
        end
      else
        query = "#{query}#{item[0]}=#{item[1]}&"
      end
    end

    url = base_url + "?" + query
    url[url.length-1]=""

    return url
  end
end

# Get places by Google Places API
class GooglePlaces < HttpRequest
  def initialize
    @base_url='https://maps.googleapis.com/maps/api/place/nearbysearch/json'
    @api_key='AIzaSyDirkpr0Wb0_4hyBeHFsc_OotV7rq0526E'
  end

  # Get places included in 'type' near specified latitude and longitude. 
  def get_nearby_places_bytypes(lat, lng, type, options={})
    get_info_fromjson = GetInfoFromJson.new

    url_params = { :location => "#{lat},#{lng}", :types => type, :key => @api_key, :rankby => "distance", :language => "ja" }
    url = set_params(@base_url, url_params)
    
    res = http_get(url)

    places = get_info_fromjson.get_places_info(res, 3)

    return places
  end

  # Get places for the specified 'keyword' near specified latitude and longitude. 
  def get_nearby_places_bykeyword(lat, lng, keyword, options={})
    get_info_fromjson = GetInfoFromJson.new

    url_params = { :location => "#{lat},#{lng}", :keyword => URI.encode(keyword), :key => @api_key, :rankby => "distance", :language => "ja" }
    url = set_params(@base_url, url_params)

    res = http_get(url)

    places = get_info_fromjson.get_places_info(res, 3)

    return places
  end
end

# Get latitude and longitude from 'keyword' by Google Geocoding API
class GoogleGeocoder < HttpRequest
  def initialize
    @base_url = 'https://maps.googleapis.com/maps/api/geocode/json'
    @api_key='AIzaSyALN7jZSORUTLd2XPV5QC2447OX-WjNp-o'
  end
  
  def get_location_bykeyword(keyword, options={})
    get_info_fromjson = GetInfoFromJson.new

    url_params = { :address => URI.encode(keyword), :key => @api_key, :language => "ja", :region => "jp" }
    url = set_params(@base_url, url_params)

    res = http_get(url)

    location = get_info_fromjson.get_location_info(res)

    return location
  end
end

class GoogleStaticMaps < HttpRequest
  def initialize
    @base_url='https://maps.googleapis.com/maps/api/staticmap'
    @api_key='AIzaSyCk4Z0EI3sj1O4l0IQZ54SOrvXq_6GJVq0'
  end

  # Create map image by specified 'location' and some places.
  def create_map(location, places)

    places = ["#{location["latitude"]},#{location["longitude"]}",
              "color:blue|label:A|#{places[0]["latitude"]},#{places[0]["longitude"]}",
              "color:blue|label:B|#{places[1]["latitude"]},#{places[1]["longitude"]}",
              "color:blue|label:C|#{places[2]["latitude"]},#{places[2]["longitude"]}"]
    url_params = { :key => @api_key, :size => "800x400", :markers => places }
    url = set_params(@base_url, url_params)

    return url
  end
end

# Get shorted URL by Google URL Shortener API
class GoogleUrlShortener < HttpRequest
  def initialize
    @base_url='https://www.googleapis.com/urlshortener/v1/url'
    @api_key='AIzaSyBjSm1VYMtakSlz4E-iYI-nKDFq2NeCyYs'
  end

  def shorten_url(long_url)
    request = { :longUrl => long_url }
    res = http_post("#{@base_url}?key=#{@api_key}", request)

    short_url = JSON.parse(res.body)

    return short_url["id"]
  end
end


class SlackRespond
  # Respond message "XXX" in '「XXX」と言って'
  def repeat_respond(params, options={})
    user_name = params[:user_name] ? "@#{params[:user_name]}" : ""
    msg=params[:text]
    msg=msg.match(/[^「]*「(.*)」と言って/)
    return {text: "#{user_name} #{msg[1]}"}.merge(options).to_json
  end

  # Respond 3 places and map image for user's remark "〇〇(location)付近の〇〇(place type)"
  def respond_places(params, options={})
    geocode=GoogleGeocoder.new
    places=GooglePlaces.new
    maps=GoogleStaticMaps.new
    url_shortener=GoogleUrlShortener.new
    
    place_table = { "コンビニ" => 'convenience_store',
                    "書店" => 'book_store',
                    "ATM" => 'atm',
                    "バス停" => 'bus_station',
                    "カフェ" => 'cafe',
                    "公園" => 'park',
                    "バー" => 'bar',
                    "駐車場" => 'parking',
                    "銀行" => 'bank',
                    "バー" => 'bar',
                    "公園" => 'park',
                    "ショッピングモール" => 'shopping_mall',
                    "大学" => 'university',
                    "ガソリンスタンド" => 'gas_station',
                    "郵便局" => 'post_office' }
    
    user_name = params[:user_name] ? "@#{params[:user_name]}" : ""
    text = params[:text]
    if text !~ /@NBot\s+(.*)(付近|近く|周辺)の(.*)/
      return {text: "#{user_name}\n「@NBot 〇〇付近の〇〇」と入力して下さい．\n"}.merge(options).to_json
    end
    text = text.match(/@NBot\s+(.*)(付近|近く|周辺)の(.*)/)
    address = text[1]
    placetype = text[3]
    p address
    p placetype
    
    types = place_table["#{placetype}"]
    
    location = geocode.get_location_bykeyword(address)
    if location==nil
      return {text: "#{user_name}\n地点が特定できませんでした．(#{address})\n"}.merge(options).to_json
    end
    if types!=nil
      places = places.get_nearby_places_bytypes(location["latitude"],location["longitude"],types)
    else
      places = places.get_nearby_places_bykeyword(location["latitude"],location["longitude"],placetype)
    end
    if places==nil
      return {text: "#{user_name}\n結果が見つかりませんでした．\n"}.merge(options).to_json
    end
    
    msg = Array.new(3)
    for i in 0..2 do
      msg[i] = "#{places[i]["name"]} : #{places[i]["address"]}\n"
    end
    
    map_url = maps.create_map(location, places)
    map_short_url = url_shortener.shorten_url(map_url)

    dir_a = "<https://www.google.co.jp/maps/dir/#{URI.encode(address)},#{URI.encode(location["address"])}/@#{location["latitude"]},#{location["longitude"]}/#{URI.encode(places[0]["name"])}/@#{places[0]["latitude"]},#{places[0]["longitude"]}|A>"
    dir_b = "<https://www.google.co.jp/maps/dir/#{URI.encode(address)},#{URI.encode(location["address"])}/@#{location["latitude"]},#{location["longitude"]}/#{URI.encode(places[1]["name"])}/@#{places[1]["latitude"]},#{places[1]["longitude"]}|B>"
    dir_c = "<https://www.google.co.jp/maps/dir/#{URI.encode(address)},#{URI.encode(location["address"])}/@#{location["latitude"]},#{location["longitude"]}/#{URI.encode(places[2]["name"])}/@#{places[2]["latitude"]},#{places[2]["longitude"]}|C>"
    
    
    return {text: "#{user_name}\n最寄りの#{placetype}3件は以下の通りです．A,B,Cのリンクをクリックして経路を確認できます．\n#{dir_a}:#{msg[0]}\n#{dir_b}:#{msg[1]}\n#{dir_c}:#{msg[2]}\n#{map_short_url}"}.merge(options).to_json
  end
end

# Choose the respond content by recieved message
class MySlackBot < SlackBot
  def bot_respond(params, options={})
    bot = SlackRespond.new
    user_name = params[:user_name] ? "@#{params[:user_name]}" : ""
    input = params[:text]
    if input =~ /[^「]*「(.*)」と言って/
      bot.repeat_respond(params, options)
    elsif input =~ /@NBot\s+(.*)(付近|近く|周辺)の(.*)/
      bot.respond_places(params, options)
    else
      return {text: "Hi! #{user_name}\nUsage:\"〇〇付近の〇〇\",\ \"「〇〇」と言って\"\n"}.merge(options).to_json
    end
  end
end


slackbot = MySlackBot.new

set :environment, :production

get '/' do
  "SlackBot Server"
end

post '/slack' do
  content_type :json
  slackbot.bot_respond(params, {username: "NBot", link_names: true})
end
