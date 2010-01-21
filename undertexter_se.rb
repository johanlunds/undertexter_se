#!/usr/bin/env ruby

# TODO: unpack, rename all files. Support for where to save (and unpack) files. Other features?

require 'optparse'
require 'net/http'
require 'rubygems'
require 'hpricot'

class String
  # Removes whitespace in string
  def compact
    gsub(/\s+/, ' ').strip
  end
end

class Application
  
  BASE     = 'http://www.undertexter.se/'
  SEARCH   = BASE + '?p=so&add=arkiv'
  DOWNLOAD = BASE + 'text.php?id='
  
  TYPES = {
    :movie => '',
    :tv    => '2'
  }
  
  ResultItem = Struct.new(:id, :title, :info)
  
  def initialize
    @type = :movie
    @dl_dir = Dir.pwd
    parse_args!
  end
  
  def run!(query)
    puts "Searching '#{@type}' for '#{query}'..."
    items = parse_result(search(@type, query))
    puts "Found #{items.length} result(s)."
    if items.length > 0
      selected = select_subs(items)
      selected.each do |id|
        puts "Downloading #{id}..."
        download(id) do |existing_file|
          print "File '#{existing_file}' exists. Overwrite? "
          gets =~ /y/i
        end
      end
    end
    puts "Done!"
  end
  
  private
  
    # Outputs result and lets user choose which ones to download.
    # Replaces non-digits in input with spaces and splits.
    def select_subs(items)
      puts
      puts ["Id", "Title", "Info"].join("\t")
      items.each do |item|
        puts [item.id, item.title, item.info].join("\t")
      end
      puts
      print "Subtitles to download: "
      gets.gsub(/[^\d]+/, ' ').split(' ')
    end
  
    # do a post with form data (the search values)
    def search(type, query)
      url = URI.parse(SEARCH)
      req = Net::HTTP::Post.new(url.request_uri)
      req.form_data = { 'typ' => TYPES[type], 'str' => query }
      res = Net::HTTP.new(url.host, url.port).start { |http| http.request(req) }
      res.body
    end
    
    # Find table cell with text "Undertexter (Max 100 träffar per sökning)". It's
    # table (a parent element) is the result table so we get all the cells and
    # loop through them, excluding cells we're not interested in.
    # Creates ResultItem-objects with content from cells and returns.
    def parse_result(result)
      items = []
      current = nil
      # Old solution: Hpricot(result).at("a[@href^='#{SHOW}']").parent.parent.parent.search("td")
      Hpricot(result).at('td.ytext').parent.parent.search("td:not(.ytext)").each_with_index do |cell, index|
        # Every sub result has 6 cells and we want (in order) the 2nd and 3rd
        case index % 6
        when 1
          link = cell.at("a")
          current = ResultItem.new
          current.id = link["href"].match(/id=(\d+)/)[1] # http://www.undertexter.se/?p=subark&id=123
          current.title = link.inner_text.compact
        when 2
          current.info = cell.inner_text.compact
          items << current
        end
      end
      items
    end
    
    # fetches contents of zip/rar and saves to disk with filename same as fetched
    # URL's basename. Takes a block which gets called if file already exists.
    def download(id)
      res, url = self.class.fetch(DOWNLOAD + id)
      filename = File.basename(url)
      if File.exist? filename
        return unless yield filename
      end
      File.open(File.join(@dl_dir, filename), 'w') { |f| f.write(res.body) }
    end
    
    # Internal method for doing GET requests with redirects. Returns response and
    # URL (for filename calculation in download-method)
    def self.fetch(url_str, limit = 3)
      raise 'HTTP redirect too deep.' if limit == 0
      res = Net::HTTP.get_response(URI.parse(url_str))
      res, url_str = fetch(res['Location'], limit - 1) if res.is_a? Net::HTTPRedirection
      [res, url_str]
    end
    
    def parse_args!
      opts = OptionParser.new do |o|
        o.banner = "Usage: #{$0} [options] QUERY"
        o.on("-t", "--type [TYPE]", [:movie, :tv], "What type of video to search (movie, tv).") do |v|
          @type = v
        end
        o.on("-d", "--dir [DIRECTORY]", "Directory to download files to.") do |v|
          @dl_dir = v
        end
        o.on_tail("-h", "--help", "Show this message.") do
          puts o
          exit
        end
      end
      opts.parse!
    end
end

Application.new.run! ARGV.pop