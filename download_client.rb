# frozen_string_literal: true

require 'nokogiri'
require 'open-uri'
require 'cgi'
require 'fileutils'
require 'json'

def download(file)
  # Format: "https://hostname/presentation/meetingID/#{file}"

  path = "https://hostname/presentation/meetingID/#{file}"

  # Lasttest
  path = "https://vmott40.in.tum.de/presentation/b87bbe0888dff19aa181be51d86a3f52543fc5a7-1620820241322/#{file}"

  # Aspect ratio test
  # path = "https://vmott40.in.tum.de/presentation/fccbbfd5ae98f6eb1e6bf57fc8970672da7244b6-1623441506330/#{file}"

  # GBS Repetirorium
  # path = "https://balancer.bbb.rbg.tum.de/presentation/32660e42f95b3ba7a92c968cdc9e0c37272cf463-1613978884363/#{file}"

  # Captions
  # path = "https://vmott40.in.tum.de/presentation/fccbbfd5ae98f6eb1e6bf57fc8970672da7244b6-1626096331406/#{file}"
  
  puts "Downloading #{path}"

  File.open(file, 'wb') do |get|
    get << URI.parse(path.to_s).open(&:read)
  end
end

# Downloads the recording's assets
# Whiteboard: 'shapes.svg', 'cursor.xml', 'panzooms.xml', 'presentation_text.json', 'captions.json', 'metadata.xml'
# Video: 'video/webcams.mp4', 'deskshare/deskshare.mp4'
# Chat: 'slides_new.xml'

['shapes.svg', 'cursor.xml', 'panzooms.xml', 'presentation_text.json', 'captions.json', 'metadata.xml', 'video/webcams.webm', 'slides_new.xml'].each do |get|
  download(get)
end

# Opens shapes.svg
@doc = Nokogiri::XML(File.open('shapes.svg'))

slides = @doc.xpath('//xmlns:image', 'xmlns' => 'http://www.w3.org/2000/svg', 'xlink' => 'http://www.w3.org/1999/xlink')

# Download all captions
json = JSON.parse(File.read('captions.json'))

for i in 0..json.length - 1 do
  download "caption_#{json[i]["locale"]}.vtt"
end

# Downloads each slide
slides.each do |img|
  path = File.dirname(img.attr('xlink:href'))

  # Creates folder structure if it's not yet present
  FileUtils.mkdir_p(path) unless File.directory?(path)

  download(img.attr('xlink:href'))
end
