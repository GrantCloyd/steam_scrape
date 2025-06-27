# frozen_string_literal: true

require 'pry'
require 'httparty'
require 'selenium-webdriver'
require 'csv'
require 'time'

class WishListCompare
  # to use, locally set your steam api key and your personal steam account id using the export statement for STEAM_API_KEY and STEAM_ID respectively
  # In addition, make sure httparty and selenium-webdriver are installed locally using gem install commands

  API_KEY = ENV['STEAM_API_KEY']
  STEAM_ID = ENV['STEAM_ID']
  WISHLIST_URL = "https://api.steampowered.com/IWishlistService/GetWishlist/v1/?key=#{API_KEY}&steamid=#{STEAM_ID}&data_request=true".freeze
  STEAM_APP_DETAILS_URL = 'https://store.steampowered.com/api/appdetails?appids='
  CDKEYS_GENERAL_SEARCH_URL = 'https://www.cdkeys.com/#q='
  BASE_CSV_PATH = 'steam_cdkeys_prices.csv'

  def compare_prices_from_steam_wishlist_and_cdkeys
    # get personal wishlist app_ids from steam
    wishlist_response = HTTParty.get(WISHLIST_URL)
    app_ids = wishlist_response.dig('response', 'items').map { |app| app['appid'] }.compact

    @app_results = []
    # steam requires iterating through each app request except when using price_overview filter
    app_ids.map do |app_id|
      # STEAM
      app_name, steam_final_price = get_name_and_price_from_steam(app_id)
      if steam_final_price.nil?
        game_unavailable_message(app_name, 'Steam')
        next
      end

      # CDKEYS
      begin
        game_matches = get_search_results_from_cdkeys(app_name)
      rescue Selenium::WebDriver::Error::TimeoutError
        game_unavailable_message(app_name, 'CDKeys')
        next
      end

      unless game_matches&.captures&.first
        game_unavailable_message(app_name, 'CDKeys')
        next
      end

      cd_key_final_price = game_matches.captures.first.gsub('.', '').to_i
      price_diff = steam_final_price - cd_key_final_price

      @app_results << {
        app_name: app_name,
        steam_final_price: steam_final_price,
        cd_key_final_price: cd_key_final_price,
        price_diff: price_diff
      }

      puts "\n* Game: #{app_name}\n* Steam price: #{steam_final_price}\n* CDKey price: #{cd_key_final_price}\n* Price Difference: #{price_diff}\n"
    end

    # Write/update CSV after all apps processed
    create_or_update_csv
  end

  private

  def get_name_and_price_from_steam(app_id)
    steam_app_details_request = HTTParty.get("#{STEAM_APP_DETAILS_URL}#{app_id}&filters=basic,price_overview")
    response_data = steam_app_details_request.dig(app_id.to_s, 'data')
    app_name = response_data['name'].gsub('™', '')
    # final is current price
    steam_final_price = response_data.dig('price_overview', 'final')

    [app_name, steam_final_price]
  end

  def get_search_results_from_cdkeys(app_name)
    options = Selenium::WebDriver::Chrome::Options.new
    options.add_argument('--headless')
    driver = Selenium::WebDriver.for :chrome, options: options
    wait = Selenium::WebDriver::Wait.new(timeout: 10)

    driver.get("#{CDKEYS_GENERAL_SEARCH_URL}#{app_name}&platforms.default=Steam&region.default=USA~Worldwide")
    search_results = wait.until { driver.find_element(id: 'instant-search-results-container') }

    game_matches = get_game_matches_from_search_results(app_name, search_results)
    driver.quit

    game_matches
  end

  def get_game_matches_from_search_results(app_name, search_results)
    search_results_text = search_results.text.gsub("\n", ' ')
    # regex outline - any subset of words before, the app name, an optional space,
    # any subset of words after, PC - which is used for every steam title, optional (ww) key for worldwide,
    # the price (captured), then ADD - which denotes it's in stock
    capture = /[\w\s]*#{app_name}\s*[\w\s]*PC\s*[(WW)\s]*\$(\d+.\d\d)*\sADD/i
    search_results_text.match(capture)
  end

  def game_unavailable_message(app_name, site)
    puts "\n#{app_name} is not available for purchase on #{site}\n"
  end

  def create_or_update_csv
    csv_data.empty? ? create_initial_csv : update_existing_csv
  end

  def create_initial_csv
    # create headers
    @app_results.each do |result|
      csv_data << [result[:app_name]]
      csv_data << ['Steam Price']
      csv_data << ['CDKey Price']
      csv_data << ['Price Diff']
      csv_data << [''] # blank row
    end
    # Fill in the first column of data
    @app_results.each_with_index do |result, i|
      base = i * 5
      csv_data[base][1] = timestamp
      csv_data[base + 1][1] = result[:steam_final_price]
      csv_data[base + 2][1] = result[:cd_key_final_price]
      csv_data[base + 3][1] = result[:price_diff]
    end
    CSV.open(BASE_CSV_PATH, 'w') { |csv| csv_data.each { |row| csv << row } }

    puts "\nNew csv created"
  end

  def update_existing_csv
    # Find all unique app names in existing CSV
    app_row_indices = {}
    csv_data.each_with_index do |row, idx|
      app_row_indices[row[0]] = idx if row[0] && !row[0].empty? && (idx % 5 == 0)
    end

    # new_col is set to the size of the existing col count to not overwrite
    new_col = csv_data[0] ? csv_data[0].size : 1

    @app_results.each do |result|
      if app_row_indices[result[:app_name]]
        base = app_row_indices[result[:app_name]]
      else
        # New app, add to end
        csv_data << [result[:app_name]] + ([nil] * (new_col - 1))
        csv_data << ['Steam Price'] + ([nil] * (new_col - 1))
        csv_data << ['CDKey Price'] + ([nil] * (new_col - 1))
        csv_data << ['Price Diff'] + ([nil] * (new_col - 1))
        csv_data << [''] + ([nil] * (new_col - 1)) + [nil]
        base = csv_data.size - 5
      end

      # fill out info based on the set base param
      csv_data[base][new_col] = timestamp
      csv_data[base + 1][new_col] = result[:steam_final_price]
      csv_data[base + 2][new_col] = result[:cd_key_final_price]
      csv_data[base + 3][new_col] = result[:price_diff]
    end
    CSV.open(BASE_CSV_PATH, 'w') { |csv| csv_data.each { |row| csv << row } }

    puts "\nExisting file updated"
  end

  # read existing
  def csv_data
    @csv_data ||= File.exist?(BASE_CSV_PATH) ? CSV.read(BASE_CSV_PATH) : []
  end

  def timestamp
    @timestamp ||= Time.now.strftime('%Y-%m-%d %H:%M:%S')
  end
end

WishListCompare.new.compare_prices_from_steam_wishlist_and_cdkeys
