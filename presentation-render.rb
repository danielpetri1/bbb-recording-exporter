require 'nokogiri'
require 'open-uri'
require 'fileutils'

def download(file)
    # Base URL of the recording
    # Format: "https://hostname/presentation/meetingID/"
    base_url = "https://balancer.bbb.rbg.tum.de/presentation/32660e42f95b3ba7a92c968cdc9e0c37272cf463-1613978884363/"

    path = base_url + file
    puts "Downloading " + path

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

# Creates new file to hold the timestamps
File.open("whiteboard-timestamps-svg", "w") {}

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
time = 0

# For each slide, we write down the time it appears in the animation and create an SVG file displaying it
slides.each do |slide|
    # If the current slide has annotations drawn over it, we need to recreate the animation's frames
    if hasCanvas.include? slide.attr('id')
        # Finds correct frame elements given id
        frames = @doc.xpath("//*[@image=\"" + slide.attr('id').to_s + "\"]/*")

        frames.each do |frame|
            # A frame is consists of the current drawn asset and the ones that came before it
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

            # Export image as PNG
            command = "rsvg-convert --format=png --output=frames/frame" + frameNumber.to_s + ".png frame" + frameNumber.to_s + ".svg"
            system(command)

            duration = (frame.attr('timestamp').to_f - time).round(1)

            File.open('whiteboard-timestamps-svg', 'a') do |file|
                file.puts("file frames/frame" + frameNumber.to_s + ".png")
                file.puts "duration " + duration.to_s
            end

            time += duration
            frameNumber += 1
        end

        # Export slide for later processing as annotated PDF file in Cairo by copying last completed PNG/SVG frame
        open('slides/slide' + slideNumber.to_s + '.png', 'wb') do |file|
            file << open('frames/frame' + (frameNumber - 1).to_s + '.png').read
        end
        
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

        # Export slide for later processing as annotated PDF file in Cairo by copying last completed PNG
        open('slides/slide' + slideNumber.to_s + '.png', 'wb') do |file|
            file << open(image).read
        end
    end

    slideNumber += 1
end

# Last file needs to be specified twice due to a problem on FFmpeg's side, without duration (according to the documentation, in practice it seems to be fine...)
# ... 

# Recreates the presentation with FFmpeg's Concat Demuxer (just slides + annotations + audio, fast due to variable frame rate)
#system("ffmpeg -f concat -i whiteboard-timestamps-svg -i video/webcams.mp4 -c:a copy -map 0:v -map 1:a -pix_fmt yuv420p -vsync vfr -vf \"scale=w=1280:h=720:force_original_aspect_ratio=1,pad=1280:720:(ow-iw)/2:(oh-ih)/2\" -y presentation.mp4")

# Remove created SVG frames
system("rm frame*.svg")

# Slides + Whiteboard + Screenshare
#system("ffmpeg -i deskshare/deskshare.mp4 -f concat -i whiteboard-timestamps-svg -i video/webcams.mp4 -c:a copy -map 0:v -map 1 -map 2:a -filter_complex '[1]scale=w=1280:h=720:force_original_aspect_ratio=1,pad=1280:720:-1:-1:white[a];[0][a]overlay' -y presentation-deskshare.mp4")

# Slides + Whiteboard + Screenshare + Webcam
system("ffmpeg -i deskshare/deskshare.mp4 -f concat -i whiteboard-timestamps-svg -i video/webcams.mp4 -c:a copy -map 0 -map 1:v -map 2 -filter_complex '[1]scale=w=1280:h=720:force_original_aspect_ratio=1,pad=1280:720:-1:-1:white[a];[0][a]overlay[b];[2]scale=w=iw/4:h=ih/4[c];[b][c]overlay=x=(main_w-overlay_w)' -y presentation-deskshare-webcam.mp4")