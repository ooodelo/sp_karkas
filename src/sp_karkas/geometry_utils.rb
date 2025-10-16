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
      axes = [Geom::Vector3d.new(1, 0, 0), Geom::Vector3d.new(0, 1, 0), Geom::Vector3d.new(0, 0, 1)]
      paired = axes.zip(lengths)

      height_axis = paired.max_by { |(_, length)| length }
      thickness_axis = paired.min_by { |(_, length)| length }
      length_axis = (paired - [height_axis, thickness_axis]).first

      origin_point = Geom::Point3d.new(local_bounds.min.x, local_bounds.min.y, local_bounds.min.z)
      tr = group.transformation
      origin = origin_point.transform(tr)
      LocalAxes.new(
        origin,
        transform_axis(tr, length_axis[0]),
        transform_axis(tr, thickness_axis[0]),
        transform_axis(tr, height_axis[0])
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
