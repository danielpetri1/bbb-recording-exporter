#!/usr/bin/env ruby
# frozen_string_literal: true

require 'nokogiri'
require 'base64'
require 'zlib'
require 'itree'

def base64_encode(path)
  data = File.open(path).read
  data = "data:image/#{File.extname(path).delete('.')};base64,#{Base64.encode64(data)}"
  return data
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
  if annotation.attribute('shape').to_s.include? 'poll' then
    poll = annotation.element_children.first
    path = poll.attribute('href')
    poll.set_attribute('href', base64_encode(path))
  end

  # Convert XHTML to SVG so that text can be shown
  if annotation.attribute('shape').to_s.include? 'text' then

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

    annotation.add_child(svg)

    # Remove the <switch> tag
    annotation.xpath('switch').remove
  end
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

slides = []
slides_interval_tree = Intervals::Tree.new

shapes = []
shapes_interval_tree = Intervals::Tree.new

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

slide_out = 0
slide_in = 0

shape_reader.each do |node|
  if node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT then
    
    if node.name == 'image' && node.attribute('class') == 'slide' then
      slide_in = node.attribute('in').to_f
      slide_out = node.attribute('out').to_f

      reader_timestamps << slide_in
      reader_timestamps << slide_out

      # Image paths need to follow the URI Data Scheme (for slides and polls)
      path = node.attribute('href')

      # slides << [node.attribute('id').to_s, base64_encode(path), slide_in, slide_out, node.attribute('width').to_f, node.attribute('height')]

      slides_interval_tree.insert(slide_in, slide_out, [base64_encode(path), node.attribute('width').to_f, node.attribute('height')])

    end

    if node.name == 'g' && node.attribute('class') == "shape" then
      
      shape_timestamp = node.attribute('timestamp').to_f
      shape_undo = node.attribute('undo').to_f
      shape_id = node.attribute('id').split('-').first

      reader_timestamps << shape_timestamp
      reader_timestamps << shape_undo

      if shape_undo < 0 then
        shape_undo = slide_out
      end

      shape_enter = [[shape_timestamp, slide_in].max, slide_out].min
      shape_leave = [[shape_undo, slide_in].max, slide_out].min

      #if shape_id == 'image5' then
        #puts "timestamp " + shape_timestamp.to_s
        #puts "in " + slide_in.to_s
        #puts "-----"
        #puts "undo " + shape_undo.to_s
        #puts "out " + slide_out.to_s
        #puts node.attribute('id')
        #puts "===="

        #puts shape_enter < shape_leave
        #puts shape_enter
        #puts shape_leave
        #puts "----"

        #puts node.inner_xml
        #shapes_interval_tree.insert(shape_enter, shape_leave, "A")
      #end
      
      # shapes << [shape_id, shape_timestamp, shape_undo, node.attribute('style'), node.inner_xml]

      if shape_enter < shape_leave then
        shapes_interval_tree.insert(shape_enter, shape_leave, [node.attribute('style'), node.inner_xml])
      end

    end
  end
end

puts shapes_interval_tree.stab(48.0, 49.7)[0].data
i = 1/0
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
    next_panzoom = panzooms.find_index { |t, _| t > interval_start}
    next_panzoom = panzooms.count if next_panzoom.nil?

    panzooms = panzooms.drop(next_panzoom - 1)
    view_box = panzooms.first[1]

    # Get slide information
    slide = slides_interval_tree.stab(interval_start, interval_end)
    
    slide_in, slide_out = slide.first.scores
    slide_href, slide_width, slide_height = slide.first.data
  
    draw = shapes_interval_tree.stab(interval_start, interval_end)

    # puts interval_start
    # puts interval_end

    # puts draw.length

    # draw.each do |annotation|
      # puts annotation.data
      # puts "===="
    # end

    #draw = shapes.select { |id, t, undo, _, _| id == slide_id && t < interval_end && (undo == -1 || undo >= interval_end)}

    # draw = @doc.xpath("svg/g[@class=\"canvas\" and @image=\"#{slide_id}\"]/g[@timestamp < \"#{interval_end}\" and (@undo = \"-1\" or @undo >= \"#{interval_end}\")]")

    # Builds SVG frame
    builder = Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
      # Add 'xmlns' => 'http://www.w3.org/2000/svg' for visual debugging
      xml.svg(width: "1600", height: "1080", viewBox: view_box, 'xmlns' => 'http://www.w3.org/2000/svg') do
      
        # Display background image
        xml.image('href': slide_href, width: slide_width, height: slide_height, preserveAspectRatio: "xMidYMid slice")
      
        # Adds annotations
        #puts "Interval start: " + interval_start.to_s
        #puts "Interval end: " + interval_end.to_s

        draw.each do |annotation|
          xml.g('style': annotation.data.first) do
              #puts annotation.scores
              #puts "-----"
              

              xml << annotation.data[1]
          end
        end
        #puts "==="
      end
    end

    # Saves frame as SVG file (for debugging purposes)
    File.open("frames/frame#{frame_number}.svg", 'w') do |file|
      file.write(builder.to_xml)
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
    #if slide_out == interval_end && !draw.empty? then

      # next_canvas = shapes.find_index {|id, _, _, _, _| slide_id != id}
      # next_canvas = 0 if next_canvas.nil?

      # shapes = shapes.slice!(next_canvas, shapes.length - 1)

    #end
    #slides_interval_tree.remove(interval_start, interval_end)
    #shapes_interval_tree.remove(interval_start, interval_end)
  end

  # The last image needs to be specified twice, without specifying the duration (FFmpeg quirk)
  file.puts "file ../frames/frame#{frame_number - 1}.svg" if frame_number.positive?
end

# Benchmark
finish = Time.now
puts finish - start
