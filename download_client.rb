# frozen_string_literal: true

require 'nokogiri'
require 'open-uri'
require 'cgi'
require 'fileutils'
require 'json'

def download(file)
  # Format: "https://hostname/presentation/meetingID/#{file}"

  path = "https://hostname/presentation/meetingID/#{file}"
  path = "https://vmott40.in.tum.de/presentation/fccbbfd5ae98f6eb1e6bf57fc8970672da7244b6-1630411518050/#{file}"

  puts "Downloading #{path}"

  File.open(file, 'wb') do |get|
    get << URI.parse(path.to_s).open(&:read)
  end
end

# Downloads the recording's assets
# Whiteboard: 'shapes.svg', 'cursor.xml', 'panzooms.xml', 'presentation_text.json', 'captions.json', 'metadata.xml'
# Video: 'video/webcams.mp4', 'deskshare/deskshare.mp4'
# Chat: 'slides_new.xml'

['shapes.svg'].each do |get|
  download(get)
end

# Opens shapes.svg
@doc = Nokogiri::XML(File.open('shapes.svg'))

slides = @doc.xpath('//xmlns:image', 'xmlns' => 'http://www.w3.org/2000/svg', 'xlink' => 'http://www.w3.org/1999/xlink')

# Download all captions
json = JSON.parse(File.read('captions.json'))

(0..json.length - 1).each do |i|
  download "caption_#{json[i]['locale']}.vtt"
end

# Downloads each slide
slides.each do |img|
  path = File.dirname(img.attr('xlink:href'))

  # Creates folder structure if it's not yet present
  FileUtils.mkdir_p(path) unless File.directory?(path)

  download(img.attr('xlink:href'))
end
