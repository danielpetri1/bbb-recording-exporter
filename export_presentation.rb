#!/usr/bin/env ruby
# frozen_string_literal: false

require "nokogiri"
require "base64"
require "zlib"
require "builder"
require "fileutils"
require "loofah"

require_relative "lib/interval_tree"
include IntervalTree

@published_files = File.expand_path(".")

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
  whiteboard.xpath("svg/g/g").each do |annotation|
    # Make all annotations visible
    style = annotation.attr("style")
    style.sub! "visibility:hidden", ""
    annotation.set_attribute("style", style)

    shape = annotation.attribute("shape").to_s
    # Convert polls to data schema
    if shape.include? "poll"
      poll = annotation.element_children.first

      path = "#{@published_files}/#{poll.attribute('href')}"
      poll.remove_attribute("href")

      # Namespace xmlns:xlink is required by FFmpeg
      poll.add_namespace_definition("xlink", "http://www.w3.org/1999/xlink")

      data = FFMPEG_REFERENCE_SUPPORT ? "file:///#{path}" : base64_encode(path)

      poll.set_attribute("xlink:href", data)
    end

    # Convert XHTML to SVG so that text can be shown
    next unless shape.include? "text"

    # The text_color variable may not be required depending on your FFmpeg version
    text_color = style.split(";").first.split(":")[1].to_s
    annotation.set_attribute("style", "#{style};fill:currentcolor")

    foreign_object = annotation.xpath("switch/foreignObject")

    # Obtain X and Y coordinates of the text
    x = foreign_object.attr("x").to_s
    y = foreign_object.attr("y").to_s

    text = foreign_object.children.children

    builder = Builder::XmlMarkup.new
    builder.text(x: x, y: y, fill: text_color, "xml:space" => "preserve") do
      text.each do |line|
        line = line.to_s

        if line == "<br/>"
          builder.tspan(x: x, dy: "0.9em") { builder << "<br/>" }
        else
          # Make a new line every 40 characters (arbitrary value, SVG does not support auto wrap)
          line_breaks = line.chars.each_slice(40).map(&:join)

          line_breaks.each do |row|
            builder.tspan(x: x, dy: "0.9em") { builder << row }
          end
        end
      end
    end

    annotation.add_child(builder.target!)

    # Remove the <switch> tag
    annotation.xpath("switch").remove
  end

  # Save new shapes.svg copy
  File.open("#{@published_files}/shapes_modified.svg", "w") do |file|
    file.chmod(0o600)
    file.write(whiteboard)
  end
end

def parse_panzooms(pan_reader, timestamps)
  panzooms = []
  timestamp = 0

  pan_reader.each do |node|
    next unless node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT
    node_name = node.name

    timestamp = node.attribute("timestamp").to_f if node_name == "event"

    if node_name == "viewBox"
      panzooms << [timestamp, node.inner_xml]
      timestamps << timestamp
    end
  end

  [panzooms, timestamps]
end

def parse_whiteboard_shapes(shape_reader)
  slide_in = 0
  slide_out = 0

  shapes = []
  slides = []
  timestamps = []

  shape_reader.each do |node|
    next unless node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT

    node_name = node.name
    node_class = node.attribute("class")

    if node_name == "image" && node_class == "slide"
      slide_in = node.attribute("in").to_f
      slide_out = node.attribute("out").to_f

      timestamps << slide_in
      timestamps << slide_out

      # Image paths need to follow the URI Data Scheme (for slides and polls)
      path = "#{@published_files}/#{node.attribute('href')}"

      data = FFMPEG_REFERENCE_SUPPORT ? "file:///#{path}" : base64_encode(path)

      slides << WhiteboardSlide.new(data, slide_in, node.attribute("width").to_f, node.attribute("height"))
    end

    next unless node_name == "g" && node_class == "shape"

    shape_timestamp = node.attribute("timestamp").to_f
    shape_undo = node.attribute("undo").to_f

    shape_undo = slide_out if shape_undo.negative?

    shape_enter = [[shape_timestamp, slide_in].max, slide_out].min
    shape_leave = [[shape_undo, slide_in].max, slide_out].min

    timestamps << shape_enter
    timestamps << shape_leave

    xml = "<g style=\"#{node.attribute('style')}\">#{node.inner_xml}</g>"
    id = node.attribute("shape").split("-").last

    shapes << WhiteboardElement.new(shape_enter, shape_leave, xml, id)
  end

  [shapes, slides, timestamps]
