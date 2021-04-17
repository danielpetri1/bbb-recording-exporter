require 'nokogiri'
require 'open-uri'

def download(file)
    # Base URL of the recording
    # Format: "https://hostname/presentation/meetingID/"
    base_url = "YOUR_BASE_URL"

    path = base_url + file
    puts "Downloading " + path

    open(file, 'wb') do |file|
        file << open(path).read
    end
end

# Download desired data, e.g. 'metadata.xml', 'panzooms.xml', 'cursor.xml', 'deskshare.xml', 'presentation_text.json', 'captions.json', 'slides_new.xml', 'video/webcams.mp4', 'deskshare/deskshare.mp4'
for get in ['shapes.svg', 'video/webcams.mp4'] do
    download(get)
end

# Opens shapes.svg
@doc = Nokogiri::XML(File.open("shapes.svg"))

# Creates new file to hold the timestamps
File.open("whiteboard-timestamps-svg", "w") {}

# Gets each slide in the presentation
slides = @doc.xpath('//xmlns:image', 'xmlns' => 'http://www.w3.org/2000/svg', 'xlink' => 'http://www.w3.org/1999/xlink')

# Downloads slides
# On the server you don't have to do this since the slides are saved as individual PNG images in the presentation folder
# Client side it is currently still required to create the folders manually (path can be seen in the error message)
slides.each do |img|
    download(img.attr('xlink:href'))
end

# Gets each canvas drawn over the presentation
whiteboard = @doc.xpath('//xmlns:g[@class="canvas"]', 'xmlns' => 'http://www.w3.org/2000/svg', 'xlink' => 'http://www.w3.org/1999/xlink')
hasCanvas = whiteboard.xpath('//@image').to_a.map(&:to_s)

# Current frame and slide in the animation
frameNumber = 0
#slideNumber = 0
time = 0

# For each slide, we write down the time it appears in the animation and create an SVG file displaying it
slides.each do |slide|
    # If the current slide has annotations drawn over it, we need to recreate the animation's frames
    if hasCanvas.include? slide.attr('id')
        # Finds correct frame elements given id
        frames = @doc.xpath("//*[@image=\"" + slide.attr('id').to_s + "\"]/*")

        frames.each do |frame|
            # A frame is composed of itself and the data that came before it
            frameSiblings = frame.xpath('./self::*|preceding-sibling::*')
            
            # The background image needs to be made visible
            style = slide.attr('style')
            style.sub! 'hidden', 'visible'
            slide.set_attribute('style', style)

            # All frame nodes need to be set to visible too
            frameSiblings.each do |node|
                style = node.attr('style')
                style.sub! 'hidden', 'visible'
                node.set_attribute('style', style)
            end
            
            # Get SVG width and height
            width = slide.attr('width')
            height = slide.attr('height')

            # Builds SVG frame
            builder = Nokogiri::XML::Builder.new do |xml|
                # Adds Document Type Definition (may not be needed)
                # xml.doc.create_internal_subset('svg', "-//W3C//DTD SVG 1.1//EN", "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd")
                
                xml.svg(width: width, height: height, version: "1.1", 'xmlns' => "http://www.w3.org/2000/svg", 'xmlns:xlink' => "http://www.w3.org/1999/xlink") {
                    # Adds backgrounds image
                    xml << slide.to_s

                    # Adds whiteboard
                    xml << frameSiblings.to_s
                }
            end

            # Saves frame as SVG file
            File.open("frame" + frameNumber.to_s + ".svg", "w") do |file|
                file.write(builder.to_xml)
            end

            # Export image as PNG (requires librsvg; may not be needed since FFmpeg has support for SVG files when compiled with -enable-librsvg)
            command = "rsvg-convert --format=png --output=frames/png/frame" + frameNumber.to_s + ".png frame" + frameNumber.to_s + ".svg"
            system(command)

            # Delete created SVG file to save space (right now we only care about PNG)
            system("rm frame" + frameNumber.to_s + ".svg")

            duration = (frame.attr('timestamp').to_f - time).round(1)

            File.open('whiteboard-timestamps-svg', 'a') do |file|
                file.puts("file frames/png/frame" + frameNumber.to_s + ".png")
                file.puts "duration " + duration.to_s
            end

            time += duration
            frameNumber += 1
        end

        # Export slide for later processing as annotated PDF file in Cairo
        # ...
        
    else
        # Since the slide has no annotations drawn over it, we only need to render the frame itself
        image = slide.attr('xlink:href')

        # Duration of each slide, rounded to one decimal place
        duration = (slide.attr('out').to_f - slide.attr('in').to_f).round(1)

        File.open('whiteboard-timestamps-svg', 'a') do |file|
            file.puts "file '" + image + "'"
            file.puts "duration " + duration.to_s
        end

        time += duration
    end
end

# Last file needs to be specified twice due to a problem on FFmpeg's side, without duration (according to the documentation, in practice it seems to be fine...)
# ... 

# Recreates the presentation with FFmpeg's Concat Demuxer
system("ffmpeg -f concat -i whiteboard-timestamps-svg -i video/webcams.mp4 -c:a copy -map 0:v -map 1:a -pix_fmt yuv420p -vsync vfr presentation.mp4")
