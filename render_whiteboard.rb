#!/usr/bin/env ruby
# frozen_string_literal: true

require 'nokogiri'
require 'base64'
require 'zlib'

# Track how long the code is taking
start = Time.now

# Opens shapes.svg
@doc = Nokogiri::XML(File.open('shapes.svg')).remove_namespaces!
shape_reader = Nokogiri::XML::Reader(File.open('shapes.svg'))

# Opens panzooms.xml
pan_reader = Nokogiri::XML::Reader(File.open('panzooms.xml'))

view_boxes = []
reader_timestamps = []

# Parse recording intervals
pan_reader.each do |node|
  if node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT then
    if node.name == 'event' then
      reader_timestamps << node.attribute('timestamp').to_f
    end
  
    if node.name == 'viewBox' then
      view_boxes << node.inner_xml
    end
  end
end

# Get array containing [panzoom timestamp, view_box parameter]
panzooms = reader_timestamps.zip(view_boxes)

shape_reader.each do |node|
  if node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT then
    
    if node.name == 'image' then
      reader_timestamps << node.attribute('in').to_f
      reader_timestamps << node.attribute('out').to_f

    end

    if node.name == 'g' && node.attribute('class') == "shape" then
      reader_timestamps << node.attribute('timestamp').to_f
      reader_timestamps << node.attribute('undo').to_f
    end
  end
end

# XPath queries for the images and text fields
images = @doc.xpath('svg/image')
xhtml = @doc.xpath('svg/g/g/switch/foreignObject')

intervals = reader_timestamps.uniq.sort

# Image paths need to follow the URI Data Scheme (for slides and polls)
images.each do |image|
  path = image.attr('href')

  # Open the image
  data = File.open(path).read

  image.set_attribute('href', "data:image/#{File.extname(path).delete('.')};base64,#{Base64.encode64(data)}")
  image.set_attribute('style', 'visibility:visible')
end

# Make all annotations visible
@doc.xpath('svg/g/g').each do |annotation|
  style = annotation.attr('style')
  style.sub! 'hidden', 'visible'

  annotation.set_attribute('style', style)
end

# Convert XHTML to SVG so that text can be shown
xhtml.each do |foreign_object|
  # Get and set style of corresponding group container
  g = foreign_object.parent.parent
  g_style = g.attr('style')
  g.set_attribute('style', "#{g_style};fill:currentcolor")

  text = foreign_object.children.children

  # Obtain X and Y coordinates of the text
  x = foreign_object.attr('x').to_s
  y = foreign_object.attr('y').to_s

  # Preserve the whitespace (seems to be ignored by FFmpeg)
  svg = "<text x=\"#{x}\" y=\"#{y}\" xml:space=\"preserve\">"

  # Add line breaks as <tspan> elements
  text.each do |line|
    if line.to_s == "<br/>"

      svg += "<tspan x=\"#{x}\" dy=\"0.9em\"><br/></tspan>"

    else

      # Make a new line every 40 characters (arbitrary value, SVG does not support auto wrap)
      line_breaks = line.to_s.chars.each_slice(40).map(&:join)

      line_breaks.each do |row|
        svg += "<tspan x=\"#{x}\" dy=\"0.9em\">#{row}</tspan>"
      end

    end
  end

  svg += "</text>"

  g.add_child(svg)

  # Remove the <switch> tag
  foreign_object.parent.remove
end

# Intervals with a value of -1 do not correspond to a timestamp
intervals = intervals.drop(1) if intervals.first == -1

# Obtain interval range that each frame will be shown for
frame_number = 0
frames = []

intervals.each_cons(2) do |(a, b)|
  frames << [a, b]
end

# Render the visible frame for each interval
File.open('timestamps/whiteboard_timestamps', 'w') do |file|
  frames.each do |frame|
    interval_start = frame[0]
    interval_end = frame[1]

    # Query slide we're currently on
    slide = @doc.xpath("svg/image[@in <= #{interval_start} and #{interval_end} <= @out]")

    # Query current viewbox parameter
    # view_box = @pan.xpath("(recording/event[@timestamp <= #{interval_start}]/viewBox/text())[last()]")

    # Find index of the first panzoom coming after the current one
    next_panzoom = panzooms.find_index { |t, _| t > interval_start}
    next_panzoom = panzooms.count if next_panzoom.nil?

    panzooms = panzooms.drop(next_panzoom - 1)
    view_box = panzooms.first[1]

    # Get slide information
    slide_id = slide.attr('id').to_s
    width = slide.attr('width').to_s
    height = slide.attr('height').to_s

    draw = @doc.xpath("svg/g[@class=\"canvas\" and @image=\"#{slide_id}\"]/g[@timestamp < \"#{interval_end}\" and (@undo = \"-1\" or @undo >= \"#{interval_end}\")]")

    # Builds SVG frame
    builder = Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
      # Add 'xmlns' => 'http://www.w3.org/2000/svg' for visual debugging
      xml.svg(width: "1600", height: "1080", viewBox: view_box) do
      
      # Display background image
      xml.image('href': slide.attr('href'), width: width, height: height, preserveAspectRatio: "xMidYMid slice", style: slide.attr('style'))
        
        # Add annotations
        draw.each do |annotation|
          xml << annotation.to_s
        end
        
      end
    end

    # Saves frame as SVG file (for debugging purposes)
    File.open("frames/frame#{frame_number}.svg", 'w') do |file|
      file.write(builder.to_xml)
    end

    # Saves frame as SVGZ file
    File.open("frames/frame#{frame_number}.svgz", 'w') do |file|
      svgz = Zlib::GzipWriter.new(file)
      svgz.write(builder.to_xml)
      svgz.close
    end

    # Write the frame's duration down
    file.puts "file ../frames/frame#{frame_number}.svgz"
    file.puts "duration #{(interval_end - interval_start).round(1)}"

    frame_number += 1
    # puts frame_number
  end

  # The last image needs to be specified twice, without specifying the duration (FFmpeg quirk)
  file.puts "file ../frames/frame#{frame_number - 1}.svgz" if frame_number.positive?
end

# Benchmark
finish = Time.now
puts finish - start