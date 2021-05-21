#!/usr/bin/env ruby
# frozen_string_literal: true

require 'nokogiri'
require 'zlib'

start = Time.now

# Opens cursor.xml and shapes.svg
@doc = Nokogiri::XML(File.open('cursor.xml'))
@img = Nokogiri::XML(File.open('shapes.svg'))
@pan = Nokogiri::XML(File.open('panzooms.xml'))

# Get intervals to display the frames
timestamps = @doc.xpath('//@timestamp')

intervals = timestamps.to_a.map(&:to_s).map(&:to_f).uniq

# Creates new file to hold the timestamps of the cursor's position
File.open('timestamps/cursor_timestamps', 'w') {}

# Obtain interval range that each frame will be shown for
frame_number = 0
frames = []

intervals.each_cons(2) do |(a, b)|
    frames << [a, b]
end

# Obtains all cursor events
cursor = @doc.xpath('//event/cursor', 'xmlns' => 'http://www.w3.org/2000/svg')

frames.each do |frame|
    interval_start = frame[0]
    interval_end = frame[1]

    # Query to figure out which slide we're on - based on interval start since slide can change if mouse stationary
    slide = @img.xpath("(//xmlns:image[@in <= #{interval_start}])[last()]", 'xmlns' => 'http://www.w3.org/2000/svg')

    # Query viewBox parameter of slide
    view_box = @pan.xpath("(//event[@timestamp <= #{interval_start}]/viewBox/text())[last()]")

    width = slide.attr('width').to_s
    height = slide.attr('height').to_s

    x = slide.attr('x').to_s
    y = slide.attr('y').to_s

    # Get cursor coordinates
    pointer = cursor[frame_number].text.split

    cursor_x = (pointer[0].to_f * width.to_f).round(3)
    cursor_y = (pointer[1].to_f * height.to_f).round(3)

    # Builds SVG frame
    builder = Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
        # xml.doc.create_internal_subset('svg', '-//W3C//DTD SVG 1.1//EN', 'http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd')

        xml.svg(width: width, height: height, x: x, y: y, version: '1.1', viewBox: view_box, 'xmlns' => 'http://www.w3.org/2000/svg') do
            xml.circle(cx: cursor_x, cy: cursor_y, r: '10', fill: 'red') unless cursor_x.negative? || cursor_y.negative?
        end
    end

    # Saves frame as SVGZ file
    File.open("cursor/cursor#{frame_number}.svgz", 'w') do |file|
        svgz = Zlib::GzipWriter.new(file)
        svgz.write(builder.to_xml)
        svgz.close
    end

    # Writes its duration down
    File.open('timestamps/cursor_timestamps', 'a') do |file|
        file.puts "file ../cursor/cursor#{frame_number}.svgz"
        file.puts "duration #{(interval_end - interval_start).round(1)}"
    end

    frame_number += 1
end

# The last image needs to be specified twice, without specifying the duration (FFmpeg quirk)
File.open('timestamps/cursor_timestamps', 'a') do |file|
    file.puts "file ../cursor/cursor#{frame_number - 1}.svgz"
end

finish = Time.now
puts finish - start
