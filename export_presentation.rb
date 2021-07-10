#!/usr/bin/env ruby
# frozen_string_literal: false

require 'nokogiri'
require 'base64'
require 'zlib'
require 'builder'
require 'fileutils'

require_relative 'lib/interval_tree'
include IntervalTree

start = Time.now

@published_files = File.expand_path('.')

# Creates scratch directories
Dir.mkdir("#{@published_files}/chats") unless File.exist?("#{@published_files}/chats")
Dir.mkdir("#{@published_files}/cursor") unless File.exist?("#{@published_files}/cursor")
Dir.mkdir("#{@published_files}/frames") unless File.exist?("#{@published_files}/frames")
Dir.mkdir("#{@published_files}/timestamps") unless File.exist?("#{@published_files}/timestamps")

# Setting the SVGZ option to true will write less data on the disk.
SVGZ_COMPRESSION = false

# Set this to true if you've recompiled FFmpeg to enable external references. Writes less data on disk and is faster.
FFMPEG_REFERENCE_SUPPORT = false
BASE_URI = FFMPEG_REFERENCE_SUPPORT ? "-base_uri #{@published_files}" : ""

# Video output quality: 0 is lossless, 51 is the worst. Default 23, 18 - 28 recommended
CONSTANT_RATE_FACTOR = 23

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

def convert_whiteboard_shapes(whiteboard)
  # Find shape elements
  whiteboard.xpath('svg/g/g').each do |annotation|
    # Make all annotations visible
    style = annotation.attr('style')
    style.sub! 'visibility:hidden', ''
    annotation.set_attribute('style', style)

    # Convert polls to data schema
    if annotation.attribute('shape').to_s.include? 'poll'
      poll = annotation.element_children.first

      path = "#{@published_files}/#{poll.attribute('href')}"
      poll.remove_attribute('href')

      # Namespace xmlns:xlink is required by FFmpeg
      poll.add_namespace_definition('xlink', 'http://www.w3.org/1999/xlink')

      data = FFMPEG_REFERENCE_SUPPORT ? "file:///#{path}" : base64_encode(path)

      poll.set_attribute('xlink:href', data)
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
    file.write(whiteboard)
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
      path = "#{@published_files}/#{node.attribute('href')}"

      data = FFMPEG_REFERENCE_SUPPORT ? "file:///#{path}" : base64_encode(path)

      slides << WhiteboardSlide.new(data, slide_in, node.attribute('width').to_f, node.attribute('height'))

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

def render_chat(chat_reader)
    messages = []

    chat_reader.each do |node|
        if node.name == 'chattimeline' && node.attribute('target') == 'chat' && node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT
            messages << [node.attribute('in').to_f, node.attribute('name'), node.attribute('message')]
        end
    end

    # Text coordinates on the SVG file - chat window height is 840, + 15 to position text
    svg_x = 0
    svg_y = 855

    svg_width = 8000 # Divisible by 320
    svg_height = 32_760 # Divisible by 15

    # Chat viewbox coordinates
    chat_x = 0
    chat_y = 0

    # Empty string to build <text>...</text> tag from
    text = ""
    overlay_position = []

    messages.each do |message|
        timestamp = message[0]
        name = message[1]
        chat = message[2]

        line_breaks = chat.chars.each_slice(35).map(&:join)

        # Message height equals the line break amount + the line for the name / time + the empty line after
        message_height = (line_breaks.size + 2) * 15

        if svg_y + message_height > svg_height

            svg_y = 855
            svg_x += 320

            chat_x += 320
            chat_y = message_height

        else
            chat_y += message_height

        end

        overlay_position << [timestamp, chat_x, chat_y]

        # Username and chat timestamp
        text << "<text x=\"#{svg_x}\" y=\"#{svg_y}\" font-weight=\"bold\">#{name}    #{Time.at(timestamp.to_f.round(0)).utc.strftime('%H:%M:%S')}</text>"
        svg_y += 15

        # Message text
        line_breaks.each do |line|
            text << "<text x=\"#{svg_x}\" y=\"#{svg_y}\">#{line}</text>"
            svg_y += 15
        end

        svg_y += 15
    end

    # Create SVG chat with all messages. Using Nokogiri's XML Builder so it automatically sanitizes the input
    # Max. dimensions: 8032 x 32767
    # Add 'xmlns' => 'http://www.w3.org/2000/svg' for visual debugging
    builder = Nokogiri::XML::Builder.new do |xml|
        xml.svg(width: svg_width, height: svg_height) {
            xml << "<style>text{font-family: monospace; font-size: 15}</style>"
            xml << text
        }
    end

    # Saves chat as SVG / SVGZ file
    File.open("#{@published_files}/chats/chat.svg", "w") do |file|
        file.write(builder.to_xml)
    end

    File.open("#{@published_files}/timestamps/chat_timestamps", 'w') do |file|
        file.puts "0 overlay@msg x 0, overlay@msg y 0;" if overlay_position.empty?

        overlay_position.each do |chat_state|
            chat_x = chat_state[1]
            chat_y = chat_state[2]

            file.puts "#{chat_state[0]} crop@c x #{chat_x}, crop@c y #{chat_y};"
        end
    end
end

