#!/usr/bin/env ruby
# frozen_string_literal: true

require 'nokogiri'
require 'zlib'

# Opens slides_new.xml
@chat = Nokogiri::XML(File.open('slides_new.xml'))
@meta = Nokogiri::XML(File.open('metadata.xml'))

# Get chat messages and timings
chat_timeline = @chat.xpath('//chattimeline[@target="chat"]')
recording_duration = (@meta.xpath('//duration').text.to_f / 1000).round(0)

ins = @chat.xpath('//@in').to_a.map(&:to_s).unshift(0).push(recording_duration).uniq

# Creates new file to hold the timestamps of the chat
File.open('timestamps/chat_timestamps', 'w') {}

chat_intervals = []
chat_number = 0

ins.each_cons(2) do |(a, b)|
  chat_intervals << [a, b]
end

chat_intervals.each do |frame|
    # Chat area size: 320x840
    # Message size: 320x40
    # => each time interval [x,y) can hold up to 21 messages
    interval_start = frame[0]
    interval_end = frame[1]

    # Determine which messages are visible
    visible_messages = @chat.xpath('//chattimeline[@target="chat" and @in < ' + interval_end.to_s + ']').to_a.last(21)

    # Create SVG chat window
    builder = Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
        xml.doc.create_internal_subset('svg', '-//W3C//DTD SVG 1.1//EN', 'http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd')
        xml.svg(width: '320', height: '840', version: '1.1', viewBox: '0 0 320 840', 'xmlns' => 'http://www.w3.org/2000/svg', 'xmlns:xlink' => 'http://www.w3.org/1999/xlink') do
        
            visible_messages.each.with_index do |chat, offset|
                xml << "<text x=\"2.5\" y=\"#{12.5 + offset * 40}\" font-family=\"Arial\"><tspan font-size=\"12\" font-weight=\"bold\">#{chat.attr('name')}</tspan><tspan fill=\"grey\" font-size=\"8\">#{Time.at(chat.attr('in').to_f.round(0)).utc.strftime('%H:%M:%S')}</tspan></text>"
                xml << "<text x=\"2.5\" y=\"#{32.5 + offset * 40}\" font-family=\"Arial\" font-size=\"15\">#{chat.attr('message')}</text>"
            end
        end
    end

    # Saves frame as SVG file (for debugging purposes)
    #File.open("chats/chat#{chat_number}.svg", 'w') do |file|
        #file.write(builder.to_xml)
    #end

    # Saves frame as SVGZ file
    File.open("chats/chat#{chat_number}.svgz", 'w') do |file|
        svgz = Zlib::GzipWriter.new(file)
        svgz.write(builder.to_xml)
        svgz.close
    end

    # Writes its duration down
    File.open('timestamps/chat_timestamps', 'a') do |file|
        file.puts "file ../chat/frame#{chat_number}.svgz"
        file.puts "duration #{(interval_end.to_f - interval_start.to_f).round(1)}"
    end

    chat_number += 1
end

# The last image needs to be specified twice, without specifying the duration (FFmpeg quirk)
File.open('timestamps/whiteboard_timestamps', 'a') do |file|
    file.puts "file ../chat/frame#{chat_number - 1}.svgz"
end
