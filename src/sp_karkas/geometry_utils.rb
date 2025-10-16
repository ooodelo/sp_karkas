require 'sketchup.rb'

module SPKarkas
  module GeometryUtils
    EPSILON = 1e-4

    AXES = [
      Geom::Vector3d.new(1, 0, 0),
      Geom::Vector3d.new(0, 1, 0),
      Geom::Vector3d.new(0, 0, 1)
    ].freeze

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

    def rectangular_prism?(group)
      faces = group.entities.grep(Sketchup::Face)
      return false unless faces.length == 6

      inverse = group.transformation.inverse

      face_axes = faces.map do |face|
        normal = face.normal.clone
        normal.transform!(group.transformation)
        normal.normalize!
        axis = AXES.max_by { |candidate| candidate.dot(normal).abs }
        return false if axis.nil?
        return false if 1.0 - normal.dot(axis).abs > 1e-3
        axis
      end

      counts = face_axes.tally
      return false unless counts.values.all? { |count| count == 2 }

      bounds = group.local_bounds
      return false if (bounds.max.x - bounds.min.x).abs <= EPSILON
      return false if (bounds.max.y - bounds.min.y).abs <= EPSILON
      return false if (bounds.max.z - bounds.min.z).abs <= EPSILON
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

      corner_signatures = corners.map { |pt| [pt.x, pt.y, pt.z].map { |value| value.round(6) } }

      vertices = group.entities.grep(Sketchup::Edge).flat_map(&:vertices).uniq
      vertex_signatures = vertices.map do |vertex|
        point = vertex.position.transform(inverse)
        [point.x, point.y, point.z].map { |value| value.round(6) }
      end

      return false unless vertex_signatures.all? { |signature| corner_signatures.include?(signature) }
      return false unless corner_signatures.uniq.length == 8

      edges = group.entities.grep(Sketchup::Edge)
      edges.all? do |edge|
        vector = edge.start.position.vector_to(edge.end.position)
        vector.transform!(inverse)
        next false if vector.length <= EPSILON
        vector.normalize!
        AXES.any? do |axis|
          vector.parallel?(axis) || vector.parallel?(axis.clone.reverse!)
        end
      end
    rescue StandardError
      false
    end
  end
end
