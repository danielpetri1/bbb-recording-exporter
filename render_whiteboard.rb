#!/usr/bin/env ruby
# frozen_string_literal: false

require 'nokogiri'
require 'base64'
require 'zlib'
require 'itree'

def base64_encode(path)
  data = File.open(path).read
  "data:image/#{File.extname(path).delete('.')};base64,#{Base64.encode64(data)}"
end

# Track how long the code is taking
start = Time.now

# Opens shapes.svg
doc = Nokogiri::XML(File.open('shapes.svg')).remove_namespaces!

# Make necessary changes to shapes.svg
doc.xpath('svg/g/g').each do |annotation|
  # Make all annotations visible
  style = annotation.attr('style')
  style.sub! 'visibility:hidden', ''
  annotation.set_attribute('style', style)

  # Convert polls to data schema
  if annotation.attribute('shape').to_s.include? 'poll'
    poll = annotation.element_children.first
    path = poll.attribute('href')
    poll.set_attribute('href', base64_encode(path))
  end

  # Convert XHTML to SVG so that text can be shown
  next unless annotation.attribute('shape').to_s.include? 'text'

  # Change text style so color is rendered
  text_style = annotation.attr('style')
  annotation.set_attribute('style', "#{text_style};fill:currentcolor")

  foreign_object = annotation.xpath('switch/foreignObject')

  # Obtain X and Y coordinates of the text
  x = foreign_object.attr('x').to_s
  y = foreign_object.attr('y').to_s

  # Preserve the whitespace
  svg = "<text x=\"#{x}\" y=\"#{y}\" xml:space=\"preserve\">"

  text = foreign_object.children.children

  # Add line breaks as <tspan> elements
  text.each do |line|
    if line.to_s == "<br/>"
      svg << "<tspan x=\"#{x}\" dy=\"0.9em\"><br/></tspan>"

    else

      # Make a new line every 40 characters (arbitrary value, SVG does not support auto wrap)
      line_breaks = line.to_s.chars.each_slice(40).map(&:join)

      line_breaks.each do |row|
        svg << "<tspan x=\"#{x}\" dy=\"0.9em\">#{row}</tspan>"
      end

      end
  end

  svg << "</text>"

  annotation.add_child(svg)

  # Remove the <switch> tag
  annotation.xpath('switch').remove
end

# Save new shapes.svg copy
File.open("shapes_modified.svg", 'w') do |file|
  file.write(doc)
end

# SVG / XML readers for shapes and panzooms
shape_reader = Nokogiri::XML::Reader(File.open('shapes_modified.svg'))
pan_reader = Nokogiri::XML::Reader(File.open('panzooms.xml'))

view_boxes = []
reader_timestamps = []

slides_interval_tree = Intervals::Tree.new
shapes_interval_tree = Intervals::Tree.new

# Parse recording intervals
pan_reader.each do |node|
  next unless node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT
  reader_timestamps << node.attribute('timestamp').to_f if node.name == 'event'

  view_boxes << node.inner_xml if node.name == 'viewBox'
end

# Get array containing [panzoom timestamp, view_box parameter]
panzooms = reader_timestamps.zip(view_boxes)

slide_out = 0
slide_in = 0

shape_reader.each do |node|
  next unless node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT

  if node.name == 'image' && node.attribute('class') == 'slide'
    slide_in = node.attribute('in').to_f
    slide_out = node.attribute('out').to_f

    reader_timestamps << slide_in
    reader_timestamps << slide_out

    # Image paths need to follow the URI Data Scheme (for slides and polls)
    path = node.attribute('href')

    slides_interval_tree.insert(slide_in, slide_out, [base64_encode(path), node.attribute('width').to_f, node.attribute('height')])

  end

  next unless node.name == 'g' && node.attribute('class') == "shape"

  shape_timestamp = node.attribute('timestamp').to_f
  shape_undo = node.attribute('undo').to_f

  reader_timestamps << shape_timestamp
  reader_timestamps << shape_undo

  shape_undo = slide_out if shape_undo.negative?

  shape_enter = [[shape_timestamp, slide_in].max, slide_out].min
  shape_leave = [[shape_undo, slide_in].max, slide_out].min

  # Itree unfortunately does not return multiple matches for the same interval 
  update = shapes_interval_tree.stab(shape_enter, shape_leave)

  xml = "<g style=\"#{node.attribute('style')}\">#{node.inner_xml}</g>"  

  update.each do |annotation|
    if annotation.scores[0] == shape_enter && annotation.scores[1] == shape_leave then
      xml << annotation.data
      shapes_interval_tree.remove(shape_enter, shape_leave)
    end
  end

  shapes_interval_tree.insert(shape_enter, shape_leave, xml) if shape_enter < shape_leave
end

intervals = reader_timestamps.uniq.sort

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
    # slide = @doc.xpath("svg/image[@in <= #{interval_start} and #{interval_end} <= @out]")

    # Query current viewbox parameter
    # view_box = @pan.xpath("(recording/event[@timestamp <= #{interval_start}]/viewBox/text())[last()]")

    # Find index of the first panzoom coming after the current one
    next_panzoom = panzooms.find_index { |t, _| t > interval_start }
    next_panzoom = panzooms.count if next_panzoom.nil?

    panzooms = panzooms.drop(next_panzoom - 1)
    view_box = panzooms.first[1]

    # Get slide information
    slide = slides_interval_tree.stab(interval_start, interval_end)

    slide_in, slide_out = slide.first.scores
    slide_href, slide_width, slide_height = slide.first.data

    draw = shapes_interval_tree.stab(interval_start, interval_end)

    # Builds SVG frame
    builder = Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
      # Add 'xmlns' => 'http://www.w3.org/2000/svg' for visual debugging
      xml.svg(width: "1600", height: "1080", viewBox: view_box, 'xmlns' => 'http://www.w3.org/2000/svg') do
        # Display background image
        xml.image(href: slide_href, width: slide_width, height: slide_height, preserveAspectRatio: "xMidYMid slice")

        # Adds annotations
        # puts "Interval start: " + interval_start.to_s
        # puts "Interval end: " + interval_end.to_s

          draw.each do |annotation|
            xml << annotation.data
          end
      end
    end

    # Saves frame as SVG file (for debugging purposes)
    File.open("frames/frame#{frame_number}.svg", 'w') do |svg|
      svg.write(builder.to_xml)
    end

    # Saves frame as SVGZ file
    # File.open("frames/frame#{frame_number}.svgz", 'w') do |file|
    # svgz = Zlib::GzipWriter.new(file)
    # svgz.write(builder.to_xml)
    # svgz.close
    # end

    # Write the frame's duration down
    file.puts "file ../frames/frame#{frame_number}.svg"
    file.puts "duration #{(interval_end - interval_start).round(1)}"

    frame_number += 1

    # Remove canvas once we're done with it
    #slides_interval_tree.remove(interval_start, interval_end)
    #shapes_interval_tree.remove(interval_start, interval_end)
  end

  # The last image needs to be specified twice, without specifying the duration (FFmpeg quirk)
  file.puts "file ../frames/frame#{frame_number - 1}.svg" if frame_number.positive?
end

# Benchmark
finish = Time.now
puts finish - start
