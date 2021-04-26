require 'nokogiri'
require 'open-uri'
require 'cgi'
require 'fileutils'

# Reference recording: "https://balancer.bbb.rbg.tum.de/playback/presentation/2.3/f5c1fdc86039b1cd48cb686d38ec0eb6be27dfc7-1619030802001?meetingId=f5c1fdc86039b1cd48cb686d38ec0eb6be27dfc7-1619030802001"

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
@doc = Nokogiri::XML(File.open("shapes.svg"))

# Creates new file to hold the timestamps of the whiteboard
File.open("whiteboard-timestamps", "w") {}

# Creates new file to hold the timestamps of the slides
File.open("presentation-timestamps", "w") {}

# Gets each slide in the presentation
slides = @doc.xpath('//xmlns:image', 'xmlns' => 'http://www.w3.org/2000/svg', 'xlink' => 'http://www.w3.org/1999/xlink')

# Downloads each slide
# On the server you don't have to do this since the slides are saved as individual PNG images in the presentation folder
slides.each do |img|
    path = File.dirname(img.attr('xlink:href'))
    
    # Creates folder structure if it's not yet present
    unless File.directory?(path) 
        FileUtils.mkdir_p(path)
    end
    
    download(img.attr('xlink:href'))
end

# Gets each canvas drawn over the presentation
whiteboard = @doc.xpath('//xmlns:g[@class="canvas"]', 'xmlns' => 'http://www.w3.org/2000/svg', 'xlink' => 'http://www.w3.org/1999/xlink')
hasCanvas = whiteboard.xpath('//@image').to_a.map(&:to_s)

# Current frame and slide in the animation
frameNumber = 0
slideNumber = 0

# For each slide, we write down the time it appears in the animation and create an SVG file displaying it
slides.each do |slide|
    # Get slide's background image
    image = slide.attr('xlink:href')

    # Get SVG width and height
    width = slide.attr('width')
    height = slide.attr('height')

    # How long the presentation slide is displayed for
    duration = (slide.attr('out').to_f - slide.attr('in').to_f).round(1)

    # Background image
    File.open('presentation-timestamps', 'a') do |file|
        file.puts "file '" + image + "'"
        file.puts "duration " + duration.to_s
    end

    # Whiteboard: if the current slide has annotations drawn over it, we need to recreate the animation's frames
    if hasCanvas.include? slide.attr('id')
        # Finds correct frame elements given id
        frames = @doc.xpath("//*[@image=\"" + slide.attr('id').to_s + "\"]/*")

        # Get timing information
        canvasStart = frames.xpath('./@timestamp')[0]
        canvasEnd = frames.xpath('./@timestamp').pop
        
        # Creates first slide, with no annotations
        builder = Nokogiri::XML::Builder.new do |xml|
            xml.svg(width: width, height: height, version: "1.1", 'xmlns' => "http://www.w3.org/2000/svg", 'xmlns:xlink' => "http://www.w3.org/1999/xlink") {
            }
        end

        # Saves empty frame as SVG file
        File.open("frames/frame" + frameNumber.to_s + ".svg", "w") do |file|
            file.write(builder.to_xml)
        end

        duration = (canvasStart.to_s.to_f - slide.attr('in').to_f).round(1)

        # Prevents negative timestamps from making it into the file (must be fixed, has something to do with undo / going back in presentation)
        if duration < 0 then
            duration = (slide.attr('out').to_f - slide.attr('in').to_f).round(1)

            File.open('whiteboard-timestamps', 'a') do |file|
                file.puts "file frames/frame" + frameNumber.to_s + ".svg"
                file.puts "duration " + duration.to_s
            end

            next
        end

        File.open('whiteboard-timestamps', 'a') do |file|
            file.puts "file frames/frame" + frameNumber.to_s + ".svg"
            file.puts "duration " + duration.to_s
        end

        frameNumber += 1

        # Draw the frames
        frameTimings = frames.xpath('./@timestamp').to_a.map(&:to_s).map(&:to_f).each_cons(2).map { |a, b| (b-a).round(1) } << (slide.attr('out').to_f - canvasEnd.to_s.to_f).round(1)

        frames.each do |frame|
            # A frame is consists of the current drawn asset and the ones that came before it
            frameSiblings = frame.xpath('./self::*|preceding-sibling::*')

            # All frame nodes need to be set to visible too
            frameSiblings.each do |node|
                style = node.attr('style')
                style.sub! 'hidden', 'visible'
                node.set_attribute('style', style)
            end

            # Builds SVG frame
            builder = Nokogiri::XML::Builder.new do |xml|
                xml.svg(width: width, height: height, version: "1.1", 'xmlns' => "http://www.w3.org/2000/svg", 'xmlns:xlink' => "http://www.w3.org/1999/xlink") {
                    # Adds whiteboard
                    xml << frameSiblings.to_s
                }
            end

            # Saves frame as SVG file
            File.open("frames/frame" + frameNumber.to_s + ".svg", "w") do |file|
                file.write(builder.to_xml)
            end

            # Duration of frame is the next element in the frameTimings queue
            duration = frameTimings.shift

            File.open('whiteboard-timestamps', 'a') do |file|
                file.puts("file frames/frame" + frameNumber.to_s + ".svg")
                file.puts "duration " + duration.to_s
            end

            frameNumber += 1
        end
        
        # Export last frame as PNG
        frameSiblings = frames.last.xpath('./self::*|preceding-sibling::*')

        # The background image needs to be made visible
        style = frames.last.attr('style')
        style.sub! 'hidden', 'visible'
        slide.set_attribute('style', style)

        # All frame nodes need to be set to visible too
        frameSiblings.each do |node|
            style = node.attr('style')
            style.sub! 'hidden', 'visible'
            node.set_attribute('style', style)
        end

        builder = Nokogiri::XML::Builder.new do |xml|
            xml.svg(width: width, height: height, version: "1.1", 'xmlns' => "http://www.w3.org/2000/svg", 'xmlns:xlink' => "http://www.w3.org/1999/xlink") {
                # Adds background image
                xml << slide.to_s
                
                # Adds whiteboard
                xml << frameSiblings.to_s
        }
        end

        File.open("tmp.svg", "w") do |file|
            file.write(builder.to_xml)
        end
        
        #Exports last frame as PNG
        export = "rsvg-convert --format=png --output=slides/slide" + slideNumber.to_s + ".png tmp.svg"
        system(export)

    else
        # Don't show any annotations - empty SVG frame
        builder = Nokogiri::XML::Builder.new do |xml|
            xml.svg(width: width, height: height, version: "1.1", 'xmlns' => "http://www.w3.org/2000/svg", 'xmlns:xlink' => "http://www.w3.org/1999/xlink") {
            }
        end

        # Saves empty frame as SVG file
        File.open("frames/frame" + frameNumber.to_s + ".svg", "w") do |file|
            file.write(builder.to_xml)
        end

        # Adds transparent frame to the whiteboard file
        File.open('whiteboard-timestamps', 'a') do |file|
            file.puts "file frames/frame" + frameNumber.to_s + ".svg"
            file.puts "duration " + duration.to_s
        end

        # Saves slide for later PDF export
        open('slides/slide' + slideNumber.to_s + '.png', 'wb') do |file|
            file << open(image).read
        end
        
        frameNumber += 1
    end
    
    slideNumber += 1
