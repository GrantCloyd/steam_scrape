# frozen_string_literal: true

require 'pry'
require 'httparty'
require 'selenium-webdriver'

API_KEY = ENV['STEAM_API_KEY']
WISHLIST_URL = "https://api.steampowered.com/IWishlistService/GetWishlist/v1/?key=#{API_KEY}&steamid=76561197993313205&data_request=true".freeze
STEAM_APP_DETAILS_URL = 'https://store.steampowered.com/api/appdetails?appids='.freeze
CDKEYS_GENERAL_SEARCH_URL = 'https://www.cdkeys.com/#q='.freeze

def compare_prices_from_steam_wishlist_and_cdkeys
  # get my wishlist from steam
  wishlist_response = HTTParty.get(WISHLIST_URL)
  app_ids = wishlist_response.dig('response', 'items').map { |app| app['appid'] }.compact

  app_ids.map do |app_id|
    # STEAM
    steam_app_details_request = HTTParty.get("#{STEAM_APP_DETAILS_URL}#{app_id}&filters=basic,price_overview")
    response_data = steam_app_details_request.dig(app_id.to_s, 'data')
    app_name = response_data['name'].gsub('™', '')
    steam_final_price = response_data.dig('price_overview', 'final')
    if steam_final_price.nil?
      puts "\n#{app_name} is not available for purchase on Steam\n"
      next
    end

    # CDKEYS
    options = Selenium::WebDriver::Chrome::Options.new
    options.add_argument('--headless')
    driver = Selenium::WebDriver.for :chrome, options: options
    wait = Selenium::WebDriver::Wait.new(timeout: 10)
    begin
      driver.get("#{CDKEYS_GENERAL_SEARCH_URL}#{app_name}&platforms.default=Steam&region.default=USA~Worldwide")
      search_results = wait.until { driver.find_element(id: 'instant-search-results-container') }
    rescue Selenium::WebDriver::Error::TimeoutError
      puts "\n#{app_name} is not available on CDkeys\n"
      next
    end
    
    text = search_results.text.gsub("\n", ' ')
    # regex outline - any subset of words before, the app name, an optional space,
    # any subset of words after, PC - which is used for every steam title, optional (ww) key for worldwide,
    # the price (captured), then ADD - which denotes it's in stock
    capture = /[\w\s]*#{app_name}\s*[\w\s]*PC\s*[(WW)\s]*\$(\d+.\d\d)*\sADD/i
    matches = text.match(capture)

    unless matches&.captures&.first
      puts "\n#{app_name} is not available on CDKeys\n"
      next
    end

    cd_price = matches.captures.first
    cd_key_final_price = cd_price.gsub('.', '').to_i
    price_diff = steam_final_price - cd_key_final_price

    puts "\n* Game: #{app_name}\n* Steam price: #{steam_final_price}\n* CDKey price: #{cd_key_final_price}\n* Price Difference: #{price_diff}\n\n"
    driver.quit
  end
end

compare_prices_from_steam_wishlist_and_cdkeys
