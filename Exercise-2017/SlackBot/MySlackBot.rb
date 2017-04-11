# coding: utf-8
$LOAD_PATH.unshift(File.dirname(__FILE__))

require 'sinatra'
require 'SlackBot'
require 'json'
require 'net/https'
require 'uri'

module GetInfobyJson
  def get_location_info(json)
    status = JSON.parse(json.body)
    if status['status']!='OK'
      return nil
    end
    addr = status['results'][0]['formatted_address']
    lat = status['results'][0]['geometry']['location']['lat']
    lng = status['results'][0]['geometry']['location']['lng']

    location = Hash.new()
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
      places[i] = Hash[ "name" => name, "address" => addr, "latitude" => lat, "longitude" => lng ]
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
end

class GooglePlaces < HttpRequest
  include GetInfobyJson
  
  def initialize
    @base_url_nearby='https://maps.googleapis.com/maps/api/place/nearbysearch/json'
    @base_url_autocomplete='https://maps.googleapis.com/maps/api/place/autocomplete/json'
    @api_key='AIzaSyDirkpr0Wb0_4hyBeHFsc_OotV7rq0526E'
  end

  def get_placeid(input)
    url="#{@base_url_autocomplete}?input=#{URI.encode(input)}&key=#{@api_key}&types=geocode&language=ja"

    res = http_get(url)

    status = JSON.parse(res.body)
    if status['status']!='OK'
      return nil
    end
    place_id = status['predictions'][0]['place_id']

    return place_id
  end

  def get_nearby_places_bytypes(lat, lng, type, options={})
    url="#{@base_url_nearby}?location=#{lat},#{lng}&key=#{@api_key}&types=#{type}&rankby=distance&language=ja"

    res = http_get(url)

    places = get_places_info(res, 3)

    return places
  end

  def get_nearby_places_bykeyword(lat, lng, keyword, options={})
    url="#{@base_url_nearby}?location=#{lat},#{lng}&key=#{@api_key}&keyword=#{URI.encode(keyword)}&rankby=distance&language=ja"

    res = http_get(url)

    places = get_places_info(res, 3)

    return places
  end
end

class GoogleGeocode < HttpRequest
  include GetInfobyJson
  
  def initialize
    @base_url = 'https://maps.googleapis.com/maps/api/geocode/json'
    @api_key='AIzaSyALN7jZSORUTLd2XPV5QC2447OX-WjNp-o'
  end

  def get_address_byplaceid(place_id)
    url="#{@base_url}?place_id=#{place_id}&key=#{@api_key}&language=ja"

    res = http_get(url)

    status = JSON.parse(res.body)
    if status['status']!='OK'
      return nil
    end
  
    addr = status['results'][0]['formatted_address']

    return addr
  end

  def get_location_byaddress(address, options={})
    url="#{@base_url}?address=#{URI.encode(address)}&key=#{@api_key}&language=ja&region=jp"

    res = http_get(url)

    location = get_location_info(res)

    return location
  end
end

class GoogleStaticMaps
  def initialize
    @base_url='https://maps.googleapis.com/maps/api/staticmap'
    @api_key='AIzaSyCk4Z0EI3sj1O4l0IQZ54SOrvXq_6GJVq0'
  end

  def create_map(location, places)
    url = "#{@base_url}?key=#{@api_key}&size=800x400&markers=#{location["latitude"]},#{location["longitude"]}&markers=color:blue|label:A|#{places[0]["latitude"]},#{places[0]["longitude"]}&markers=color:blue|label:B|#{places[1]["latitude"]},#{places[1]["longitude"]}&markers=color:blue|label:C|#{places[2]["latitude"]},#{places[2]["longitude"]}"

    return url
  end
end

