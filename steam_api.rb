require "pry"
require 'httparty'
require 'open-uri'
require 'nokogiri' 
require 'selenium-webdriver'


API_KEY = ENV['STEAM_API_KEY']
def get_details
  response = HTTParty.get("https://api.steampowered.com/IWishlistService/GetWishlist/v1/?key=#{API_KEY}&steamid=76561197993313205&data_request=true")
  app_ids = response.dig('response', 'items').map {|app| app['appid']}.compact
  steam_url = 'https://store.steampowered.com/api/appdetails?appids='
  cdkeys_url= 'https://www.cdkeys.com/#q='
  app_ids.map do |app_id| 
    request = HTTParty.get("#{steam_url}#{app_id}&filters=basic,price_overview")
    #binding.pry
    request_data = request.dig(app_id.to_s, 'data') 
    app_name = request_data['name']
    steam_final_price = request_data.dig('price_overview', 'final')
    driver = Selenium::WebDriver.for :chrome
    driver.get("#{cdkeys_url}#{app_name}&platforms.default=Steam&region.default=USA~Worldwide")
    wait = Selenium::WebDriver::Wait.new(timeout: 5)
    main_box = wait.until { driver.find_element(id: "instant-search-results-container")}
    text = main_box.text.gsub("\n", " ")
    capture = /([\w\s]*#{app_name}\s[\w\s]*PC\s\$\d.\d\d\sADD)/i
    matches = text.match(capture)
   # binding.pry
    next unless matches&.captures&.first
    
    cd_price = matches.captures.first.split[-2] 
    cd_key_final_price = cd_price.gsub("$", "").gsub(".", "").to_i
   # binding.pry
    
    puts "Steam price #{steam_final_price} cd key price #{cd_key_final_price}"
    driver.quit
  end
end 
  
get_details