def render_cursor(panzooms, cursor_reader)
    # Create the mouse pointer SVG
    builder = Builder::XmlMarkup.new

    # Add 'xmlns' => 'http://www.w3.org/2000/svg' for visual debugging, remove for faster exports
    builder.svg(width: '16', height: '16') do
        builder.circle(cx: '8', cy: '8', r: '8', fill: 'red')
    end

    File.open("#{@published_files}/cursor/cursor.svg", 'w') do |svg|
        svg.write(builder.target!)
    end
    
    cursor = []
    view_box = '0 0 1600 900'
    timestamps = []
    timestamp = 0

    cursor_reader.each do |node|
        timestamps << node.attribute('timestamp').to_f if node.name == 'event' && node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT
    
        cursor << node.inner_xml if node.name == 'cursor' && node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT
    end

    panzoom_index = 0
    File.open("#{@published_files}/timestamps/cursor_timestamps", 'w') do |file|
        timestamps.each.with_index do |timestamp, frame_number|
        
            if !(panzoom_index >= panzooms.length) && timestamp >= panzooms[panzoom_index].first then
                _, view_box = panzooms[panzoom_index]
                panzoom_index += 1 
                view_box = view_box.split(' ')
            end

            # Get cursor coordinates
            pointer = cursor[frame_number].split

            width = view_box[2].to_f
            height = view_box[3].to_f

            # Calculate original cursor coordinates
            cursor_x = pointer[0].to_f * width
            cursor_y = pointer[1].to_f * height

            # Scaling required to reach target dimensions
            x_scale = 1600 / width
            y_scale = 1080 / height

            # Keep aspect ratio
            scale_factor = [x_scale, y_scale].min

            # Scale
            cursor_x *= scale_factor
            cursor_y *= scale_factor

            # Translate given difference to new on-screen dimensions
            x_offset = (1600 - scale_factor * width) / 2
            y_offset = (1080 - scale_factor * height) / 2

            # Center cursor
            cursor_x -= 8
            cursor_y -= 8

            cursor_x += x_offset
            cursor_y += y_offset

            # Move whiteboard to the right, making space for the chat and webcams
            cursor_x += 320

            # Writes the timestamp and position down
            file.puts "#{timestamp} overlay@m x #{cursor_x.round(3)}, overlay@m y #{cursor_y.round(3)};"
        end
    end
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

# Opens shapes.svg
whiteboard = Nokogiri::XML(File.open("#{@published_files}/shapes.svg")).remove_namespaces!

convert_whiteboard_shapes(whiteboard)

@timestamps, slides, shapes = parse_whiteboard_shapes(Nokogiri::XML::Reader(File.open("#{@published_files}/shapes_modified.svg")))
shapes_interval_tree = IntervalTree::Tree.new(shapes)

# Presentation panzooms
panzooms = parse_panzooms(Nokogiri::XML::Reader(File.open("#{@published_files}/panzooms.xml")))

render_chat(Nokogiri::XML::Reader(File.open("#{@published_files}/slides_new.xml")))
render_cursor(panzooms, Nokogiri::XML::Reader(File.open("#{@published_files}/cursor.xml")))

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

      index = 0
      draw.each do |shape|
        if shape.id != current_id
          current_id = shape.id
          draw_unique << draw[index - 1]
        end

        index += 1
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

render = "ffmpeg -f lavfi -i color=c=white:s=1920x1080 " \
         "-f concat -safe 0 #{BASE_URI} -i #{@published_files}/timestamps/whiteboard_timestamps " \
         "-framerate 10 -loop 1 -i #{@published_files}/cursor/cursor.svg " \
         "-framerate 1 -loop 1 -i #{@published_files}/chats/chat.svg " \
         "-i #{@published_files}/video/webcams.#{VIDEO_EXTENSION} "

render << if deskshare
 "-i #{@published_files}/deskshare/deskshare.#{VIDEO_EXTENSION} -filter_complex " \
 "'[2]sendcmd=f=#{@published_files}/timestamps/cursor_timestamps[cursor];" \
 "[3]sendcmd=f=#{@published_files}/timestamps/chat_timestamps,crop@c=w=320:h=840:x=0:y=0[chat];" \
 "[4]scale=w=320:h=240[webcams];[5]scale=w=1600:h=1080:force_original_aspect_ratio=1[deskshare];" \
 "[0][deskshare]overlay=x=320:y=90[screenshare];" \
 "[screenshare][1]overlay=x=320[slides];" \
 "[slides][cursor]overlay@m[whiteboard];" \
 "[whiteboard][chat]overlay=y=240[chats];" \
 "[chats][webcams]overlay' "

else
  "-filter_complex '[2]sendcmd=f=#{@published_files}/timestamps/cursor_timestamps[cursor];" \
  "[3]sendcmd=f=#{@published_files}/timestamps/chat_timestamps,crop@c=w=320:h=840:x=0:y=0[chat];" \
  "[4]scale=w=320:h=240[webcams];" \
  "[0][1]overlay=x=320[slides];" \
  "[slides][cursor]overlay@m[whiteboard];" \
  "[whiteboard][chat]overlay=y=240[chats];[chats][webcams]overlay' "
end

render << "-c:a aac -crf #{CONSTANT_RATE_FACTOR} -shortest -y #{@published_files}/meeting.mp4"

puts "Beginning to render video"

ffmpeg = system(render)

puts "Finished with code #{ffmpeg}"

finish = Time.now
puts "Exported recording available at #{@published_files}/meeting.mp4. Render time: #{finish - start}"

# Delete the contents of the scratch directories
if ffmpeg then
  FileUtils.rm_rf("#{@published_files}/chats")
  FileUtils.rm_rf("#{@published_files}/cursor")
  FileUtils.rm_rf("#{@published_files}/frames")
  FileUtils.rm_rf("#{@published_files}/timestamps")
  FileUtils.rm("#{@published_files}/shapes_modified.svg") 
end