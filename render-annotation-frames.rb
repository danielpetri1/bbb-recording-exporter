require 'nokogiri'
require 'itree'

tree = Intervals::Tree.new

def ranges_overlap?(range_a, range_b)
    range_b[0] <= range_a[1] && range_a[0] <= range_b[1] 
end

def merge_ranges(intervals)
    merged = []

    intervals.sort_by! { |interval| interval[0] }

    intervals.each do |interval|
      if merged.empty? || merged.last[1] < interval[0]
        merged << interval
      else
        merged.last[1] = interval[1] if interval[1] > merged.last[1]
      end
    end
  
    return merged
end


#tree.insert(8.9, 15.1, 'a')
#tree.insert(9, 15.1, 'b')
#tree.insert(11, 12, 'c')

#results = tree.stab(8.9, 15.1)

#results.each do |result|
#    puts result.data
#end

itv = [[8.9, 15.1], [9, 15.1], [11, 12]]

def split_intervals(intervals)
    # Sort array by start time
    intervals.sort_by! { |interval| interval[0] }

    max = []

    intervals.each do |elem|
        max << elem[1]
    end

    max = max.max

    intervals.each_cons(2) do |a, b|
        
        if (a[1] >= b[0]) then
            a[1] = b[0]
        end

        if a[1] < b[0] then
            intervals << [a[1], b[0]]
        end
    end

    if max > intervals.last[1] then
        intervals << [intervals.last[1], max]
    end

    return intervals
end

# Opens shapes.svg
@doc = Nokogiri::XML(File.open('shapes copy.svg'))

# Gets each canvas drawn over the presentation
whiteboard = @doc.xpath('//xmlns:g[@class="canvas"]', 'xmlns' => 'http://www.w3.org/2000/svg', 'xlink' => 'http://www.w3.org/1999/xlink')
slides = @doc.xpath('//xmlns:image', 'xmlns' => 'http://www.w3.org/2000/svg', 'xlink' => 'http://www.w3.org/1999/xlink')

stabsStart = []
stabsEnd = []
frameNumber = 0
itv = []

whiteboard.each do |canvas|
    # Finds slide corresponding to that canvas to get information from
    slide = @doc.xpath('//xmlns:image[@id = "' + canvas.attr('image').to_s + '"]', 'xmlns' => 'http://www.w3.org/2000/svg', 'xlink' => 'http://www.w3.org/1999/xlink')

    # Attributes of the slide the canvas is being drawn on
    slideStart = slide.attr('in').to_s.to_f
    slideEnd = slide.attr('out').to_s.to_f

    width = slide.attr('width').to_s
    height = slide.attr('height').to_s
    
    x = slide.attr('x').to_s
    y = slide.attr('y').to_s

    # Tree to hold intervals
    intervals = Intervals::Tree.new

    # Find shapes that make up the slide
    shapes = canvas.xpath('./xmlns:g[@class="shape"]')

    shapes.each do |shape|

        # Make shape visible
        style = shape.attr('style')
        style.sub! 'hidden', 'visible'
        shape.set_attribute('style', style)

        # When the shape should stop being shown
        undo = shape.attr('undo').to_s.to_f.round(1)

        if undo < 0 then
            undo = slideEnd
        end

        # When the shape is first drawn

        timestamp = shape.attr('timestamp').to_s.to_f.round(1)

        shapeStart = [[slideStart, timestamp].max, slideEnd].min
        shapeEnd = [[slideStart, undo].max, slideEnd].min

        intervals.insert(shapeStart, shapeEnd, shape)

        itv << [shapeStart, shapeEnd]
    end
end


