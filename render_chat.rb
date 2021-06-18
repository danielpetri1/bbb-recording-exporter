#!/usr/bin/ruby
# frozen_string_literal: false

require 'nokogiri'
require 'zlib'

# Track how long the code is taking
start = Time.now

# Opens slides_new.xml
@chat_reader = Nokogiri::XML::Reader(File.open('slides_new.xml'))

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

# Create SVG chat with all messages
# Max. dimensions: 8032 x 32767
builder = Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
     xml.svg(width: svg_width, height: svg_height, version: '1.1', 'xmlns' => 'http://www.w3.org/2000/svg') do
        xml << "<style>text{font-family: monospace; font-size: 15}</style>"
        xml << text
     end
end

# Saves chat as SVG / SVGZ file
File.open("chats/chat.svgz", 'w') do |file|
    svgz = Zlib::GzipWriter.new(file)
    svgz.write(builder.to_xml)
    svgz.close
end

# File.open("chats/chat.svg", 'w') do |file|
# file.write(builder.to_xml)
# end

File.open('timestamps/chat_timestamps', 'w') do |file|
    file.puts "0 overlay@msg x 0, overlay@msg y 0;" if overlay_position.empty?

    overlay_position.each do |chat_state|
        chat_x = chat_state[1]
        chat_y = chat_state[2]

        file.puts "#{chat_state[0]} crop@c x #{chat_x}, crop@c y #{chat_y};"
    end
end

# Benchmark
finish = Time.now
puts finish - start

exit 0
