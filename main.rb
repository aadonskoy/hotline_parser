require 'ostruct'
require 'open-uri'
require 'nokogiri'

class Item < OpenStruct
  def image_filename
    "#{filename}#{image_url.match(/\.\w+\z/)[0]}"
  end
end

class Saver
  def initialize(directory)
    @directory = directory
  end
  def save(item)
    raise 'Not implemented'
  end
end

class LogImageSaver < Saver
  def save(item)
    puts [@directory, item.image_filename].join('/')
  end
end

class ImageSaver < Saver
  def save(item)
    open([@directory, item.image_filename].join('/'), 'wb') do |file|
      file << open(item.image_url).read
    end
    puts "#{item.image_url}"
  end
end

class SiteParser
  attr_reader :items
  def initialize(params = {})
    @base_url = params.fetch(:base_url)
    @product_link = params.fetch(:product_link)
    @options = params.fetch(:options) { '?catmode=tiles&sort=1&sr=0' }
    @items = []
    @url = '' << @base_url << @product_link << @options
  end

  def start
    process_with_threads(number_pages) do |page_number|
      @items[page_number] = parse_page(page_number)
    end
    @items.flatten!
  end

  def save_images(saver)
    start if @items.size == 0
    process_with_threads(@items.size - 1) do |item_id|
      saver.save(@items[item_id])
    end
  end

  def render_most_cheap
    start if @items.size == 0
    cheapest = @items.sort_by { |item| item.min_price }.first
    puts "Cheapest: #{cheapest.name}, av_price: #{cheapest.mid_price}"
  end

  def render_most_expansive
    start if @items.size == 0
    most_expansive = @items.sort_by { |item| item.max_price }.last
    puts "Most expansive: #{most_expansive.name}, av_price: #{most_expansive.mid_price}"

  end

  def overall_mid_price
    start if @items.size == 0
    overall_mid = @items.map { |item| item.mid_price }.inject { |sum, var| sum + var } / @items.length
    puts "Overall mid price: #{overall_mid}"
  end

  private

  def process_with_threads(n)
    (0..n).each_slice(20) do |numbers|
      threads = []
      numbers.each do |thread_id|
        threads << Thread.new(thread_id) do |number|
          yield(number)
        end
      end
      threads.each { |thread| thread.join }
    end
  end

  def fetch_page(page_number = 0)
    html = open(@url + "&p=#{page_number}")
    Nokogiri::HTML(html)
  end

  def parse_page(page_number = 0)
    items_on_page = []
    doc = fetch_page(page_number)
    doc.xpath('//td[@id="catalogue"]/ul[contains(@class, "catalog")]/li/div[contains(@class, "c-box")]').each do |item|
      items_on_page << Item.new(
                                name: parse_name(item),
                                filename: parse_filename(item),
                                mid_price: parse_mid_price(item),
                                min_price: parse_min_price(item),
                                max_price: parse_max_price(item),
                                image_url: parse_image_url(item)
                               ) if parse_mid_price(item) > 0
    end
    puts "finish with #{page_number}"
    items_on_page
  end

  def parse_name(doc)
    name_node = doc.xpath('div[contains(@class, "info")]/div[@class="title-box"]/h3/a').text
    name_node.sub(/\s{3,}\z/, '') unless name_node.empty?
  end

  def parse_filename(doc)
    filename_node = doc.xpath('div[contains(@class, "info")]/div[@class="title-box"]/h3/a/@href').first
    filename_node.value.scan(/\/.+\/(.+)\//)[0][0] if filename_node && !filename_node.value.empty?
  end

  def parse_mid_price(doc)
    mid_price_node = doc.xpath('div[@class="pr-box"]/div[@class="price"]/span[@class="orng"]').text
    return mid_price_node.gsub(/\D/, '').to_f unless mid_price_node.empty?
    0
  end

  def parse_min_price(doc)
    min_price_node = doc.xpath('div[@class="pr-box"]/div[@class="price"]/span[@class="blck"]').text
    if !min_price_node.empty?
      min_price_node.match(/(.*) - .* .*/)[1].gsub(/\D/, '').to_f
    else
      parse_mid_price(doc)
    end
  end

  def parse_max_price(doc)
    max_price_node = doc.xpath('div[@class="pr-box"]/div[@class="price"]/span[@class="blck"]').text
    if !max_price_node.empty?
      max_price_node.match(/.* - (.*) .*/)[1].gsub(/\D/, '').to_f
    else
      parse_mid_price(doc)
    end
  end

  def parse_image_url(doc)
    image_url_node = doc.xpath('div[contains(@class, "img-box")]/a/div/img/@src').first
    return @base_url + image_url_node.value if image_url_node
    @base_url + '/img/s/noimg/pr_80.png'
  end

  def number_pages
    @number_pages ||= fetch_page.xpath('//div[@class="pager"]/span/a[last()]').text.to_i - 1
  end
end

parser = SiteParser.new(base_url: 'http://hotline.ua', product_link: '/deti/detskie-konstruktory/')
parser.start
parser.save_images(ImageSaver.new('images'))
parser.overall_mid_price
parser.render_most_expansive
parser.render_most_cheap
p 'Done'