end

def render_chat(chat_reader)
  messages = []

  chat_reader.each do |node|
    next unless node.name == "chattimeline" && node.attribute("target") == "chat" && node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT
    # Scrub message to prevent HTML e.g. from links from breaking XML Builder
    safe_message = Loofah.fragment(node.attribute("message")).scrub!(:strip)
    messages << [node.attribute("in").to_f, node.attribute("name"), safe_message.text]
  end

  # Text coordinates on the SVG file - chat window height is 840, + 15 to position text
  svg_x = 0
  svg_y = 855

  svg_width = 8000 # Divisible by 320
  svg_height = 32_760 # Divisible by 15

  # Chat viewbox coordinates
  chat_x = 0
  chat_y = 0

  overlay_position = []

  # Create SVG chat with all messages
  # Max. dimensions: 8032 x 32767
  # Add 'xmlns' => 'http://www.w3.org/2000/svg' for visual debugging
  builder = Builder::XmlMarkup.new
  builder.svg(width: svg_width, height: svg_height) do
    builder.style { builder << "text{font-family: monospace; font-size: 15}" }

    messages.each do |timestamp, name, chat|
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
      builder.text(x: svg_x, y: svg_y, "font-weight" => "bold") { builder << "#{name}    #{Time.at(timestamp.to_f.round(0)).utc.strftime('%H:%M:%S')}" }
      svg_y += 15

      # Message text
      line_breaks.each do |line|
        builder.text(x: svg_x, y: svg_y) { builder << line.to_s }
        svg_y += 15
      end

      svg_y += 15
    end
  end

  # Saves chat as SVG / SVGZ file
  File.open("#{@published_files}/chats/chat.svg", "w") do |file|
    file.chmod(0o600)
    file.write(builder.target!)
  end

  File.open("#{@published_files}/timestamps/chat_timestamps", "w") do |file|
    file.chmod(0o600)
    file.puts "0 overlay@msg x 0, overlay@msg y 0;" if overlay_position.empty?

    overlay_position.each do |timestamp, chat_x, chat_y|
      file.puts "#{timestamp} crop@c x #{chat_x}, crop@c y #{chat_y};"
    end
  end
end

def render_cursor(panzooms, cursor_reader)
  # Create the mouse pointer SVG
  builder = Builder::XmlMarkup.new

  # Add 'xmlns' => 'http://www.w3.org/2000/svg' for visual debugging, remove for faster exports
  builder.svg(width: "16", height: "16") do
    builder.circle(cx: "8", cy: "8", r: "8", fill: "red")
  end

  File.open("#{@published_files}/cursor/cursor.svg", "w") do |svg|
    svg.chmod(0o600)
    svg.write(builder.target!)
  end

  cursor = []
  timestamps = []
  view_box = ""

  cursor_reader.each do |node|
    node_name = node.name
    is_element = node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT

    timestamps << node.attribute("timestamp").to_f if node_name == "event" && is_element

    cursor << node.inner_xml if node_name == "cursor" && is_element
  end

  panzoom_index = 0
  File.open("#{@published_files}/timestamps/cursor_timestamps", "w") do |file|
    file.chmod(0o600)
    timestamps.each.with_index do |timestamp, frame_number|
      panzoom = panzooms[panzoom_index]

      if panzoom_index < panzooms.length && timestamp >= panzoom.first
        _, view_box = panzoom
        panzoom_index += 1
        view_box = view_box.split
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

def render_video
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

  system(render)
