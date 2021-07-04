#!/usr/bin/env ruby
# frozen_string_literal: false

require 'nokogiri'
require 'base64'
require 'zlib'
require 'builder'

require_relative 'lib/interval_tree'
include IntervalTree

start = Time.now

@published_files = File.expand_path('.')

# Flags
SVGZ_COMPRESSION = false

FILE_EXTENSION = SVGZ_COMPRESSION ? "svgz" : "svg"
VIDEO_EXTENSION = File.file?("#{@published_files}/video/webcams.mp4") ? "mp4" : "webm"

# Leave it as false for BBB >= 2.3 as it stopped supporting live whiteboard
REMOVE_REDUNDANT_SHAPES = false

WhiteboardElement = Struct.new(:begin, :end, :value, :id)
WhiteboardSlide = Struct.new(:href, :begin, :width, :height)

def base64_encode(path)
  data = File.open(path).read
  "data:image/#{File.extname(path).delete('.')};base64,#{Base64.strict_encode64(data)}"
end

def svg_export(draw, view_box, slide_href, width, height, frame_number)
  # Builds SVG frame
  builder = Builder::XmlMarkup.new

  # FFmpeg unfortunately seems to require the xmlns:xmlink namespace. Add 'xmlns' => 'http://www.w3.org/2000/svg' for visual debugging
  builder.svg(width: "1600", height: "1080", viewBox: view_box, 'xmlns:xlink' => 'http://www.w3.org/1999/xlink') do
    # Display background image
    builder.image('xlink:href': slide_href, width: width, height: height, preserveAspectRatio: "xMidYMid slice")

    # Adds annotations
    draw.each do |shape|
      builder << shape.value
    end
  end

  File.open("#{@published_files}/frames/frame#{frame_number}.#{FILE_EXTENSION}", "w") do |svg|
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
      poll.remove_attribute('href')

      # Namespace xmlns:xlink is required by FFmpeg
      poll.add_namespace_definition('xlink', 'http://www.w3.org/1999/xlink')
      poll.set_attribute('xlink:href', base64_encode("#{@published_files}/#{path}"))
    end

    # Convert XHTML to SVG so that text can be shown
    next unless annotation.attribute('shape').to_s.include? 'text'

    # Change text style so color is rendered
    text_style = annotation.attr('style')

    # The text_color variable may not be required depending on your FFmpeg version
    text_color = text_style.split(';').first.split(':')[1]
    annotation.set_attribute('style', "#{text_style};fill:currentcolor")

    foreign_object = annotation.xpath('switch/foreignObject')

    # Obtain X and Y coordinates of the text
    x = foreign_object.attr('x').to_s
    y = foreign_object.attr('y').to_s

    # Preserve the whitespace
    svg = "<text x=\"#{x}\" y=\"#{y}\" xml:space=\"preserve\" fill=\"#{text_color}\">"

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
  File.open("#{@published_files}/shapes_modified.svg", 'w') do |file|
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
      slides << WhiteboardSlide.new(base64_encode("#{@published_files}/#{path}"), slide_in, node.attribute('width').to_f, node.attribute('height'))

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
    id = node.attribute('shape').split('-').last

    shapes << WhiteboardElement.new(shape_enter, shape_leave, xml, id)
  end

  [timestamps, slides, shapes]
end

# Opens shapes.svg
doc = Nokogiri::XML(File.open("#{@published_files}/shapes.svg")).remove_namespaces!

convert_whiteboard_shapes(doc)

# Parse the converted whiteboard shapes
@timestamps, slides, shapes = parse_whiteboard_shapes(Nokogiri::XML::Reader(File.open("#{@published_files}/shapes_modified.svg")))

shapes_interval_tree = IntervalTree::Tree.new(shapes)

# Slide panzooms as array containing [panzoom timestamp, view_box parameter]
panzooms = parse_panzooms(Nokogiri::XML::Reader(File.open("#{@published_files}/panzooms.xml")))

# Create frame intervals with starting time 0
intervals = @timestamps.uniq.sort
intervals = intervals.drop(1) if intervals.first == -1

frame_number = 0
frames = []

intervals.each_cons(2) do |(a, b)|
  frames << [a, b]
end

