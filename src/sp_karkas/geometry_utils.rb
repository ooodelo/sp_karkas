require 'sketchup.rb'

module SPKarkas
  module GeometryUtils
    EPSILON = 1e-4
    PLANE_OFFSET_ABS_EPSILON = 1e-6

    AXES = [
      Geom::Vector3d.new(1, 0, 0),
      Geom::Vector3d.new(0, 1, 0),
      Geom::Vector3d.new(0, 0, 1)
    ].freeze

    AXIS_LABELS = %i[x y z].freeze

    AXIS_VECTORS = AXIS_LABELS.zip(AXES).to_h.freeze

    PLANE_AXES = {
      x: %i[y z],
      y: %i[x z],
      z: %i[x y]
    }.freeze

    PlaneDescription = Struct.new(
      :axis,
      :offset,
      :normal,
      :outer_loops,
      :inner_loops,
      :bounds,
      :point,
      :plane,
      :tolerance,
      keyword_init: true
    )

    LocalAxes = Struct.new(:origin, :xaxis, :yaxis, :zaxis) do
      def to_transformation
        Geom::Transformation.axes(origin, xaxis, yaxis, zaxis)
      end

      def inverse
        to_transformation.inverse
      end
    end

    module_function

    def axis_lengths(bounds)
      [
        bounds.max.x - bounds.min.x,
        bounds.max.y - bounds.min.y,
        bounds.max.z - bounds.min.z
      ]
    end

    def wall_axes(group)
      local_bounds = group.local_bounds
      lengths = axis_lengths(local_bounds)
      local_axes = [
        { axis: Geom::Vector3d.new(1, 0, 0), length: lengths[0] },
        { axis: Geom::Vector3d.new(0, 1, 0), length: lengths[1] },
        { axis: Geom::Vector3d.new(0, 0, 1), length: lengths[2] }
      ]

      tr = group.transformation
      up_vector = Geom::Vector3d.new(0, 0, 1)
      axis_data = local_axes.map do |entry|
        transformed = transform_axis(tr, entry[:axis])
        entry.merge(
          transformed: transformed,
          up_alignment: transformed.dot(up_vector).abs
        )
      end

      vertical_axis = axis_data.max_by { |entry| entry[:up_alignment] }
      remaining_axes = axis_data - [vertical_axis]
      length_axis = remaining_axes.max_by { |entry| entry[:length] }
      thickness_axis = (remaining_axes - [length_axis]).first

      origin_point = Geom::Point3d.new(local_bounds.min.x, local_bounds.min.y, local_bounds.min.z)
      origin = origin_point.transform(tr)
      LocalAxes.new(
        origin,
        length_axis[:transformed],
        thickness_axis[:transformed],
        vertical_axis[:transformed]
      )
    end

    def axis_intervals(group, axes)
      bounds = group.local_bounds
      transformation = group.transformation
      inverse_axes = axes.inverse

      corners = [
        Geom::Point3d.new(bounds.min.x, bounds.min.y, bounds.min.z),
        Geom::Point3d.new(bounds.max.x, bounds.min.y, bounds.min.z),
        Geom::Point3d.new(bounds.min.x, bounds.max.y, bounds.min.z),
        Geom::Point3d.new(bounds.min.x, bounds.min.y, bounds.max.z),
        Geom::Point3d.new(bounds.max.x, bounds.max.y, bounds.min.z),
        Geom::Point3d.new(bounds.max.x, bounds.min.y, bounds.max.z),
        Geom::Point3d.new(bounds.min.x, bounds.max.y, bounds.max.z),
        Geom::Point3d.new(bounds.max.x, bounds.max.y, bounds.max.z)
      ]

      projected = corners.map do |corner|
        world_point = corner.transform(transformation)
        world_point.transform(inverse_axes)
      end

      xs = projected.map(&:x)
      ys = projected.map(&:y)
      zs = projected.map(&:z)

      {
        x: [xs.min, xs.max],
        y: [ys.min, ys.max],
        z: [zs.min, zs.max]
      }
    end

    def transform_axis(transformation, axis)
      axis = axis.clone
      axis.transform!(transformation)
      axis.normalize!
      axis
    end

    def project_point(point, axes)
      relative = point.transform(axes.inverse)
      Geom::Point3d.new(relative.x, relative.y, relative.z)
    end

    def interval_contains?(interval, value)
      value >= (interval.first - EPSILON) && value <= (interval.last + EPSILON)
    end

    def nearly_equal?(a, b)
      (a - b).abs <= EPSILON
    end

    def on_boundary?(value, interval)
      nearly_equal?(value, interval.first) || nearly_equal?(value, interval.last)
    end

    def expand_interval(interval, amount)
      [interval.first - amount, interval.last + amount]
    end

    def evenly_spaced_positions(interval, spacing)
      length = interval.last - interval.first
      return [] if length < spacing
      positions = []
      count = (length / spacing).floor - 1
      count = 0 if count.negative?
      count.times do |index|
        positions << interval.first + spacing * (index + 1)
      end
      positions
    end

    def rectangular_prism?(entities, transformation)
      faces = entities.grep(Sketchup::Face)
      return false if faces.empty?

      bounds = compute_bounds(entities)
      tolerance = plane_offset_tolerance(bounds)

      plane_groups = group_faces_by_plane(faces, transformation, tolerance)
      return false if plane_groups.nil?

      axis_planes = {}

      AXIS_LABELS.each do |axis|
        groups = plane_groups[axis] || []
        return false unless groups.length == 2

        groups.each do |group|
          return false unless validate_plane_group(axis, group, tolerance)
        end

        sorted = groups.sort_by(&:offset)
        axis_planes[axis] = { min: sorted.first, max: sorted.last }
      end

      axis_planes.each_value do |pair|
        difference = pair[:max].offset - pair[:min].offset
        return false if difference.abs <= EPSILON
      end

      axis_planes
    rescue StandardError
      false
    end

    def compute_bounds(entities)
      bounds = Geom::BoundingBox.new
      entities.each do |entity|
        next unless entity.respond_to?(:bounds)
        bounds.add(entity.bounds)
      end
      bounds
    end

    def group_faces_by_plane(faces, transformation, tolerance)
      grouped = Hash.new { |hash, key| hash[key] = [] }

      faces.each do |face|
        plane_info = describe_face_plane(face, transformation)
        return nil if plane_info.nil?

        axis = plane_info[:axis]
        axis_groups = grouped[axis]

        group = find_existing_plane_group(axis_groups, plane_info[:offset], tolerance)
        unless group
          group = PlaneDescription.new(
            axis: axis,
            offset: plane_info[:offset],
            normal: plane_info[:normal],
            outer_loops: [],
            inner_loops: [],
            bounds: nil,
            point: nil,
            plane: nil,
            tolerance: tolerance
          )
          axis_groups << group
        else
          group.normal = combine_normals(group.normal, plane_info[:normal])
        end

        group.outer_loops.concat(plane_info[:outer_loops])
        group.inner_loops.concat(plane_info[:inner_loops])
      end

      grouped
    end

    def describe_face_plane(face, transformation)
      normal = face.normal.clone
      normal.transform!(transformation)
      normal.normalize!

      axis_vector = AXES.max_by { |candidate| candidate.dot(normal).abs }
      return nil unless axis_vector

      alignment = 1.0 - normal.dot(axis_vector).abs
      return nil if alignment > 1e-3

      axis_index = AXES.index(axis_vector)
      axis_label = AXIS_LABELS[axis_index]

      outer_loops = []
      inner_loops = []

      face.loops.each do |loop|
        points = loop.vertices.map { |vertex| vertex.position.transform(transformation) }
        if loop.outer?
          outer_loops << points
        else
          inner_loops << points
        end
      end

      return nil if outer_loops.empty?

      axis_values = outer_loops.flat_map do |points|
        points.map { |point| point.public_send(axis_label) }
      end

      offset = axis_values.sum / axis_values.length.to_f

      {
        axis: axis_label,
        normal: normal,
        offset: offset,
        outer_loops: outer_loops,
        inner_loops: inner_loops
      }
    end

    def find_existing_plane_group(groups, offset, tolerance)
      groups.find { |group| plane_offset_equal?(group.offset, offset, tolerance) }
    end

    def validate_plane_group(axis, group, tolerance)
      tolerance ||= group.tolerance || PLANE_OFFSET_ABS_EPSILON
      outer_points = group.outer_loops.flat_map { |points| points }
      return false if outer_points.empty?

      axis_values = outer_points.map { |point| point.public_send(axis) }
      reference_offset = group.offset

      return false unless axis_values.all? { |value| plane_offset_equal?(value, reference_offset, tolerance) }

      primary_axis, secondary_axis = PLANE_AXES[axis]

      return false unless edges_axis_aligned?(group.outer_loops, axis, primary_axis, secondary_axis)

      primary_values = unique_values(group.outer_loops, primary_axis)
      secondary_values = unique_values(group.outer_loops, secondary_axis)

      return false unless primary_values.length == 2 && secondary_values.length == 2

      primary_min, primary_max = primary_values.minmax
      secondary_min, secondary_max = secondary_values.minmax

      return false if nearly_equal?(primary_min, primary_max)
      return false if nearly_equal?(secondary_min, secondary_max)

      corners = [primary_min, primary_max].product([secondary_min, secondary_max])
      corners.each do |primary_value, secondary_value|
        next if outer_points.any? do |point|
          nearly_equal?(point.public_send(primary_axis), primary_value) &&
            nearly_equal?(point.public_send(secondary_axis), secondary_value)
        end

        return false
      end

      group.point = outer_points.first
      group.bounds = {
        primary_axis => [primary_min, primary_max],
        secondary_axis => [secondary_min, secondary_max]
      }

      normalize_group_normal!(group, axis)

      group.plane = plane_from_point_and_normal(group.point, group.normal)

      true
    end

    def edges_axis_aligned?(loops, axis, primary_axis, secondary_axis)
      loops.each do |points|
        point_count = points.length
        return false if point_count < 2

        points.each_with_index do |point, index|
          next_point = points[(index + 1) % point_count]
          vector = point.vector_to(next_point)
          return false if vector.length <= EPSILON

          axis_delta = vector.public_send(axis)
          primary_delta = vector.public_send(primary_axis)
          secondary_delta = vector.public_send(secondary_axis)

          return false unless nearly_equal?(axis_delta, 0.0)

          primary_changed = !nearly_equal?(primary_delta, 0.0)
          secondary_changed = !nearly_equal?(secondary_delta, 0.0)

          return false if primary_changed && secondary_changed
          return false unless primary_changed || secondary_changed
        end
      end

      true
    end

    def unique_values(loops, axis)
      values = loops.flat_map { |points| points.map { |point| point.public_send(axis) } }
      values.each_with_object([]) do |value, uniques|
        uniques << value unless uniques.any? { |existing| nearly_equal?(existing, value) }
      end
    end

    def normalize_group_normal!(group, axis)
      normalized = group.normal.clone
      length = normalized.length

      if length.zero?
        normalized = AXIS_VECTORS[axis].clone
        normalized.normalize!
      else
        normalized.normalize!
      end

      group.normal = normalized
    end

    def combine_normals(first, second)
      combined = Geom::Vector3d.new(first.x + second.x, first.y + second.y, first.z + second.z)
      return first.clone.tap(&:normalize!) if combined.length.zero?

      combined.normalize!
      combined
    end

    def plane_offset_equal?(first, second, tolerance)
      (first - second).abs <= tolerance
    end

    def plane_offset_tolerance(bounds)
      diagonal = bounding_box_diagonal(bounds)
      [PLANE_OFFSET_ABS_EPSILON, diagonal * 1e-6].max
    end

    def bounding_box_diagonal(bounds)
      return 0.0 if bounds.nil?

      min = bounds.min
      max = bounds.max

      dx = max.x - min.x
      dy = max.y - min.y
      dz = max.z - min.z

      Math.sqrt(dx * dx + dy * dy + dz * dz)
    end

    def plane_from_point_and_normal(point, normal)
      a = normal.x
      b = normal.y
      c = normal.z
      d = -(a * point.x + b * point.y + c * point.z)
      [a, b, c, d]
    end
  end
end