class SlackRespond
  def repeat_respond(params, options={})
    user_name = params[:user_name] ? "@#{params[:user_name]}" : ""
    msg=params[:text]
    msg=msg.match(/[^「]*「(.*)」と言って/)
    return {text: "#{user_name} #{msg[1]}"}.merge(options).to_json
  end
  
  def respond_places_useplaceid(params, options={})
    geocode=GoogleGeocode.new
    places=GooglePlaces.new
    maps=GoogleStaticMaps.new
    
    user_name = params[:user_name] ? "@#{params[:user_name]}" : ""
    text = params[:text]
    text = text.match(/@NBot\s+(.*)/)
    input_text = text[1]
    
    place_id = places.get_placeid(input_text)
    if place_id==nil
      return {text: "ERROR:地点が特定できませんでした．(#{input_text})\n"}.merge(options).to_json
    end
    print(place_id)
    address = geocode.get_address_byplaceid(place_id)
    if address==nil
      return {text: "ERROR:地点が特定できませんでした．(#{place_id})\n"}.merge(options).to_json
    end
    print(address)
    location = geocode.get_location_byaddress(address)
    if location==nil
      return {text: "ERROR:地点が特定できませんでした．(#{address})\n"}.merge(options).to_json
    end
    places = places.get_nearby_places_bytypes(location["latitude"],location["longitude"],'convenience_store')
    if places==nil
      return {text: "ERROR:結果が見つかりませんでした．\n"}.merge(options).to_json
    end
    
    msg = Array.new(3)
    for i in 0..2 do
      msg[i] = "#{places[i]["name"]} : #{places[i]["address"]}\n"
    end
    
    map = maps.create_map(location, places) 
    
    return {text: "最寄りのコンビニ3件は以下の通りです．\nA:#{msg[0]}\nB:#{msg[1]}\nC:#{msg[2]}\n#{map}"}.merge(options).to_json
  end
  
  def respond_places(params, options={})
    geocode=GoogleGeocode.new
    places=GooglePlaces.new
    maps=GoogleStaticMaps.new
    
    place_table = Hash[ "コンビニ" => 'convenience_store',
                        "書店" => 'book_store',
                        "ATM" => 'atm',
                        "バス停" => 'bus_station',
                        "カフェ" => 'cafe',
                        "公園" => 'park',
                        "バー" => 'bar',
                        "駐車場" => 'parking']
    
    user_name = params[:user_name] ? "@#{params[:user_name]}" : ""
    text = params[:text]
    if text !~ /@NBot\s+(.*)(付近|近く)の(.*)/
      return {text: "#{user_name}\n「@NBot 〇〇付近の〇〇」と入力して下さい．\n"}.merge(options).to_json
    end
    text = text.match(/@NBot\s+(.*)(付近|近く)の(.*)/)
    address = text[1]
    placetype = text[3]
    
    types = place_table["#{placetype}"]
    
    location = geocode.get_location_byaddress(address)
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
    
    map = maps.create_map(location, places)

    dir_a = "<https://www.google.co.jp/maps/dir/#{URI.encode(address)}/@#{location["latitude"]},#{location["longitude"]}/#{URI.encode(places[0]["name"])}/@#{places[0]["latitude"]},#{places[0]["longitude"]}|A>"
    dir_b = "<https://www.google.co.jp/maps/dir/#{URI.encode(address)}/@#{location["latitude"]},#{location["longitude"]}/#{URI.encode(places[1]["name"])}/@#{places[1]["latitude"]},#{places[1]["longitude"]}|B>"
    dir_c = "<https://www.google.co.jp/maps/dir/#{URI.encode(address)}/@#{location["latitude"]},#{location["longitude"]}/#{URI.encode(places[2]["name"])}/@#{places[2]["latitude"]},#{places[2]["longitude"]}|C>"
    
    
    return {text: "#{user_name}\n最寄りの#{placetype}3件は以下の通りです．A,B,Cのリンクをクリックして経路を確認できます．\n#{dir_a}:#{msg[0]}\n#{dir_b}:#{msg[1]}\n#{dir_c}:#{msg[2]}\n#{map}"}.merge(options).to_json
   end
end

class MySlackBot < SlackBot 
  def bot_respond(params, options={})
    bot = SlackRespond.new
    user_name = params[:user_name] ? "@#{params[:user_name]}" : ""
    input = params[:text]
    if input =~ /[^「]*「(.*)」と言って/
      bot.repeat_respond(params, options)
    elsif input =~ /@NBot\s+(.*)(付近|近く)の(.*)/
      bot.respond_places(params, options)
    else
      return {text: "#{user_name}\nExample:\"〇〇付近の〇〇\",\ \"「〇〇」と言って\"\n"}.merge(options).to_json
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
  #slackbot.respond_places(params, {username: "NBot", link_names: true})
  slackbot.bot_respond(params, {username: "NBot", link_names: true})
end
