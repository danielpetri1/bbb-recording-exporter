# Reference recording: "https://balancer.bbb.rbg.tum.de/playback/presentation/2.3/f5c1fdc86039b1cd48cb686d38ec0eb6be27dfc7-1619030802001?meetingId=f5c1fdc86039b1cd48cb686d38ec0eb6be27dfc7-1619030802001"
require 'nokogiri'
require 'open-uri'
require 'cgi'
require 'fileutils'

def download(file)
    # Format: "https://hostname/presentation/meetingID/file"
    # path = "https://balancer.bbb.rbg.tum.de/presentation/f5c1fdc86039b1cd48cb686d38ec0eb6be27dfc7-1619030802001/" # If not indicated through CLI

    uri = URI.parse(ARGV[0])
    meetingId = CGI.parse(uri.query)['meetingId'].first
    path = URI::HTTP.build(:scheme => uri.scheme, :host => uri.host, :path => '/presentation/' + meetingId + '/' + file)

    puts "Downloading " + path.to_s

    open(file, 'wb') do |file|
        file << open(path).read
    end
end

# Download desired data, e.g. 'metadata.xml', 'panzooms.xml', 'cursor.xml', 'presentation_text.json', 'captions.json', 'slides_new.xml', 'video/webcams.mp4', 'deskshare/deskshare.mp4'
for get in ['shapes.svg', 'video/webcams.mp4', 'deskshare/deskshare.mp4'] do
    download(get)
end

# Opens shapes.svg
@doc = Nokogiri::XML(File.open('shapes.svg'))

slides = @doc.xpath('//xmlns:image', 'xmlns' => 'http://www.w3.org/2000/svg', 'xlink' => 'http://www.w3.org/1999/xlink')

# Downloads each slide
slides.each do |img|
    path = File.dirname(img.attr('xlink:href'))
    
    # Creates folder structure if it's not yet present
    unless File.directory?(path) 
        FileUtils.mkdir_p(path)
    end
    
    download(img.attr('xlink:href'))
end