# Render the visible frame for each interval
File.open("#{@published_files}/timestamps/whiteboard_timestamps", 'w') do |file|
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

    draw = shapes_interval_tree.search(interval_start, unique: false, sort: false)
    draw = [] if draw.nil?

    if REMOVE_REDUNDANT_SHAPES && !draw.empty?
      draw_unique = []
      current_id = draw.first.id

      draw.each_with_index do |shape, index|
        if shape.id != current_id
          current_id = shape.id
          draw_unique << draw[index - 1]
        end
      end

      draw_unique << draw.last
      draw = draw_unique
    end

    svg_export(draw, view_box, slide_href, width, height, frame_number)

    # Write the frame's duration down
    file.puts "file ../frames/frame#{frame_number}.#{FILE_EXTENSION}"
    file.puts "duration #{(interval_end - interval_start).round(1)}"

    frame_number += 1
  end

  # The last image needs to be specified twice, without specifying the duration (FFmpeg quirk)
  file.puts "file ../frames/frame#{frame_number - 1}.svg" if frame_number.positive?
end

finish = Time.now

puts "Finished rendering whiteboard. Total: #{finish - start}"

start = Time.now

# Determine if video had screensharing
deskshare = File.file?("#{@published_files}/deskshare/deskshare.#{VIDEO_EXTENSION}")

if deskshare
  render = "ffmpeg -f lavfi -i color=c=white:s=1920x1080 " \
 "-f concat -safe 0 -i #{@published_files}/timestamps/whiteboard_timestamps " \
 "-framerate 10 -loop 1 -i #{@published_files}/cursor/cursor.svg " \
 "-framerate 1 -loop 1 -i #{@published_files}/chats/chat.#{FILE_EXTENSION} " \
 "-i #{@published_files}/video/webcams.#{VIDEO_EXTENSION} " \
 "-i #{@published_files}/deskshare/deskshare.#{VIDEO_EXTENSION} -filter_complex " \
 "'[2]sendcmd=f=#{@published_files}/timestamps/cursor_timestamps[cursor];[3]sendcmd=f=#{@published_files}/timestamps/chat_timestamps,crop@c=w=320:h=840:x=0:y=0[chat];[4]scale=w=320:h=240[webcams];[5]scale=w=1600:h=1080:force_original_aspect_ratio=1[deskshare];[0][deskshare]overlay=x=320:y=90[screenshare];[screenshare][1]overlay=x=320[slides];[slides][cursor]overlay@m[whiteboard];[whiteboard][chat]overlay=y=240[chats];[chats][webcams]overlay' " \
 "-c:a aac -shortest -y #{@published_files}/meeting.mp4"
else
  render = "ffmpeg -f lavfi -i color=c=white:s=1920x1080 " \
 "-f concat -safe 0 -i #{@published_files}/timestamps/whiteboard_timestamps " \
 "-framerate 10 -loop 1 -i #{@published_files}/cursor/cursor.svg " \
 "-framerate 1 -loop 1 -i #{@published_files}/chats/chat.#{FILE_EXTENSION} " \
 "-i #{@published_files}/video/webcams.#{VIDEO_EXTENSION} -filter_complex " \
 "'[2]sendcmd=f=#{@published_files}/timestamps/cursor_timestamps[cursor];[3]sendcmd=f=#{@published_files}/timestamps/chat_timestamps,crop@c=w=320:h=840:x=0:y=0[chat];[4]scale=w=320:h=240[webcams];[0][1]overlay=x=320[slides];[slides][cursor]overlay@m[whiteboard];[whiteboard][chat]overlay=y=240[chats];[chats][webcams]overlay' " \
 "-c:a aac -shortest -y #{@published_files}/meeting.mp4"
end

puts "Beginning to render video"

system(render)

finish = Time.now
puts "Exported recording available at #{@published_files}/meeting.mp4. Render time: #{finish - start}"

# Delete the contents of the scratch directories (race conditions)
# FileUtils.rm_rf("#{@published_files}/chats")
# FileUtils.rm_rf("#{@published_files}/cursor")
# FileUtils.rm_rf("#{@published_files}/frames")
# FileUtils.rm_rf("#{@published_files}/timestamps")