end

def render_whiteboard(panzooms, slides, shapes, timestamps)
  shapes_interval_tree = IntervalTree::Tree.new(shapes)

  # Create frame intervals with starting time 0
  intervals = timestamps.uniq.sort
  intervals = intervals.drop(1) if intervals.first == -1

  frame_number = 0
  frames = []

  intervals.each_cons(2) do |(a, b)|
    frames << [a, b]
  end

  # Render the visible frame for each interval
  File.open("#{@published_files}/timestamps/whiteboard_timestamps", "w") do |file|
    file.chmod(0o600)
    slide = slides.first

    frames.each do |interval_start, interval_end|
      # Get view_box parameter of the current slide
      _, view_box = panzooms.shift if !panzooms.empty? && interval_start >= panzooms.first.first

      slide = slides.shift if !slides.empty? && interval_start >= slides.first.begin

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

      svg_export(draw, view_box, slide.href, slide.width, slide.height, frame_number)

      # Write the frame's duration down
      file.puts "file ../frames/frame#{frame_number}.#{FILE_EXTENSION}"
      file.puts "duration #{(interval_end - interval_start).round(1)}"

      frame_number += 1
    end

    # The last image needs to be specified twice, without specifying the duration (FFmpeg quirk)
    file.puts "file ../frames/frame#{frame_number - 1}.#{FILE_EXTENSION}" if frame_number.positive?
  end
end

def svg_export(draw, view_box, slide_href, width, height, frame_number)
  # Builds SVG frame
  builder = Builder::XmlMarkup.new

  # FFmpeg unfortunately seems to require the xmlns:xmlink namespace. Add 'xmlns' => 'http://www.w3.org/2000/svg' for visual debugging
  builder.svg(width: "1600", height: "1080", viewBox: view_box, "xmlns:xlink" => "http://www.w3.org/1999/xlink") do
    # Display background image
    builder.image('xlink:href': slide_href, width: width, height: height, preserveAspectRatio: "xMidYMid slice")

    # Adds annotations
    draw.each do |shape|
      builder << shape.value
    end
  end

  File.open("#{@published_files}/frames/frame#{frame_number}.#{FILE_EXTENSION}", "w") do |svg|
    svg.chmod(0o600)
    if SVGZ_COMPRESSION
      svgz = Zlib::GzipWriter.new(svg)
      svgz.write(builder.target!)
      svgz.close
    else
      svg.write(builder.target!)
    end
  end
end

def export_presentation
  # Benchmark
  start = Time.now

  puts "Started composing presentation"

  # Convert whiteboard assets to a format compatible with FFmpeg
  convert_whiteboard_shapes(Nokogiri::XML(File.open("#{@published_files}/shapes.svg")).remove_namespaces!)

  shapes, slides, timestamps = parse_whiteboard_shapes(Nokogiri::XML::Reader(File.open("#{@published_files}/shapes_modified.svg")))
  panzooms, timestamps = parse_panzooms(Nokogiri::XML::Reader(File.open("#{@published_files}/panzooms.xml")), timestamps)

  # Create video assets
  render_chat(Nokogiri::XML::Reader(File.open("#{@published_files}/slides_new.xml")))
  render_cursor(panzooms, Nokogiri::XML::Reader(File.open("#{@published_files}/cursor.xml")))
  render_whiteboard(panzooms, slides, shapes, timestamps)

  puts "Finished composing presentation. Total: #{Time.now - start}"

  start = Time.now

  puts "Beginning to render video"
  ffmpeg = render_video

  puts "Finished with code #{ffmpeg}"

  puts "Exported recording available at #{@published_files}/meeting.mp4. Render time: #{Time.now - start}" if ffmpeg
end

export_presentation

# Delete the contents of the scratch directories
FileUtils.rm_rf(["#{@published_files}/chats", "#{@published_files}/cursor", "#{@published_files}/frames", "#{@published_files}/timestamps", "#{@published_files}/shapes_modified.svg"])
