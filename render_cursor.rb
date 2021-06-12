#!/usr/bin/env ruby
# frozen_string_literal: true

require 'nokogiri'
require 'zlib'

start = Time.now

# Opens cursor.xml and shapes.svg
@doc = Nokogiri::XML(File.open('cursor.xml'))
@img = Nokogiri::XML(File.open('shapes.svg'))

# Get cursor timestamps
timestamps = @doc.xpath('//@timestamp').to_a.map(&:to_s).map(&:to_f)

# Creates new file to hold the timestamps and the cursor's position
File.open('timestamps/cursor_timestamps', 'w') {}

# Obtain interval range that each frame will be shown for
frame_number = 0

# Obtains all cursor events
cursor = @doc.xpath('//event/cursor', 'xmlns' => 'http://www.w3.org/2000/svg')

timestamps.each do |timestamp|

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

    puts "x offset: #{x_offset}, y offset: #{y_offset}, scale factor: #{scale_factor}"

    # Writes the timestamp and position down
    File.open('timestamps/cursor_timestamps', 'a') do |file|
        file.puts "#{timestamp}  drawtext reinit 'x=#{cursor_x}:y=#{cursor_y}';";
    end

    frame_number += 1
end

finish = Time.now
puts finish - start