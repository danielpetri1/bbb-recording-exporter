# frozen_string_literal: true

require 'nokogiri'

# Opens shapes.svg
@doc = Nokogiri::XML(File.open('shapes.svg'))

# Gets the path of each image in the presentation
images = @doc.xpath('//xmlns:image/@xlink:href', 'xmlns' => 'http://www.w3.org/2000/svg', 'xlink' => 'http://www.w3.org/1999/xlink').to_a.map(&:to_s).uniq

slides = []
slide_number = 0

images.each do |image|
  next if image == 'presentation/deskshare.png'

  # Gets the last occurence of each presentation slide
  slides << @doc.xpath("//xmlns:image[@xlink:href = \"#{image}\"]").last
end

slides.each do |slide|
  width = slide.attr('width')
  height = slide.attr('height')
  slide_id = slide.attr('id')

  # Gets the canvas of that slide
  canvas = @doc.xpath("//xmlns:g[@class=\"canvas\" and @image=\"#{slide_id}\"]",
                      'xmlns' => 'http://www.w3.org/2000/svg', 'xlink' => 'http://www.w3.org/1999/xlink')

  # Gets the shapes that make up the drawings
  draw = canvas.xpath('xmlns:g[@class="shape" and @undo = "-1"]')

  # Remove redundant shapes
  shapes = []
  render = []

  draw.each do |shape|
    shapes << shape.attr('shape').to_s
  end

  # Add this shape to what will be rendered
  if draw.length.positive?

    shapes.uniq.each do |shape|
      selection = draw.select do |drawing|
        drawing.attr('shape') == shape
      end

      render << selection.last
    end
  end

  # Makes slide and annotations visible
  style = slide.attr('style')
  style.sub! 'hidden', 'visible'
  slide.set_attribute('style', style)

  render.each do |shape|
    next if shape.nil?

    style = shape.attr('style')
    style.sub! 'hidden', 'visible'

    shape.set_attribute('style', style)
  end

  # Builds SVG frame
  builder = Nokogiri::XML::Builder.new do |xml|
    xml.svg(width: width, height: height, version: '1.1', 'xmlns' => 'http://www.w3.org/2000/svg',
            'xmlns:xlink' => 'http://www.w3.org/1999/xlink') do
      # Adds background image
      xml << slide.to_s

      # Adds annotations
      render.each do |shape|
        xml << shape.to_s
      end
    end
  end

  # Saves slide as SVG file
  File.open('tmp.svg', 'w') do |file|
    file.write(builder.to_xml)
  end

  system("rsvg-convert --format=png --output=slides/slide#{slide_number}.png tmp.svg")

  slide_number += 1
end
