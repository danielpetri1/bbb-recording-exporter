#!/usr/bin/env ruby
# Copyright (c) 2011-2017 MISHIMA, Hiroyuki; Simeon Simeonov; Carlos Alonsol; Sam Davies; amarzot-yesware

# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:

# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

module IntervalTree

    class Tree
      def initialize(ranges, &range_factory)
        range_factory = lambda { |l, r| (l ... r+1) } unless block_given?
        ranges_excl = ensure_exclusive_end([ranges].flatten, range_factory)
        @top_node = divide_intervals(ranges_excl)
      end
      attr_reader :top_node
  
      def divide_intervals(intervals)
        return nil if intervals.empty?
        x_center = center(intervals)
        s_center = Array.new
        s_left = Array.new
        s_right = Array.new
  
        intervals.each do |k|
          case
          when k.end.to_r < x_center
            s_left << k
          when k.begin.to_r > x_center
            s_right << k
          else
            s_center << k
          end
        end
        Node.new(x_center, s_center,
                 divide_intervals(s_left), divide_intervals(s_right))
      end
  
      # Search by range or point
      DEFAULT_OPTIONS = {unique: true}
      def search(query, options = {})
        options = DEFAULT_OPTIONS.merge(options)
  
        return nil unless @top_node
  
        if query.respond_to?(:begin)
          result = top_node.search(query)
          options[:unique] ? result.uniq : result
        else
          point_search(self.top_node, query, [], options[:unique])
        end
          .sort_by{|x|[x.begin, x.end]}
      end
  
      def ==(other)
        top_node == other.top_node
      end
  
      private
  
      def ensure_exclusive_end(ranges, range_factory)
        ranges.map do |range|
          case
          when !range.respond_to?(:exclude_end?)
            range
          when range.exclude_end?
            range
          else
            range_factory.call(range.begin, range.end)
          end
        end
      end
  
      def center(intervals)
        (
          intervals.map(&:begin).min.to_r +
          intervals.map(&:end).max.to_r
        ) / 2
      end
  
      def point_search(node, point, result, unique = true)
        node.s_center.each do |k|
          if k.begin <= point && point < k.end
            result << k
          end
        end
        if node.left_node && ( point.to_r < node.x_center )
          point_search(node.left_node, point, []).each{|k|result << k}
        end
        if node.right_node && ( point.to_r >= node.x_center )
          point_search(node.right_node, point, []).each{|k|result << k}
        end
        if unique
          result.uniq
        else
          result
        end
      end
    end # class Tree
  
    class Node
      def initialize(x_center, s_center, left_node, right_node)
        @x_center = x_center
        @s_center = s_center
        @left_node = left_node
        @right_node = right_node
      end
      attr_reader :x_center, :s_center, :left_node, :right_node
  
      def ==(other)
        x_center == other.x_center &&
        s_center == other.s_center &&
        left_node == other.left_node &&
        right_node == other.right_node
      end
  
      # Search by range only
      def search(query)
        search_s_center(query) +
          (left_node && query.begin.to_r < x_center && left_node.search(query) || []) +
          (right_node && query.end.to_r > x_center && right_node.search(query) || [])
      end
  
      private
  
      def search_s_center(query)
        s_center.select do |k|
          (
            # k is entirely contained within the query
            (k.begin >= query.begin) &&
            (k.end <= query.end)
          ) || (
            # k's start overlaps with the query
            (k.begin >= query.begin) &&
            (k.begin < query.end)
          ) || (
            # k's end overlaps with the query
            (k.end > query.begin) &&
            (k.end <= query.end)
          ) || (
            # k is bigger than the query
            (k.begin < query.begin) &&
            (k.end > query.end)
          )
        end
      end
    end # class Node
  
  end # module IntervalTree