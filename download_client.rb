# frozen_string_literal: true

# Reference recording "https://balancer.bbb.rbg.tum.de/playback/presentation/2.3/f5c1fdc86039b1cd48cb686d38ec0eb6be27dfc7-1619030802001?meetingId=f5c1fdc86039b1cd48cb686d38ec0eb6be27dfc7-1619030802001"
require 'nokogiri'
require 'open-uri'
require 'cgi'
require 'fileutils'

def download(file)
  # Format: "https://hostname/presentation/meetingID/file"
  
  # Lasttest
  path = "https://vmott40.in.tum.de/presentation/b87bbe0888dff19aa181be51d86a3f52543fc5a7-1620820241322/#{file}"

  # Pink Cube
  # path = "https://vmott40.in.tum.de/presentation/b87bbe0888dff19aa181be51d86a3f52543fc5a7-1620639249054/#{file}"
  
  #uri = URI.parse(ARGV[0])
  #meeting_id = CGI.parse(uri.query)['meetingId'].first
  #path = URI::HTTP.build(scheme: uri.scheme, host: uri.host, path: "/presentation/#{meeting_id}/#{file}")

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

# Downloads each slide
slides.each do |img|
  path = File.dirname(img.attr('xlink:href'))

  # Creates folder structure if it's not yet present
  FileUtils.mkdir_p(path) unless File.directory?(path)

  download(img.attr('xlink:href'))
end
