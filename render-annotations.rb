require 'nokogiri'

def renderAnimatedAnnotations(frames, shapes, slideEnd, width, height, x, y, frameNumber, keep)
    # Initialize queue holding the duration of each frame in the shape's animation
    frameTimings = frames.xpath('./@timestamp').to_a.map(&:to_s).map(&:to_f).each_cons(2).map do
        |a, b| (b - a).round(1)
    end << (slideEnd - frames.last.attr('timestamp').to_s.to_f).round(1)

    shapes.each do |tool|
        # Get every frame that has this ID
        draw = frames.xpath('//xmlns:g[@shape="'+ tool +'"]')
        
        draw.each do |frame|
            # Builds SVG frame
            builder = Nokogiri::XML::Builder.new do |xml|
                xml.svg(width: width, height: height, x: x, y: y, version: '1.1', 'xmlns' => 'http://www.w3.org/2000/svg', 'xmlns:xlink' => 'http://www.w3.org/1999/xlink') do

                    # Adds what came before
                    keep.each do |drawing|
                        xml << drawing.to_s
                    end

                    # Adds annotations at given timestamp
                    xml << frame.to_s
                end
            end

            # Saves frame as SVG file
            File.open("frames/frame#{frameNumber}.svg", 'w') do |file|
                file.write(builder.to_xml)
            end

            # If an undo happened before the next shape starts, adapt duration accordingly
            if frame == draw.last && frame.attr('undo') != "-1" && frame.attr('undo').to_s.to_f < frameTimings[0].to_f + frame.attr('timestamp').to_s.to_f then
                duration = (frame.attr('undo').to_s.to_f - frame.attr('timestamp').to_s.to_f).round(1)

                File.open('whiteboard-timestamps', 'a') do |file|
                    file.puts("file frames/frame#{frameNumber}.svg")
                    file.puts "duration #{duration}"
                end

                frameNumber += 1

                # Draw state of the frame AFTER undo was pressed by rendering what was kept up to that point
                duration = (frame.attr('timestamp').to_s.to_f + frameTimings[0].to_f - frame.attr('undo').to_s.to_f).round(1)

                builder = Nokogiri::XML::Builder.new do |xml|
                    xml.svg(width: width, height: height, x: x, y: y, version: '1.1', 'xmlns' => 'http://www.w3.org/2000/svg', 'xmlns:xlink' => 'http://www.w3.org/1999/xlink') do
                        
                        # Adds what came before undo
                        keep.each do |drawing|
                            if drawing.attr('undo') != frame.attr('undo')
                                xml << drawing.to_s
                            end
                        end

                    end
                end

                File.open("frames/frame#{frameNumber}.svg", 'w') do |file|
                    file.write(builder.to_xml)
                end

                File.open('whiteboard-timestamps', 'a') do |file|
                    file.puts("file frames/frame#{frameNumber}.svg")
                    file.puts "duration #{duration}"
                end

            else
                # Save last state of current drawing if undo wasn't pressed or its deletion only occurs after the next few shapes
                if frame == draw.last then
                    keep << draw.last
                end

                duration = frameTimings[0].to_f

                File.open('whiteboard-timestamps', 'a') do |file|
                    file.puts("file frames/frame#{frameNumber}.svg")
                    file.puts "duration #{duration}"
                end
            end

            frameNumber += 1
            frameTimings.shift
        end
    end

    return frameNumber
end

# Opens shapes.svg
@doc = Nokogiri::XML(File.open('shapes.svg'))

# Creates new file to hold the timestamps of the whiteboard
File.open('whiteboard-timestamps', 'w') {}

# Gets each canvas drawn over the presentation
whiteboard = @doc.xpath('//xmlns:g[@class="canvas"]', 'xmlns' => 'http://www.w3.org/2000/svg', 'xlink' => 'http://www.w3.org/1999/xlink')

# Gets slides
slides = @doc.xpath('//xmlns:image', 'xmlns' => 'http://www.w3.org/2000/svg', 'xlink' => 'http://www.w3.org/1999/xlink')

# Slides that have annotations
hasCanvas = whiteboard.xpath('//@image').to_a.map(&:to_s)

frameNumber = 0

