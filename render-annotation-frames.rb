require 'nokogiri'
require 'itree'

# Opens shapes.svg
@doc = Nokogiri::XML(File.open('shapes.svg'))

# Creates new file to hold the timestamps of the whiteboard
File.open('whiteboard-timestamps', 'w') {}

# Gets each canvas drawn over the presentation
whiteboard = @doc.xpath('//xmlns:g[@class="canvas"]', 'xmlns' => 'http://www.w3.org/2000/svg', 'xlink' => 'http://www.w3.org/1999/xlink')
slides = @doc.xpath('//xmlns:image', 'xmlns' => 'http://www.w3.org/2000/svg', 'xlink' => 'http://www.w3.org/1999/xlink')

timestamps = @doc.xpath('//@timestamp')
undos = @doc.xpath('//@undo')

# We want to render frames for each change in the whiteboard
changes = timestamps + undos
changes = changes.to_a.map(&:to_s).map(&:to_f).uniq.sort

if changes[0] == -1 then 
    changes[0] = 0
else
    changes.unshift(0)
end

renderIntervals = []

timings = changes.each_slice(2).to_a

changes.each_cons(2) do | (a,b) |
    renderIntervals << [a, b]
end

renderIntervals.each do |time|
    puts "==="
    puts time[0]
    puts time[1]
    puts "==="
end

# Duration of last annotation
# slides.last.attr('out').to_s.to_f - changes.last).round(1)

frameNumber = 0

# Tree to hold intervals
intervals = Intervals::Tree.new

whiteboard.each do |canvas|
    # Finds slide corresponding to that canvas to get information from
    slide = @doc.xpath('//xmlns:image[@id = "' + canvas.attr('image').to_s + '"]', 'xmlns' => 'http://www.w3.org/2000/svg', 'xlink' => 'http://www.w3.org/1999/xlink')

    # Attributes of the slide the canvas is being drawn on
    slideStart = slide.attr('in').to_s.to_f
    slideEnd = slide.attr('out').to_s.to_f

    width = slide.attr('width').to_s
    height = slide.attr('height').to_s
    
    x = slide.attr('x').to_s
    y = slide.attr('y').to_s

    # Find shapes that make up the slide
    shapes = canvas.xpath('./xmlns:g[@class="shape"]')

    shapes.each do |shape|

        # Make shape visible
        style = shape.attr('style')
        style.sub! 'hidden', 'visible'
        shape.set_attribute('style', style)

        # When the shape should stop being shown
        undo = shape.attr('undo').to_s.to_f.round(1)

        if undo < 0 then
            undo = slideEnd
        end

        # When the shape is first drawn
        timestamp = shape.attr('timestamp').to_s.to_f.round(1)

        shapeStart = [[slideStart, timestamp].max, slideEnd].min
        shapeEnd = [[slideStart, undo].max, slideEnd].min

        intervals.insert(shapeStart, shapeEnd, shape)

    end
end

renderIntervals.each do |timestamp|
    # Get what is being shown up until that timestamp
    results = intervals.stab(timestamp[0], timestamp[1])

    # Arrays to hold whiteboard information
    draw = []
    shapes = []
    render = []

    # Get slide annotations at timestamp
    results.each do |result|
        draw << result.data
    end

    # Get individual shapes ID
    draw.each do |drawing|
        shapes << drawing.attr('shape')
    end

    # Filter out duplicates, we're only interested in the last shape of each ID
    shapes = shapes.uniq

    # Add this shape to what will be rendered
    shapes.each do |shape|
        selection = draw.select { |drawing| drawing.attr('shape') == shape}
        render << selection.last
    end

    # Find out which slide is being rendered
    #if render.length > 0 then
    #    puts render.first.attr('id')
    #end

    # Builds SVG frame
    builder = Nokogiri::XML::Builder.new do |xml|
        xml.svg(width: 1600, height: 900, x: 0, y: 0, version: '1.1', 'xmlns' => 'http://www.w3.org/2000/svg', 'xmlns:xlink' => 'http://www.w3.org/1999/xlink') do

            # Adds what came before
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
        file.puts "duration #{(timestamp[1] - timestamp[0]).round(1)}"
    end

    frameNumber += 1
end

system("ffmpeg -f concat -i whiteboard-timestamps -c:v libvpx-vp9 -b:v 2500k -pix_fmt yuva420p -metadata:s:v:0 alpha_mode=\"1\" -vsync vfr -auto-alt-ref 0 -y -filter_complex 'scale=w=1280:h=720:force_original_aspect_ratio=1,pad=1280:720:-1:-1:white' whiteboard.webm")