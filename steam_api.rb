# frozen_string_literal: true

require 'pry'
require 'httparty'
require 'selenium-webdriver'
require 'csv'
require 'time'

class WishListCompare
  BASE_CSV_PATH = 'steam_cdkeys_prices.csv'
  API_KEY = ENV['STEAM_API_KEY']
  STEAM_ID = ENV['STEAM_ID']
  WISHLIST_URL = "https://api.steampowered.com/IWishlistService/GetWishlist/v1/?key=#{API_KEY}&steamid=#{STEAM_ID}&data_request=true".freeze
  STEAM_APP_DETAILS_URL = 'https://store.steampowered.com/api/appdetails?appids='
  CDKEYS_GENERAL_SEARCH_URL = 'https://www.cdkeys.com/#q='

  class << self
    def compare_prices_from_steam_wishlist_and_cdkeys
      # get my wishlist from steam
      wishlist_response = HTTParty.get(WISHLIST_URL)
      app_ids = wishlist_response.dig('response', 'items').map { |app| app['appid'] }.compact

      @app_results = []
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
        @app_results << {
          app_name: app_name,
          steam_final_price: steam_final_price,
          cd_key_final_price: cd_key_final_price,
          price_diff: price_diff
        }
        puts "\n* Game: #{app_name}\n* Steam price: #{steam_final_price}\n* CDKey price: #{cd_key_final_price}\n* Price Difference: #{price_diff}\n\n"
        driver.quit
      end
      # Write/update CSV after all apps processed
      binding.pry
      create_or_update_csv
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
    end

    def update_existing_csv
      # Find all unique app names in existing CSV
      app_row_indices = {}
      @csv_data.each_with_index do |row, idx|
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
    end

    # read existing
    def csv_data
      @csv_data ||= File.exist?(BASE_CSV_PATH) ? CSV.read(BASE_CSV_PATH) : []
    end

    def timestamp
      @timestamp ||= Time.now.strftime('%Y-%m-%d %H:%M:%S')
    end
  end
end

WishListCompare.compare_prices_from_steam_wishlist_and_cdkeys
