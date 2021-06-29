#!/usr/bin/ruby
# frozen_string_literal: true

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

require 'trollop'
require 'nokogiri'
require 'builder'

require File.expand_path('../../../lib/recordandplayback', __FILE__)

opts = Trollop.options do
  opt :meeting_id, "Meeting id to archive", type: String
  opt :format, "Playback format name", type: String
end

meeting_id = opts[:meeting_id]

logger = Logger.new("/var/log/bigbluebutton/post_publish.log", 'weekly')
logger.level = Logger::INFO
BigBlueButton.logger = logger

published_files = "/var/bigbluebutton/published/presentation/#{meeting_id}"

#
# Main code
#

start = Time.now

# Creates directory for the mouse pointer
Dir.mkdir("#{published_files}/cursor") unless File.exist?("#{published_files}/cursor")

# Opens cursor.xml and shapes.svg
@cursor_reader = Nokogiri::XML::Reader(File.open("#{published_files}/cursor.xml"))
@img_reader = Nokogiri::XML::Reader(File.open("#{published_files}/shapes.svg"))

timestamps = []
cursor = []
dimensions = []

@cursor_reader.each do |node|
    timestamps << node.attribute('timestamp').to_f if node.name == 'event' && node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT

    cursor << node.inner_xml if node.name == 'cursor' && node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT
end

@img_reader.each do |node|
    dimensions << [node.attribute('in').to_f, node.attribute('width').to_f, node.attribute('height').to_f] if node.name == 'image' && node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT
end

# Create the mouse pointer SVG
builder = Builder::XmlMarkup.new

# Add 'xmlns' => 'http://www.w3.org/2000/svg' for visual debugging, remove for faster exports
builder.svg(width: '16', height: '16') do
    builder.circle(cx: '8', cy: '8', r: '8', fill: 'red')
end

File.open("#{published_files}/cursor/cursor.svg", 'w') do |svg|
    svg.write(builder.target!)
end

File.open("#{published_files}/timestamps/cursor_timestamps", 'w') do |file|
    timestamps.each.with_index do |timestamp, frame_number|
        # Get cursor coordinates
        pointer = cursor[frame_number].split

        next_slide = dimensions.find_index { |t, _, _| t > timestamp }
        next_slide = dimensions.count if next_slide.nil?

        dimensions = dimensions.drop(next_slide - 1)
        dimension = dimensions.first

        width = dimension[1]
        height = dimension[2]

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

        cursor_x += x_offset
        cursor_y += y_offset

        # Move whiteboard to the right, making space for the chat and webcams
        cursor_x += 320

        # Writes the timestamp and position down
        file.puts "#{timestamp} overlay@m x #{cursor_x.round(3)}, overlay@m y #{cursor_y.round(3)};"
    end
end

finish = Time.now
BigBlueButton.logger.info("Finished render_cursor.rb for [#{meeting_id}]. Total: #{finish - start}")

exit 0