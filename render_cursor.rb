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

require "trollop"
require 'nokogiri'
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

published_files = "/var/bigbluebutton/published/presentation/#{meeting_id}"

#
# Main code
#

# Track how long the code is taking
start = Time.now

BigBlueButton.logger.info("Starting render_cursor.rb for [#{meeting_id}]")

# Opens cursor.xml and shapes.svg
@doc = Nokogiri::XML(File.open("#{published_files}/cursor.xml"))
@img = Nokogiri::XML(File.open("#{published_files}/shapes.svg"))

# Get cursor timestamps
timestamps = @doc.xpath('//@timestamp').to_a.map(&:to_s).map(&:to_f)

# Creates directory for the temporary assets
Dir.mkdir("#{published_files}/cursor") unless File.exist?("#{published_files}/cursor")

# Create the mouse pointer
builder = Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
    # xml.doc.create_internal_subset('svg', '-//W3C//DTD SVG 1.1//EN', 'http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd')

    xml.svg(width: "16", height: "16", version: '1.1', 'xmlns' => 'http://www.w3.org/2000/svg') do
        xml.circle(cx: '8', cy: '8', r: '8', fill: 'red')
    end
end

File.open("#{published_files}/cursor/cursor.svg", 'w') do |file|
    file.write(builder.to_xml)
end

# Creates new file to hold the timestamps and the cursor's position
File.open("#{published_files}/timestamps/cursor_timestamps", 'w') {}

# Obtains all cursor events
cursor = @doc.xpath('//event/cursor', 'xmlns' => 'http://www.w3.org/2000/svg')

timestamps.each.with_index do |timestamp, frame_number|

    # Query to figure out which slide we're on - based on interval start since slide can change if mouse stationary
    slide = @img.xpath("(//xmlns:image[@in <= #{timestamp}])[last()]", 'xmlns' => 'http://www.w3.org/2000/svg')

    width = slide.attr('width').to_s
    height = slide.attr('height').to_s

    # Get cursor coordinates
    pointer = cursor[frame_number].text.split

    cursor_x = (pointer[0].to_f * width.to_f).round(3)
    cursor_y = (pointer[1].to_f * height.to_f).round(3)

    # Scaling required to reach target dimensions
    x_scale = 1600 / width.to_f
    y_scale = 1080 / height.to_f

    # Keep aspect ratio
    scale_factor = [x_scale, y_scale].min
    
    # Scale
    cursor_x *= scale_factor
    cursor_y *= scale_factor

    # Translate given difference to new on-screen dimensions
    x_offset = (1600 - scale_factor * width.to_f) / 2
    y_offset = (1080 - scale_factor * height.to_f) / 2

    cursor_x += x_offset
    cursor_y += y_offset

    # Move whiteboard to the right, making space for the chat and webcams
    cursor_x += 320

    # Writes the timestamp and position down
    File.open("#{published_files}/timestamps/cursor_timestamps", 'a') do |file|
        file.puts "#{timestamp}"
        file.puts "overlay@mouse x #{cursor_x},"
        file.puts "overlay@mouse y #{cursor_y};"
    end
end

finish = Time.now
BigBlueButton.logger.info("Finished render_cursor.rb for [#{meeting_id}]. Total: #{finish - start}")

exit 0