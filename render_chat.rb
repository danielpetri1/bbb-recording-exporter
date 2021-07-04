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

require 'trollop'
require 'nokogiri'
require 'zlib'
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


BigBlueButton.logger.info("Starting render_chat.rb for [#{meeting_id}]")

#
# Main code
#

# Flags
SVGZ_COMPRESSION = false
FILE_EXTENSION = SVGZ_COMPRESSION ? "svgz" : "svg"

# Track how long the code is taking
start = Time.now

# Creates directory for the temporary assets
Dir.mkdir("#{published_files}/chats") unless File.exist?("#{published_files}/chats")
Dir.mkdir("#{published_files}/timestamps") unless File.exist?("#{published_files}/timestamps")

# Opens slides_new.xml
@chat_reader = Nokogiri::XML::Reader(File.open("#{published_files}/slides_new.xml"))

messages = []

@chat_reader.each do |node|
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
File.open("#{published_files}/chats/chat.#{FILE_EXTENSION}", "w") do |file|
    if SVGZ_COMPRESSION then
        svgz = Zlib::GzipWriter.new(file)
        svgz.write(builder.to_xml)
        svgz.close
    else
        file.write(builder.to_xml)
    end
end

File.open("#{published_files}/timestamps/chat_timestamps", 'w') do |file|
    file.puts "0 overlay@msg x 0, overlay@msg y 0;" if overlay_position.empty?

    overlay_position.each do |chat_state|
        chat_x = chat_state[1]
        chat_y = chat_state[2]

        file.puts "#{chat_state[0]} crop@c x #{chat_x}, crop@c y #{chat_y};"
    end
end

# Benchmark
finish = Time.now
BigBlueButton.logger.info("Finished render_chat.rb for [#{meeting_id}]. Total: #{finish - start}")

exit 0