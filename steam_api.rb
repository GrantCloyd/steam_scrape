require "pry"
require 'httparty' 


API_KEY = ENV['STEAM_API_KEY']
def get_details
  response = HTTParty.get("https://api.steampowered.com/IWishlistService/GetWishlist/v1/?key=#{API_KEY}&steamid=76561197993313205&data_request=true")
  app_ids = response.dig('response', 'items').map {|app| app['appid']}.compact
  url = 'https://store.steampowered.com/api/appdetails?appids='
  app_ids.map do |app_id| 
    request = HTTParty.get("#{url}#{app_id}") 
    app_name = request.dig(app_id.to_s, 'data', 'name')
  end
end 
  
get_details