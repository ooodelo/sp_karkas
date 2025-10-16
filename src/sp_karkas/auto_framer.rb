require 'sketchup.rb'
require_relative 'geometry_utils'
require_relative 'framing_elements'
require_relative 'metadata'

module SPKarkas
  module AutoFramer
    extend self

    STUD_SPACING = 400.mm
    HEADER_HEIGHT = 2.1.m
    ROUGH_OPENING_EXPANSION = 25.mm

    def activate
      model = Sketchup.active_model
      walls = detect_wall_groups(model)
      if walls.empty?
        UI.messagebox('Select at least one group to frame or ensure wall groups exist in the model.')
        return
      end

      model.start_operation('SP Karkas Auto Framer', true)
      walls.each_with_index do |wall, index|
        frame_wall(model, wall, index + 1)
      end
      model.commit_operation
      UI.messagebox("Framed #{walls.size} wall(s).")
    rescue StandardError => error
      model.abort_operation
      UI.messagebox("Auto Framer failed: #{error.message}")
      raise error
    end

    def detect_wall_groups(model)
      selection = model.selection.grep(Sketchup::Group)
      return selection unless selection.empty?

      model.entities.grep(Sketchup::Group).select { |group| wall_like?(group) }
    end

    def wall_like?(group)
      axes = GeometryUtils.wall_axes(group)
      bounds = group.local_bounds
      thickness = bounds.max.y - bounds.min.y
      height = bounds.max.z - bounds.min.z
      length = bounds.max.x - bounds.min.x
      height > length && height > thickness * 2
    rescue StandardError
      false
    end

    def frame_wall(_model, wall_group, sequence)
      Metadata.apply(wall_group, Metadata.wall_tag.merge('sequence' => sequence))

      axes = GeometryUtils.wall_axes(wall_group)
      local = wall_group.local_bounds
      length_interval = [0.0, local.max.x - local.min.x]
      height_interval = [0.0, local.max.z - local.min.z]

      studs = layout_studs(wall_group, axes, length_interval, height_interval, sequence)
      layout_headers(wall_group, axes, length_interval, height_interval, sequence)
      layout_braces(wall_group, axes, length_interval, height_interval, sequence)

      studs
    end

    def layout_studs(wall_group, axes, length_interval, height_interval, sequence)
      wall_entities = wall_group.entities
      stud_length = height_interval.last - height_interval.first
      studs = []

      left_offset = length_interval.first + FramingElements::DEFAULT_STUD_WIDTH / 2.0
      right_offset = length_interval.last - FramingElements::DEFAULT_STUD_WIDTH / 2.0

      studs << FramingElements.create_stud(wall_entities, axes, stud_length, left_offset, Metadata.framing_member_tag('king_stud_left', sequence))
      return studs if right_offset <= left_offset

      studs << FramingElements.create_stud(wall_entities, axes, stud_length, right_offset, Metadata.framing_member_tag('king_stud_right', sequence))

      GeometryUtils.evenly_spaced_positions([left_offset, right_offset], STUD_SPACING).each_with_index do |offset, index|
        studs << FramingElements.create_stud(
          wall_entities,
          axes,
          stud_length,
          offset,
          Metadata.framing_member_tag('stud', sequence * 100 + index)
        )
      end
      studs
    end

    def layout_headers(wall_group, axes, length_interval, height_interval, sequence)
      openings = detect_openings(wall_group, axes)
      return if openings.empty?

      elevation = [HEADER_HEIGHT, height_interval.last - FramingElements::DEFAULT_STUD_WIDTH].min
      openings.each_with_index do |opening, index|
        expanded = GeometryUtils.expand_interval(opening, ROUGH_OPENING_EXPANSION)
        start_offset = GeometryUtils.interval_contains?(length_interval, expanded.first) ? expanded.first : length_interval.first
        end_offset = GeometryUtils.interval_contains?(length_interval, expanded.last) ? expanded.last : length_interval.last
        width = end_offset - start_offset
        next if width <= GeometryUtils::EPSILON

        FramingElements.create_header(
          wall_group.entities,
          axes,
          start_offset,
          width,
          elevation,
          Metadata.framing_member_tag('header', sequence * 1000 + index)
        )
      end
    end

    def layout_braces(wall_group, axes, length_interval, height_interval, sequence)
      height = height_interval.last
      FramingElements.create_brace(
        wall_group.entities,
        axes,
        length_interval.first,
        length_interval.last,
        height,
        Metadata.framing_member_tag('brace', sequence)
      )
      FramingElements.create_brace(
        wall_group.entities,
        axes,
        length_interval.last,
        length_interval.first,
        height,
        Metadata.framing_member_tag('brace', sequence + 1)
      )
    end

    def detect_openings(wall_group, axes)
      thickness_axis = axes.yaxis.clone.normalize
      faces = wall_group.entities.grep(Sketchup::Face)

      transformation = wall_group.transformation
      loop_intervals = faces.each_with_object([]) do |face, collection|
        normal = face.normal.clone
        normal.transform!(transformation)
        normal.normalize!
        angle = normal.angle_between(thickness_axis)
        next unless angle < 5.degrees || (Math::PI - angle) < 5.degrees

        face.loops.reject(&:outer?).each do |loop|
          projected = loop.vertices.map { |vertex| GeometryUtils.project_point(vertex.position, axes) }
          x_values = projected.map(&:x)
          next if x_values.empty?

          min_x = x_values.min
          max_x = x_values.max
          next if (max_x - min_x).abs < GeometryUtils::EPSILON

          collection << [min_x, max_x]
        end
      end

      return merge_intervals(loop_intervals) unless loop_intervals.empty?

      edges = wall_group.entities.grep(Sketchup::Edge)
      edge_intervals = edges.each_with_object([]) do |edge, collection|
        points = edge.vertices.map { |vertex| GeometryUtils.project_point(vertex.position, axes) }
        next if points.length < 2

        vector = points.first.vector_to(points.last)
        next unless vector.parallel?(Geom::Vector3d.new(0, 0, 1))

        x_values = points.map(&:x)
        collection << [x_values.min, x_values.max]
      end
      merge_intervals(edge_intervals)
    end

    def merge_intervals(intervals)
      sorted = intervals.sort_by(&:first)
      merged = []
      sorted.each do |interval|
        if merged.empty? || interval.first > merged.last.last + GeometryUtils::EPSILON
          merged << interval.dup
        else
          merged.last[1] = [merged.last.last, interval.last].max
        end
      end
      merged
    end

    unless file_loaded?(__FILE__)
      UI.menu('Plugins').add_item('SP Karkas Auto Framer') { activate }
      file_loaded(__FILE__)
    end
  end
end
