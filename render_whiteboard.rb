# frozen_string_literal: true

require 'nokogiri'

# Opens shapes.svg
@doc = Nokogiri::XML(File.open('shapes.svg'))

# Get intervals to display the frames
ins = @doc.xpath('//@in')
outs = @doc.xpath('//@out')
timestamps = @doc.xpath('//@timestamp')
undos = @doc.xpath('//@undo')
images = @doc.xpath('//xmlns:image', 'xmlns' => 'http://www.w3.org/2000/svg')

intervals = (ins + outs + timestamps + undos).to_a.map(&:to_s).map(&:to_f).uniq.sort

# Update image paths since files are saved in ./frames
images.each do |image|
  path = image.attr('xlink:href')
  image.set_attribute('xlink:href', '../' + path)
  image.set_attribute('style', 'visibility:visible')
end

# Creates new file to hold the timestamps of the whiteboard
File.open('whiteboard_timestamps', 'w') {}

# Intervals with a value of -1 do not correspond to a timestamp
intervals = intervals.drop(1) if intervals.first == -1

# Obtain interval range that each frame will be shown for
frame_number = 0
frames = []

intervals.each_cons(2) do |(a, b)|
  frames << [a, b]
end

# Render the visible frame for each interval
frames.each do |frame|
  interval_start = frame[0]
  interval_end = frame[1]

  # Figure out which slide we're currently on
  slide = @doc.xpath("//xmlns:image[@in <= #{interval_start} and #{interval_end} <= @out]", 'xmlns' => 'http://www.w3.org/2000/svg')

  # Get slide information
  slide_id = slide.attr('id').to_s
  width = slide.attr('width').to_s
  height = slide.attr('height').to_s

  x = slide.attr('x').to_s
  y = slide.attr('y').to_s

  # Get slide's canvas
  #canvas = @doc.xpath("//xmlns:g[@class=\"canvas\" and @image=\"#{slide_id}\"]",
  #                    'xmlns' => 'http://www.w3.org/2000/svg', 'xlink' => 'http://www.w3.org/1999/xlink')

  # Render up until interval end
  #draw = canvas.xpath("./xmlns:g[@timestamp < #{interval_end}]")

  draw = @doc.xpath('//xmlns:g[@class="canvas" and @image="' + slide_id.to_s + '"]/xmlns:g[@timestamp < ' + interval_end.to_s + ' and (@undo = -1 or @undo > ' + interval_end.to_s + ')]', 'xmlns' => 'http://www.w3.org/2000/svg')

  #draw.remove_attribute('id')
  #draw.remove_attribute('class')
  #draw.remove_attribute('timestamp')
  #draw.remove_attribute('undo')
  #draw.remove_attribute('shape')

  # Remove redundant shapes
  # shapes = []
  # render = []

  #draw.each do |shape|
  #  shapes << shape.attr('shape').to_s
  # end

  # Add this shape to what will be rendered
  # if draw.length.positive?

  #  shapes.uniq.each do |shape|
  #    selection = draw.select do |drawing|
  #      drawing.attr('shape') == shape && (drawing.attr('undo') == '-1' || drawing.attr('undo').to_s.to_f >= interval_end)
  #    end

  #    unless selection.last.nil?
  #      render << selection.last
  #    end
  #  end
  #end

  # Builds SVG frame
  builder = Nokogiri::XML::Builder.new do |xml|
    xml.svg(width: width, height: height, x: x, y: y, version: '1.1', 'xmlns' => 'http://www.w3.org/2000/svg',
            'xmlns:xlink' => 'http://www.w3.org/1999/xlink') do
      
      # Display background image (optional, FFMpeg doesn't show it...)
      xml << slide.to_s

      # Add annotations
      draw.each do |shape|

        # Make shape visible
        style = shape.attr('style')
        style.sub! 'hidden', 'visible'
        shape.set_attribute('style', style)

        xml << shape.to_s
      end
    end
  end

  # Saves frame as SVG file
  File.open("frames/frame#{frame_number}.svg", 'w') do |file|
    file.write(builder.to_xml)
  end

  # Writes its duration down
  File.open('whiteboard_timestamps', 'a') do |file|
    file.puts "file frames/frame#{frame_number}.svg"
    file.puts "duration #{(interval_end - interval_start).round(1)}"
  end

  frame_number += 1
  puts frame_number
end

# The last image needs to be specified twice, without specifying the duration (FFmpeg quirk)
File.open('whiteboard_timestamps', 'a') do |file|
  file.puts "file frames/frame#{frame_number - 1}.svg"
end
