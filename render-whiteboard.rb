require 'nokogiri'

# Opens shapes.svg
@doc = Nokogiri::XML(File.open('shapes copy.svg'))

# Get intervals to display the frames
ins = @doc.xpath('//@in')
outs = @doc.xpath('//@out')
timestamps = @doc.xpath('//@timestamp')
undos = @doc.xpath('//@undo')

intervals = (ins + outs + timestamps + undos).to_a.map(&:to_s).map(&:to_f).uniq.sort

# Creates new file to hold the timestamps of the whiteboard
File.open('whiteboard-timestamps', 'w') {}

# If a value of -1 does not correspond to a timestamp
if intervals.first == -1 then
    intervals = intervals.drop(1)
end 

# Obtain interval range that each frame will be shown for
frameNumber = 0
frames = []

intervals.each_cons(2) do | (a,b) |
    frames << [a, b]
end

# Render the visible frame for each interval
frames.each do |frame|

    intervalStart = frame[0]
    intervalEnd = frame[1]

    # Frame's duration
    duration = (intervalEnd - intervalStart).round(1)

    # Figure out which slide we're currently on
    slide = @doc.xpath('//*[@in <= ' + intervalStart.to_s + ' and ' + intervalEnd.to_s + ' <= @out]')

    # Get slide information
    # slideStart = slide.attr('in').to_s.to_f
    # slideEnd = slide.attr('out').to_s.to_f
    slideId = slide.attr('id').to_s
    width = slide.attr('width').to_s
    height = slide.attr('height').to_s
    
    x = slide.attr('x').to_s
    y = slide.attr('y').to_s

    # Get slide's canvas
    canvas = @doc.xpath('//xmlns:g[@class="canvas" and @image="' + slideId.to_s + '"]', 'xmlns' => 'http://www.w3.org/2000/svg', 'xlink' => 'http://www.w3.org/1999/xlink')

    # Render up until interval end
    draw = canvas.xpath('./xmlns:g[@timestamp < ' + intervalEnd.to_s + ']')

    # Remove redundant shapes
    shapes = []
    render = []

    draw.each do |shape|
        shapes << shape.attr('shape').to_s
    end

    # Add this shape to what will be rendered
    if draw.length > 0 then

        shapes.uniq.each do |shape|
            selection = draw.select { |drawing| drawing.attr('shape') == shape && (drawing.attr('undo') == "-1" || drawing.attr('undo').to_s.to_f >= intervalEnd)}
            render << selection.last
        end

    end


    render.each do |shape|

        unless shape.nil?
            style = shape.attr('style')
            style.sub! 'hidden', 'visible'
            shape.set_attribute('style', style) 
        end

    end

    # Builds SVG frame
    builder = Nokogiri::XML::Builder.new do |xml|
        xml.svg(width: width, height: height, x: x, y: y, version: '1.1', 'xmlns' => 'http://www.w3.org/2000/svg', 'xmlns:xlink' => 'http://www.w3.org/1999/xlink') do

            render.each do |shape|
                xml << shape.to_s
            end

        end
    end

    # Saves frame as SVG file
    File.open("frames/frame#{frameNumber}.svg", 'w') do |file|
        file.write(builder.to_xml)
    end

    # Writes its duration down
    File.open('whiteboard-timestamps', 'a') do |file|
        file.puts "file frames/frame#{frameNumber}.svg"
        file.puts "duration #{(intervalEnd - intervalStart).round(1)}"
    end

    frameNumber += 1
end

system("ffmpeg -f concat -i whiteboard-timestamps -c:v libvpx-vp9 -b:v 2500k -pix_fmt yuva420p -metadata:s:v:0 alpha_mode=\"1\" -vsync vfr -auto-alt-ref 0 -y -filter_complex 'scale=w=1920:h=1080:force_original_aspect_ratio=1,pad=1920:1080:-1:-1:white' whiteboard.webm")