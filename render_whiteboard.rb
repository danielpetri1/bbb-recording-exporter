#!/usr/bin/env ruby
# frozen_string_literal: false

require 'nokogiri'
require 'base64'
require 'zlib'
require 'builder'

require_relative 'lib/interval_tree'
include IntervalTree

start = Time.now

# Flags
SVGZ_COMPRESSION = false

FILE_EXTENSION = SVGZ_COMPRESSION ? "svgz" : "svg"

WhiteboardElement = Struct.new(:begin, :end, :value)
WhiteboardSlide = Struct.new(:href, :begin, :width, :height)

def base64_encode(path)
  data = File.open(path).read
  "data:image/#{File.extname(path).delete('.')};base64,#{Base64.encode64(data)}"
end

def svg_export(draw, view_box, slide_href, width, height, frame_number)
  # Builds SVG frame
  builder = Builder::XmlMarkup.new
  # Add 'xmlns' => 'http://www.w3.org/2000/svg' for visual debugging, remove for faster exports
  builder.svg(width: "1600", height: "1080", viewBox: view_box, 'xmlns' => 'http://www.w3.org/2000/svg') do
    # Display background image
    builder.image(href: slide_href, width: width, height: height, preserveAspectRatio: "xMidYMid slice")

    # Adds annotations
    draw.each do |shape|
      builder << shape.value
    end
  end

  File.open("frames/frame#{frame_number}.#{FILE_EXTENSION}", "w") do |svg|
    if SVGZ_COMPRESSION
      svgz = Zlib::GzipWriter.new(svg)
      svgz.write(builder.target!)
      svgz.close

    else
      svg.write(builder.target!)
    end
  end
end

def convert_whiteboard_shapes(doc)
  # Find shape elements
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
end

def parse_panzooms(pan_reader)
  panzooms = []
  timestamp = 0

  pan_reader.each do |node|
    next unless node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT

    timestamp = node.attribute('timestamp').to_f if node.name == 'event'

    if node.name == 'viewBox'
      panzooms << [timestamp, node.inner_xml]
      @timestamps << timestamp
    end
  end

  panzooms
end

def parse_whiteboard_shapes(shape_reader)
  slide_in = 0
  slide_out = 0

  timestamps = []
  slides = []
  shapes = []

  shape_reader.each do |node|
    next unless node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT

    if node.name == 'image' && node.attribute('class') == 'slide'

      slide_in = node.attribute('in').to_f
      slide_out = node.attribute('out').to_f

      timestamps << node.attribute('in').to_f
      timestamps << node.attribute('out').to_f

      # Image paths need to follow the URI Data Scheme (for slides and polls)
      path = node.attribute('href')
      slides << WhiteboardSlide.new(base64_encode(path), slide_in, node.attribute('width').to_f, node.attribute('height'))

    end

    next unless node.name == 'g' && node.attribute('class') == "shape"

    shape_timestamp = node.attribute('timestamp').to_f
    shape_undo = node.attribute('undo').to_f

    shape_undo = slide_out if shape_undo.negative?

    shape_enter = [[shape_timestamp, slide_in].max, slide_out].min
    shape_leave = [[shape_undo, slide_in].max, slide_out].min

    timestamps << shape_enter
    timestamps << shape_leave

    xml = "<g style=\"#{node.attribute('style')}\">#{node.inner_xml}</g>"
    shapes << WhiteboardElement.new(shape_enter, shape_leave, xml)
  end

  [timestamps, slides, shapes]
end

# Opens shapes.svg
doc = Nokogiri::XML(File.open('shapes.svg')).remove_namespaces!

convert_whiteboard_shapes(doc)

# Parse the converted whiteboard shapes
@timestamps, slides, shapes = parse_whiteboard_shapes(Nokogiri::XML::Reader(File.open('shapes_modified.svg')))

shapes_interval_tree = IntervalTree::Tree.new(shapes)

# Slide panzooms as array containing [panzoom timestamp, view_box parameter]
panzooms = parse_panzooms(Nokogiri::XML::Reader(File.open('panzooms.xml')))

# Create frame intervals with starting time 0
intervals = @timestamps.uniq.sort
intervals = intervals.drop(1) if intervals.first == -1

frame_number = 0
frames = []

intervals.each_cons(2) do |(a, b)|
  frames << [a, b]
end

# Render the visible frame for each interval
File.open('timestamps/whiteboard_timestamps', 'w') do |file|
  # Example slide to instantiate variables
  width = 1600
  height = 900
  view_box = '0 0 1600 900'
  slide_href = 'deskshare/deskshare.png'

  frames.each do |frame|
    interval_start, interval_end = frame

    # Get view_box parameter of the current slide
    _, view_box = panzooms.shift if !panzooms.empty? && interval_start >= panzooms.first.first

    if !slides.empty? && interval_start >= slides.first.begin
      slide = slides.shift

      slide_href = slide.href
      width = slide.width
      height = slide.height
    end

    draw = shapes_interval_tree.search(interval_start, unique: false)
    draw = [] if draw.nil?

    svg_export(draw, view_box, slide_href, width, height, frame_number)

    # Write the frame's duration down
    file.puts "file ../frames/frame#{frame_number}.#{FILE_EXTENSION}"
    file.puts "duration #{(interval_end - interval_start).round(1)}"

    frame_number += 1
  end

  # The last image needs to be specified twice, without specifying the duration (FFmpeg quirk)
  file.puts "file ../frames/frame#{frame_number - 1}.svg" if frame_number.positive?
end

# Benchmark
finish = Time.now
puts finish - start