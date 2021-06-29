#!/usr/bin/ruby
# frozen_string_literal: false

#
# BigBlueButton open source conferencing system - http://www.bigbluebutton.org/
#
# Copyright (c) 2012 BigBlueButton Inc. and by respective authors (see below).
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU Lesser General Public License as published by the Free
# Software Foundation; either version 3.0 of the License, or (at your option)
# any later version.
#
# BigBlueButton is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License for more
# details.
#
# You should have received a copy of the GNU Lesser General Public License along
# with BigBlueButton; if not, see <http://www.gnu.org/licenses/>.
#

require "trollop"
require 'nokogiri'
require 'base64'
require 'zlib'
require File.expand_path('../../../lib/recordandplayback', __FILE__)

opts = Trollop.options do
  opt :meeting_id, "Meeting id to archive", type: String
  opt :format, "Playback format name", type: String
end

meeting_id = opts[:meeting_id]

logger = Logger.new("/var/log/bigbluebutton/post_publish.log", 'weekly')
logger.level = Logger::INFO
BigBlueButton.logger = logger

@published_files = "/var/bigbluebutton/published/presentation/#{meeting_id}"

BigBlueButton.logger.info("Starting render_whiteboard.rb for [#{meeting_id}]")

# Track how long the code is taking
start = Time.now

# Creates directory for the whiteboard frames
Dir.mkdir("#{@published_files}/frames") unless File.exist?("#{@published_files}/frames")

#
# Interval Tree Module (fast_interval_tree gem)
#

# Copyright (c) 2011-2021 MISHIMA, Hiroyuki; Simeon Simeonov; Carlos Alonsol; Sam Davies; amarzot-yesware; Daniel Petri Rocha

# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:

# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

module IntervalTree
  class Tree
    def initialize(ranges, &range_factory)
      range_factory = ->(l, r) { (l...r + 1) } unless block_given?
      ranges_excl = ensure_exclusive_end([ranges].flatten, range_factory)
      @top_node = divide_intervals(ranges_excl)
    end
    attr_reader :top_node

    def divide_intervals(intervals)
      return nil if intervals.empty?
      x_center = center(intervals)
      s_center = []
      s_left = []
      s_right = []

      intervals.each do |k|
        if k.end.to_r < x_center
          s_left << k
        elsif k.begin.to_r > x_center
          s_right << k
        else
          s_center << k
        end
      end

      s_center = s_center.sort_by { |x| [x.begin, x.end] }

      Node.new(x_center, s_center,
               divide_intervals(s_left), divide_intervals(s_right))
    end

    # Search by range or point
    DEFAULT_OPTIONS = { unique: true, sort: true }
    def search(query, options = {})
      options = DEFAULT_OPTIONS.merge(options)
      return nil unless @top_node

      if query.respond_to?(:begin)
        result = top_node.search(query)
        options[:unique] ? result.uniq : result
      else
        result = point_search(top_node, query, [], options[:unique])
      end

      options[:sort] ? result.sort_by { |x| [x.begin, x.end] } : result
    end

    def ==(other)
      top_node == other.top_node
    end

    private

    def ensure_exclusive_end(ranges, range_factory)
      ranges.map do |range|
        if !range.respond_to?(:exclude_end?)
          range
        elsif range.exclude_end?
          range
        else
          range_factory.call(range.begin, range.end)
        end
      end
    end

    def center(intervals)
      (
        intervals.map(&:begin).min.to_r +
        intervals.map(&:end).max.to_r
      ) / 2
    end

    def point_search(node, point, result, unique)
      stack = [node]
      point_r = point.to_r

      until stack.empty?
        node = stack.pop

        node.s_center.each do |k|
          break if k.begin > point
          result << k if point < k.end
        end

        if node.left_node && (point_r < node.x_center)
          stack << node.left_node

        elsif node.right_node && (point_r >= node.x_center)
          stack << node.right_node
        end

      end
      if unique
        result.uniq
      else
        result
      end
    end
  end

  class Node
    def initialize(x_center, s_center, left_node, right_node)
      @x_center = x_center
      @s_center = s_center
      @left_node = left_node
      @right_node = right_node
    end
    attr_reader :x_center, :s_center, :left_node, :right_node

    def ==(other)
      x_center == other.x_center &&
        s_center == other.s_center &&
        left_node == other.left_node &&
        right_node == other.right_node
    end

    # Search by range only
    def search(query)
      search_s_center(query) +
        (left_node && query.begin.to_r < x_center && left_node.search(query) || []) +
        (right_node && query.end.to_r > x_center && right_node.search(query) || [])
    end

    private

    def search_s_center(query)
      result = []

      s_center.each do |k|
        break if k.begin > query.end

        next unless (
          # k is entirely contained within the query
          (k.begin >= query.begin) &&
          (k.end <= query.end)
        ) || (
          # k's start overlaps with the query
          (k.begin >= query.begin) &&
          (k.begin < query.end)
        ) || (
          # k's end overlaps with the query
          (k.end > query.begin) &&
          (k.end <= query.end)
        ) || (
          # k is bigger than the query
          (k.begin < query.begin) &&
          (k.end > query.end)
        )
        result << k
      end

      result
    end
  end
end

#
# Main code
#

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

BigBlueButton.logger.info("Finished render_whiteboard.rb for [#{meeting_id}]. Total: #{finish - start}")

start = Time.now

# Determine if video had screensharing
deskshare = File.file?("#{@published_files}/deskshare/deskshare.#{VIDEO_EXTENSION}")

if deskshare
  render = "ffmpeg -f lavfi -i color=c=white:s=1920x1080 " \
 "-f concat -safe 0 -i #{@published_files}/timestamps/whiteboard_timestamps " \
 "-framerate 10 -loop 1 -i #{@published_files}/cursor/cursor.svg " \
 "-framerate 1 -loop 1 -i #{@published_files}/chats/chat.#{FILE_EXTENSION} \ " \
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

BigBlueButton.logger.info("Beginning to render video for [#{meeting_id}]")
system(render)

finish = Time.now
BigBlueButton.logger.info("Exported recording available at #{@published_files}/meeting.mp4 . Render time: #{finish - start}")

# Delete the contents of the scratch directories (race conditions)
# FileUtils.rm_rf("#{@published_files}/chats")
# FileUtils.rm_rf("#{@published_files}/cursor")
# FileUtils.rm_rf("#{@published_files}/frames")
# FileUtils.rm_rf("#{@published_files}/timestamps")

exit 0