end

# Recreates the presentation slides
system("ffmpeg -f concat -i presentation-timestamps -c:v libvpx-vp9 -b:v 2M -pix_fmt yuva420p -metadata:s:v:0 alpha_mode=\"1\" -vsync vfr -auto-alt-ref 0 -y -filter_complex 'scale=w=1280:h=720:force_original_aspect_ratio=1,pad=1280:720:-1:-1:white' presentation.webm")

# Recreates the whiteboard annotations
system("ffmpeg -f concat -i whiteboard-timestamps -c:v libvpx-vp9 -b:v 2M -pix_fmt yuva420p -metadata:s:v:0 alpha_mode=\"1\" -vsync vfr -auto-alt-ref 0 -y -filter_complex 'scale=w=1280:h=720:force_original_aspect_ratio=1,pad=1280:720:-1:-1:white' whiteboard.webm")

# Presentation + Annotations + Deskshare + Webcams (.webm)
system("ffmpeg -i deskshare/deskshare.mp4 -c:v libvpx-vp9 -i presentation.webm -c:v libvpx-vp9 -i whiteboard.webm -i video/webcams.mp4 -filter_complex '[3]scale=w=iw/4:h=ih/4[cam];[0][1]overlay[tmp];[tmp][2]overlay[out];[out][cam]overlay=x=(main_w-overlay_w)' -b:v 2M -shortest -y presentation-deskshare-webcam.webm")

# Presentation + Annotations + Deskshare + Webcams (.mp4) - faster, patent encumbered
#system("ffmpeg -i deskshare/deskshare.mp4 -c:v libvpx-vp9 -i presentation.webm -c:v libvpx-vp9 -i whiteboard.webm -i video/webcams.mp4 -filter_complex '[3]scale=w=iw/4:h=ih/4[cam];[0][1]overlay[tmp];[tmp][2]overlay[out];[out][cam]overlay=x=(main_w-overlay_w)' -shortest -y presentation-deskshare-webcam.mp4")