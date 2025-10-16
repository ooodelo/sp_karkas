require_relative 'geometry_utils'

module SPKarkas
  module OpeningExtractor
    OPENING_CLEARANCE = 6.mm
    SILL_THRESHOLD = 0.1.m

    Opening = Struct.new(
      :type,
      :horizontal_range,
      :vertical_range,
      :raw_horizontal_range,
      :raw_vertical_range,
      keyword_init: true
    )

    module_function

    def assign!(walls)
      walls.each do |wall|
        wall.openings = extract_for_wall(wall)
      end
    end

    def extract_for_wall(wall)
      plane = wall.plane
      return [] if plane.nil? || plane.inner_loops.empty?

      primary_axis = wall.primary_axis
      secondary_axis = wall.secondary_axis

      plane.inner_loops.map do |loop_points|
        primary_values = loop_points.map { |point| point.public_send(primary_axis) }
        secondary_values = loop_points.map { |point| point.public_send(secondary_axis) }

        horizontal_range = [primary_values.min, primary_values.max]
        vertical_range = [secondary_values.min, secondary_values.max]

        local_horizontal = to_local(horizontal_range, wall.horizontal_origin)
        local_vertical = to_local(vertical_range, wall.base_elevation)

        Opening.new(
          type: classify_opening(local_vertical),
          horizontal_range: apply_clearance(local_horizontal, wall.horizontal_range),
          vertical_range: apply_clearance(local_vertical, wall.height_range),
          raw_horizontal_range: local_horizontal,
          raw_vertical_range: local_vertical
        )
      end
    end

    def to_local(range, origin)
      [range.first - origin, range.last - origin]
    end

    def apply_clearance(range, wall_range)
      expanded = GeometryUtils.expand_interval(range, OPENING_CLEARANCE)
      lower = [expanded.first, wall_range.first].max
      upper = [expanded.last, wall_range.last].min
      upper = [upper, lower].max
      [lower, upper]
    end

    def classify_opening(vertical_range)
      return :door if vertical_range.first <= SILL_THRESHOLD

      :window
    end
  end
end
