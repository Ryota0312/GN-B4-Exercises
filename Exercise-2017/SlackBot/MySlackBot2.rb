# coding: utf-8
$LOAD_PATH.unshift(File.dirname(__FILE__))

require 'sinatra'
require 'SlackBot'
require 'json'
require 'net/https'
require 'uri'

# Creator
class GoogleAPIs

end

class GooglePlacesFactory  < GoogleAPIs
  
end


# Get places by Google Places API
class GooglePlaces
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
class GoogleGeocoder
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

class GoogleStaticMaps
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
class GoogleUrlShortener
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
