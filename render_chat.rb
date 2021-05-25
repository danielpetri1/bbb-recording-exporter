#!/usr/bin/env ruby
# frozen_string_literal: true

require 'nokogiri'
require 'zlib'

# Track how long the code is taking
start = Time.now

# Opens slides_new.xml
@chat = Nokogiri::XML(File.open('slides_new.xml'))
@meta = Nokogiri::XML(File.open('metadata.xml'))

# Get chat messages and timings
recording_duration = (@meta.xpath('//duration').text.to_f / 1000).round(0)

ins = @chat.xpath('//@in').to_a.map(&:to_s).unshift(0).push(recording_duration)

# Creates new file to hold the timestamps of the chat
File.open('timestamps/chat_timestamps', 'w') {}

chat_intervals = []

ins.each_cons(2) do |(a, b)|
  chat_intervals << [a, b]
end

messages = @chat.xpath("//chattimeline[@target=\"chat\"]")

# Line break offset
dy = 0

# Empty string to build <text>...</text> tag from
text = ""
message_heights = [0]

messages.each do |message|

    # User name and chat timestamp
    text += "<text x=\"2.5\" y=\"12.5\" dy=\"#{dy}em\" font-family=\"monospace\" font-size=\"15\" font-weight=\"bold\">#{message.attr('name')}</text>"
    text += "<text x=\"2.5\" y=\"12.5\" dx=\"#{message.attr('name').length}em\" dy=\"#{dy}em\" font-family=\"monospace\" font-size=\"15\" fill=\"grey\" opacity=\"0.5\">#{Time.at(message.attr('in').to_f.round(0)).utc.strftime('%H:%M:%S')}</text>"
    
    line_breaks = message.attr('message').chars.each_slice(35).map(&:join)
    message_heights.push(line_breaks.size + 2)

    dy += 1

    # Message text 
    line_breaks.each.with_index do |line|
        text += "<text x=\"2.5\" y=\"12.5\" dy=\"#{dy}em\" font-family=\"monospace\" font-size=\"15\">#{line}</text>"
        dy += 1
    end
    
    dy += 1
end

base = -840

# Create SVG chat with all messages for debugging purposes
builder = Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
     xml.doc.create_internal_subset('svg', '-//W3C//DTD SVG 1.1//EN', 'http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd')
     xml.svg(width: '320', height: dy * 15, version: '1.1', 'xmlns' => 'http://www.w3.org/2000/svg', 'xmlns:xlink' => 'http://www.w3.org/1999/xlink') do
         xml << text
    end
end

File.open("chats/chat.svg", 'w') do |file|
    file.write(builder.to_xml)
end

i = 1/0
chat_intervals.each.with_index do |frame, chat_number|
    
    interval_start = frame[0]
    interval_end = frame[1]

    base += message_heights[chat_number] * 15

    # Create SVG chat window
    builder = Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
        xml.doc.create_internal_subset('svg', '-//W3C//DTD SVG 1.1//EN', 'http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd')
        xml.svg(width: '320', height: '840', viewBox: "0 #{base} 320 840", version: '1.1', 'xmlns' => 'http://www.w3.org/2000/svg', 'xmlns:xlink' => 'http://www.w3.org/1999/xlink') do
            xml << text
        end
    end

    # Saves frame as SVGZ file
    File.open("chats/chat#{chat_number}.svgz", 'w') do |file|
        svgz = Zlib::GzipWriter.new(file)
        svgz.write(builder.to_xml)
        svgz.close
    end

    # # Saves frame as SVG file (for debugging purposes)
    # File.open("chats/chat#{chat_number}.svg", 'w') do |file|
    #     file.write(builder.to_xml)
    # end

    File.open('timestamps/chat_timestamps', 'a') do |file|
        file.puts "file ../chats/chat#{chat_number}.svgz"
        file.puts "duration #{(interval_end.to_f - interval_start.to_f).round(1)}"
    end
end

# Benchmark
finish = Time.now

puts finish - start

# chat_intervals.each do |frame|
#     # Chat area size: 320x840
#     # Message size: 320x40
#     # => each time interval [x,y) can hold up to 21 messages
#     interval_start = frame[0]
#     interval_end = frame[1]

#     # Determine which messages are visible
#     visible_messages = @chat.xpath("//chattimeline[@target=\"chat\" and @in < #{interval_end}]").to_a.last(21)
#     dy = 0

#     # Create SVG chat window
#     builder = Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
#         xml.doc.create_internal_subset('svg', '-//W3C//DTD SVG 1.1//EN', 'http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd')
#         xml.svg(width: '320', height: '840', version: '1.1', viewBox: '0 0 320 840', 'xmlns' => 'http://www.w3.org/2000/svg', 'xmlns:xlink' => 'http://www.w3.org/1999/xlink') do
#             visible_messages.each do |chat|
#                 xml << "<text x=\"2.5\" y=\"#{12.5}\" dy=\"#{dy}em\" font-family=\"Arial\"><tspan font-size=\"12\" font-weight=\"bold\">#{chat.attr('name')}</tspan><tspan fill=\"grey\" font-size=\"8\">#{Time.at(chat.attr('in').to_f.round(0)).utc.strftime('%H:%M:%S')}</tspan></text>"
                
#                 # Line wrapping after 35 characters
#                 line_breaks = chat.attr('message').chars.each_slice(35).map(&:join)

#                 text = "<text x=\"2.5\" y=\"#{32.5}\" dy=\"#{dy}em\" font-family=\"monospace\" font-size=\"15\">"

#                 line_breaks.each do |line|
#                     text += "<tspan dy=\"#{dy}em\">#{line}</tspan>"
#                     dy += 1
#                 end

#                 text += "</text>"

#                 puts dy

#                 xml << text
#             end
#         end
#     end

#     # Saves frame as SVG file (for debugging purposes)
#     File.open("chats/chat#{chat_number}.svg", 'w') do |file|
#         file.write(builder.to_xml)
#     end

#     # Saves frame as SVGZ file
#     #File.open("chats/chat#{chat_number}.svgz", 'w') do |file|
#         #svgz = Zlib::GzipWriter.new(file)
#         #svgz.write(builder.to_xml)
#         #svgz.close
#     #end

#     # Writes its duration down
#     File.open('timestamps/chat_timestamps', 'a') do |file|
#         file.puts "file ../chats/chat#{chat_number}.svgz"
#         file.puts "duration #{(interval_end.to_f - interval_start.to_f).round(1)}"
#     end

#     chat_number += 1
# end

# # The last image needs to be specified twice, without specifying the duration (FFmpeg quirk)
# File.open('timestamps/chat_timestamps', 'a') do |file|
#     file.puts "file ../chats/chat#{chat_number - 1}.svgz"
# end