slides.each do |slide|
    # Get slide's information
    slideStart = slide.attr('in').to_s.to_f
    slideEnd = slide.attr('out').to_s.to_f

    width = slide.attr('width')
    height = slide.attr('height')

    x = slide.attr('x')
    y = slide.attr('y')

    if hasCanvas.include? slide.attr('id')
        # The canvas we need to draw is the first element of the queue
        canvas = whiteboard.shift

        frames = canvas.xpath('./xmlns:g[@class="shape"]')

        # Make all frames visible
        frames.each do |frame|
            style = frame.attr('style')
            style.sub! 'hidden', 'visible'
            frame.set_attribute('style', style)
        end

        # If the starting timestamp of the drawing already occured, we are going back in the presentation
        if(frames.attr('timestamp').to_s.to_f <= slideStart) then
        
            # Show up to timestamp
            before = canvas.xpath('./xmlns:g[@timestamp <= ' + slideStart.to_s + 'and @undo = -1]')

            after = canvas.xpath('./xmlns:g[@timestamp > ' + slideStart.to_s + ']')

            # Show frame as it was last shown
            builder = Nokogiri::XML::Builder.new do |xml|
            xml.svg(width: width, height: height, x: x, y: y, version: '1.1', 'xmlns' => 'http://www.w3.org/2000/svg', 'xmlns:xlink' => 'http://www.w3.org/1999/xlink') do
                    # Adds annotations at given timestamp
                        xml << before.to_s
                end
            end

            # Saves "before" frame as SVG file and writes its duration down
            File.open("frames/frame#{frameNumber}.svg", 'w') do |file|
                file.write(builder.to_xml)
            end

            # Length of the "before" frame showing what was drawn
            if(after.length <= 0) then
                duration = (slideEnd - slideStart).round(1)

                File.open('whiteboard-timestamps', 'a') do |file|
                    file.puts "file frames/frame#{frameNumber}.svg"
                    file.puts "duration #{duration}"
                end

                frameNumber += 1
                next
            end
        
            duration = (after.attr('timestamp').to_s.to_f - slideStart).round(1)

            File.open('whiteboard-timestamps', 'a') do |file|
                file.puts "file frames/frame#{frameNumber}.svg"
                file.puts "duration #{duration}"
            end

            frameNumber += 1

            shapes = after.xpath('@shape').map(&:to_s).uniq

            # Draw the new frames
            frameNumber = renderAnimatedAnnotations(after, shapes, slideEnd, width, height, x, y, frameNumber, before)
            next
        end 

        # Gets unique IDs of each shape (each shape has many frames with the same ID)
        shapes = canvas.xpath('./xmlns:g[@class="shape"]/@shape').map(&:to_s).uniq

        # Wait until first annotation appears: create empty SVG frame
        builder = Nokogiri::XML::Builder.new do |xml|
            xml.svg(width: width, height: height, version: '1.1', 'xmlns' => 'http://www.w3.org/2000/svg', 'xmlns:xlink' => 'http://www.w3.org/1999/xlink')
        end

        # Saves frame as SVG file and writes its duration down
        File.open("frames/frame#{frameNumber}.svg", 'w') do |file|
            file.write(builder.to_xml)
        end

        # Nothing appears until the timestamp of the first drawing
        duration = (frames.attr('timestamp').to_s.to_f - slideStart).round(1)

        File.open('whiteboard-timestamps', 'a') do |file|
            file.puts "file frames/frame#{frameNumber}.svg"
            file.puts "duration #{duration}"
        end

        # No drawing counts as a transparent frame in the video
        frameNumber += 1;

        # Draw frames
        frameNumber = renderAnimatedAnnotations(frames, shapes, slideEnd, width, height, x, y, frameNumber, [])

    else
        duration = (slideEnd - slideStart).round(1)

        # Create empty SVG frame
        builder = Nokogiri::XML::Builder.new do |xml|
            xml.svg(width: width, height: height, version: '1.1', 'xmlns' => 'http://www.w3.org/2000/svg', 'xmlns:xlink' => 'http://www.w3.org/1999/xlink')
        end

        # Saves frame as SVG file and writes its duration down
        File.open("frames/frame#{frameNumber}.svg", 'w') do |file|
            file.write(builder.to_xml)
        end

        File.open('whiteboard-timestamps', 'a') do |file|
            file.puts "file frames/frame#{frameNumber}.svg"
            file.puts "duration #{duration}"
        end

        frameNumber += 1
    end
end

system("ffmpeg -f concat -i whiteboard-timestamps -c:v libvpx-vp9 -b:v 2500k -pix_fmt yuva420p -metadata:s:v:0 alpha_mode=\"1\" -vsync vfr -auto-alt-ref 0 -y -filter_complex 'scale=w=1280:h=720:force_original_aspect_ratio=1,pad=1280:720:-1:-1:white' whiteboard.webm")