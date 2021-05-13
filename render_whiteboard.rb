#!/usr/bin/env ruby
# frozen_string_literal: true

require 'nokogiri'

# Opens shapes.svg
@doc = Nokogiri::XML(File.open('shapes.svg'))

# Get intervals to display the frames
ins = @doc.xpath('//@in')
outs = @doc.xpath('//@out')
timestamps = @doc.xpath('//@timestamp')
undos = @doc.xpath('//@undo')
images = @doc.xpath('//xmlns:image', 'xmlns' => 'http://www.w3.org/2000/svg')

intervals = (ins + outs + timestamps + undos).to_a.map(&:to_s).map(&:to_f).uniq.sort

# Update image paths since files are saved in ./frames
images.each do |image|
  path = image.attr('xlink:href')
  image.set_attribute('xlink:href', '../' + path)
  image.set_attribute('style', 'visibility:visible')
end

# Creates new file to hold the timestamps of the whiteboard
File.open('whiteboard_timestamps', 'w') {}

# Intervals with a value of -1 do not correspond to a timestamp
intervals = intervals.drop(1) if intervals.first == -1

# Obtain interval range that each frame will be shown for
frame_number = 0
frames = []

intervals.each_cons(2) do |(a, b)|
  frames << [a, b]
end

# Render the visible frame for each interval
frames.each do |frame|
  interval_start = frame[0]
  interval_end = frame[1]

  # Figure out which slide we're currently on
  slide = @doc.xpath("//xmlns:image[@in <= #{interval_start} and #{interval_end} <= @out]", 'xmlns' => 'http://www.w3.org/2000/svg')

  # Get slide information
  slide_id = slide.attr('id').to_s
  slide_class = slide.attr('class').to_s
  
  width = slide.attr('width').to_s
  height = slide.attr('height').to_s
  x = slide.attr('x').to_s
  y = slide.attr('y').to_s

  viewBox = '0 0 1600 900'

  draw = @doc.xpath('//xmlns:g[@class="canvas" and @image="' + slide_id.to_s + '"]/xmlns:g[@timestamp < "' + interval_end.to_s + '" and (@undo = "-1" or @undo >= "' + interval_end.to_s + '")]', 'xmlns' => 'http://www.w3.org/2000/svg')

  # Removes redundant frames that compose the shape's animation
  # For backwards-compability with BBB 2.2, live whiteboard not supported in BBB 2.3

  shapes = draw.xpath('./@shape')

  shapes.each do |shape|
    
    # Remove every frame that led up to the final state of the annotation
    delete = shape.xpath('parent::*')
    keep = delete.last
    draw = draw - delete

    # Add final state of the shape
    draw.push(keep)

  end

  # -----------------------------------

  # Builds SVG frame
  builder = Nokogiri::XML::Builder.new(:encoding => 'UTF-8') do |xml|
    
    xml.doc.create_internal_subset('svg','-//W3C//DTD SVG 1.1//EN','http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd')

    xml.svg(width: width, height: height, x: x, y: y, version: '1.1', viewBox: viewBox, 'xmlns' => 'http://www.w3.org/2000/svg', 'xmlns:xlink' => 'http://www.w3.org/1999/xlink') do
      
      # Display background image
      xml.image(id: slide_id, class: slide_class, 'xlink:href': slide.attr('href'), width: width, height: height, x: x, y: y, style: slide.attr('style'))

      # Add annotations
      draw.each do |shape|

        # Make shape visible
        style = shape.attr('style')
        style.sub! 'hidden', 'visible'
        #shape.set_attribute('style', style)
        
        xml.g(id: shape.attr('id'), style: style) do
          xml << shape.xpath('./*').to_s
        end

      end
    end
  end

  # Saves frame as SVG file
  File.open("frames/frame#{frame_number}.svg", 'w') do |file|
    file.write(builder.to_xml)
  end

  # Writes its duration down
  File.open('whiteboard_timestamps', 'a') do |file|
    file.puts "file frames/frame#{frame_number}.svg"
    file.puts "duration #{(interval_end - interval_start).round(1)}"
  end

  frame_number += 1
  puts frame_number
end

# The last image needs to be specified twice, without specifying the duration (FFmpeg quirk)
File.open('whiteboard_timestamps', 'a') do |file|
  file.puts "file frames/frame#{frame_number - 1}.svg"
end
