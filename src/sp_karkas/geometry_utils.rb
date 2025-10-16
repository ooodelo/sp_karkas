require 'sketchup.rb'

module SPKarkas
  module GeometryUtils
    EPSILON = 1e-4

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
  end
end
