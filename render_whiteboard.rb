# frozen_string_literal: true

require 'nokogiri'

# Opens shapes.svg
@doc = Nokogiri::XML(File.open('shapes.svg'))

# Get intervals to display the frames
ins = @doc.xpath('//@in')
outs = @doc.xpath('//@out')
timestamps = @doc.xpath('//@timestamp')
undos = @doc.xpath('//@undo')

intervals = (ins + outs + timestamps + undos).to_a.map(&:to_s).map(&:to_f).uniq.sort

# Creates new file to hold the timestamps of the whiteboard
File.open('whiteboard_timestamps', 'w') {}

# If a value of -1 does not correspond to a timestamp
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
  slide = @doc.xpath("//*[@in <= #{interval_start} and #{interval_end} <= @out]")

  # Get slide information
  # slideStart = slide.attr('in').to_s.to_f
  # slideEnd = slide.attr('out').to_s.to_f
  slide_id = slide.attr('id').to_s
  width = slide.attr('width').to_s
  height = slide.attr('height').to_s

  x = slide.attr('x').to_s
  y = slide.attr('y').to_s

  # Get slide's canvas
  canvas = @doc.xpath("//xmlns:g[@class=\"canvas\" and @image=\"#{slide_id}\"]",
                      'xmlns' => 'http://www.w3.org/2000/svg', 'xlink' => 'http://www.w3.org/1999/xlink')

  # Render up until interval end
  draw = canvas.xpath("./xmlns:g[@timestamp < #{interval_end}]")

  # Remove redundant shapes
  shapes = []
  render = []

  draw.each do |shape|
    shapes << shape.attr('shape').to_s
  end

  # Add this shape to what will be rendered
  if draw.length.positive?

    shapes.uniq.each do |shape|
      selection = draw.select do |drawing|
        drawing.attr('shape') == shape && (drawing.attr('undo') == '-1' || drawing.attr('undo').to_s.to_f >= interval_end)
      end
      render << selection.last
    end

  end

  render.each do |shape|
    next if shape.nil?

    style = shape.attr('style')
    style.sub! 'hidden', 'visible'
    shape.set_attribute('style', style)
  end

  # Builds SVG frame
  builder = Nokogiri::XML::Builder.new do |xml|
    xml.svg(width: width, height: height, x: x, y: y, version: '1.1', 'xmlns' => 'http://www.w3.org/2000/svg',
            'xmlns:xlink' => 'http://www.w3.org/1999/xlink') do
      render.each do |shape|
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
end

# The last image needs to be specified twice, without specifying the duration (FFmpeg quirk)
File.open('whiteboard_timestamps', 'a') do |file|
  file.puts "file frames/frame#{frame_number - 1}.svg"
end
