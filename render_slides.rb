# frozen_string_literal: true

require 'nokogiri'

# Opens shapes.svg
@doc = Nokogiri::XML(File.open('shapes.svg'))

# Creates new file to hold the timestamps of the slides
File.open('presentation_timestamps', 'w') {}

# Gets each slide in the presentation
slides = @doc.xpath('//xmlns:image[@class="slide"]', 'xmlns' => 'http://www.w3.org/2000/svg', 'xlink' => 'http://www.w3.org/1999/xlink')

# For each slide, write down the time it appears in the presentation
slides.each do |slide|
  # Get slide's background image
  image = slide.attr('xlink:href')

  # How long the presentation slide is displayed for
  duration = (slide.attr('out').to_f - slide.attr('in').to_f).round(1)

  # Writes duration to file with the corresponding image
  File.open('presentation_timestamps', 'a') do |file|
    file.puts "file '#{image}'"
    file.puts "duration #{duration}"
  end
end

# The last image needs to be specified twice, without specifying the duration (FFmpeg quirk)
image = slides.last.attr('xlink:href')

File.open('presentation_timestamps', 'a') do |file|
  file.puts "file '#{image}'"
end
