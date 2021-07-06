# frozen_string_literal: true

require 'nokogiri'
require 'open-uri'
require 'cgi'
require 'fileutils'

def download(file)
  # Format: "https://hostname/presentation/meetingID/#{file}"

  path = "https://hostname/presentation/meetingID/#{file}"

  puts "Downloading #{path}"

  File.open(file, 'wb') do |get|
    get << URI.parse(path.to_s).open(&:read)
  end
end

# Downloads the recording's assets
# Whiteboard: 'shapes.svg', 'cursor.xml', 'panzooms.xml', 'presentation_text.json', 'captions.json', 'metadata.xml'
# Video: 'video/webcams.mp4', 'deskshare/deskshare.mp4'
# Chat: 'slides_new.xml'

['shapes.svg', 'cursor.xml', 'panzooms.xml', 'presentation_text.json', 'metadata.xml', 'video/webcams.mp4', 'deskshare/deskshare.mp4', 'slides_new.xml'].each do |get|
  download(get)
end

# Opens shapes.svg
@doc = Nokogiri::XML(File.open('shapes.svg'))

slides = @doc.xpath('//xmlns:image', 'xmlns' => 'http://www.w3.org/2000/svg', 'xlink' => 'http://www.w3.org/1999/xlink')

# Downloads each slide
slides.each do |img|
  path = File.dirname(img.attr('xlink:href'))

  # Creates folder structure if it's not yet present
  FileUtils.mkdir_p(path) unless File.directory?(path)

  download(img.attr('xlink:href'))
end
