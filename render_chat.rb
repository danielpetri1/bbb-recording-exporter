#!/usr/bin/ruby
# frozen_string_literal: false

require 'nokogiri'
require 'zlib'

# Track how long the code is taking
start = Time.now

# Opens slides_new.xml
@chat = Nokogiri::XML(File.open("slides_new.xml"))

# Get chat messages and timings
# recording_duration = (@meta.xpath('//duration').text.to_f / 1000).round(0)

ins = @chat.xpath('popcorn/chattimeline/@in').to_a.map(&:to_s) # .unshift(0).push(recording_duration)

# Creates new file to hold the timestamps of the chat
File.open("timestamps/chat_timestamps", 'w') {}

messages = @chat.xpath("popcorn/chattimeline[@target=\"chat\"]")

# Line break offset
dy = 12.5

# Empty string to build <text>...</text> tag from
text = ""
message_heights = [0]

messages.each do |message|
    break if dy >= 32_767

    # User name and chat timestamp
    text << "<text y=\"#{dy}\" font-weight=\"bold\">#{message.attr('name')}    #{Time.at(message.attr('in').to_f.round(0)).utc.strftime('%H:%M:%S')}</text>"

    line_breaks = message.attr('message').chars.each_slice(35).map(&:join)
    message_heights.push(line_breaks.size + 2)

    dy += 15

    # Message text
    line_breaks.each do |line|
        text << "<text y=\"#{dy}\">#{line}</text>"
        dy += 15
    end

    dy += 15
end

chat_y = 1080

# Create SVG chat with all messages for debugging purposes
builder = Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
     # xml.doc.create_internal_subset('svg', '-//W3C//DTD SVG 1.1//EN', 'http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd')
     xml.svg(width: '320', height: [dy * 15, 32_767].min, version: '1.1', 'xmlns' => 'http://www.w3.org/2000/svg', 'xmlns:xlink' => 'http://www.w3.org/1999/xlink') do
        xml << "<style>text{font-family: monospace; font-size: 15}</style>"
        xml << text
     end
end

File.open("chats/chat.svg", 'w') do |file|
    file.write(builder.to_xml)
end

File.open('timestamps/chat_timestamps', 'a') do |file|
    ins.each.with_index do |timestamp, chat_number|
        if message_heights[chat_number].nil?
            break
        else
            chat_y -= message_heights[chat_number] * 15
            file.puts timestamp.to_s
            # file.puts "overlay@msg x 0,"
            file.puts "overlay@msg y #{chat_y};"
        end
    end
end

# Benchmark
finish = Time.now
puts finish - start

exit 0
