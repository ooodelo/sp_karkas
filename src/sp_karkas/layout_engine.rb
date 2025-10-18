require_relative 'framing_elements'
require_relative 'metadata'
require_relative 'geometry_utils'

module SPKarkas
  class LayoutEngine
    STUD_SPACING = 400.mm
    EDGE_OFFSET = 45.mm
    JACK_STUD_OFFSET = FramingElements::DEFAULT_STUD_WIDTH

    def initialize(entities, walls)
      @entities = entities
      @walls = walls
      @sequences = Hash.new(0)
    end

    def build
      studs = []
      headers = []
      top_plates = []
      bottom_plates = []

      @walls.each do |wall|
        studs.concat(place_wall_studs(wall))
        headers.concat(place_headers(wall))
        bottom_plates << place_bottom_plate(wall)
        top_plates << place_top_plate(wall)
      end

      corner_posts = place_corner_posts

      {
        studs: studs.compact,
        headers: headers.compact,
        top_plates: top_plates.compact,
        bottom_plates: bottom_plates.compact,
        corner_posts: corner_posts.compact
      }
    end

    private

    def place_wall_studs(wall)
      return [] if wall.length <= GeometryUtils::EPSILON

      length = wall.length
      height = wall.height
      positions = base_positions(length)
      openings = wall.openings.reject(&:degenerate?)

      openings.each do |opening|
        opening_width = opening.horizontal_range.last - opening.horizontal_range.first

        positions << opening.horizontal_range.first
        positions << opening.horizontal_range.last

        next unless opening_width > 2 * JACK_STUD_OFFSET + GeometryUtils::EPSILON

        positions << [opening.horizontal_range.first - JACK_STUD_OFFSET, 0.0].max
        positions << [opening.horizontal_range.last + JACK_STUD_OFFSET, length].min
      end

      positions = normalize_positions(positions, length)
      full_height_studs = positions.reject { |offset| inside_opening?(offset, openings) }

      studs = full_height_studs.map do |offset|
        FramingElements.create_stud(
          @entities,
          wall.axes,
          height,
          offset,
          Metadata.framing_member_tag('stud', next_sequence(:stud))
        )
      end

      studs.concat(place_jack_studs(wall))
    end

    def place_jack_studs(wall)
      wall.openings.reject(&:degenerate?).flat_map do |opening|
        jack_height = opening.vertical_range.first
        next [] if jack_height <= GeometryUtils::EPSILON

        left = opening.horizontal_range.first + JACK_STUD_OFFSET
        right = opening.horizontal_range.last - JACK_STUD_OFFSET

        next [] if right - left <= GeometryUtils::EPSILON

        length = wall.length
        left = [[left, 0.0].max, length].min
        right = [[right, 0.0].max, length].min

        next [] if right - left <= GeometryUtils::EPSILON

        [left, right].map do |offset|
          FramingElements.create_stud(
            @entities,
            wall.axes,
            jack_height,
            offset,
            Metadata.framing_member_tag('jack_stud', next_sequence(:stud))
          )
        end
      end
    end

    def place_headers(wall)
      wall.openings.reject(&:degenerate?).map do |opening|
        width = opening.horizontal_range.last - opening.horizontal_range.first
        next if width <= GeometryUtils::EPSILON

        FramingElements.create_header(
          @entities,
          wall.axes,
          opening.horizontal_range.first,
          width,
          opening.vertical_range.last,
          Metadata.framing_member_tag('header', next_sequence(:header))
        )
      end.compact
    end

    def base_positions(length)
      positions = [0.0, length]
      return positions if length <= 2 * EDGE_OFFSET + GeometryUtils::EPSILON

      current = EDGE_OFFSET
      while current < length - EDGE_OFFSET - GeometryUtils::EPSILON
        positions << current
        current += STUD_SPACING
      end

      positions
    end

    def normalize_positions(positions, length)
      clamped = positions.map { |pos| [[pos, 0.0].max, length].min }
      sorted = clamped.sort
      unique = []

      sorted.each do |value|
        if unique.empty? || (value - unique.last).abs > GeometryUtils::EPSILON
          unique << value
        end
      end

      unique
    end

    def inside_opening?(offset, openings)
      openings.any? do |opening|
        opening.horizontal_range.first + GeometryUtils::EPSILON < offset &&
          offset < opening.horizontal_range.last - GeometryUtils::EPSILON
      end
    end

    def next_sequence(category)
      @sequences[category] += 1
    end

    def place_bottom_plate(wall)
      return nil if wall.length <= GeometryUtils::EPSILON

      FramingElements.create_plate(
        @entities,
        wall.axes,
        wall.horizontal_range.first,
        wall.length,
        0.0,
        Metadata.framing_member_tag('bottom_plate', next_sequence(:plate))
      )
    end

    def place_top_plate(wall)
      return nil if wall.length <= GeometryUtils::EPSILON

      FramingElements.create_plate(
        @entities,
        wall.axes,
        wall.horizontal_range.first,
        wall.length,
        wall.height - FramingElements::DEFAULT_PLATE_THICKNESS,
        Metadata.framing_member_tag('top_plate', next_sequence(:plate))
      )
    end

    def place_corner_posts
      return [] if @walls.empty?

      corners = corner_points
      return [] if corners.empty?

      height = @walls.map(&:height).max
      width = FramingElements::DEFAULT_CORNER_POST_WIDTH
      depth = FramingElements::DEFAULT_CORNER_POST_DEPTH

      min_x, max_x = corners.map { |corner| corner.x }.minmax
      min_y, max_y = corners.map { |corner| corner.y }.minmax

      corners.map do |corner|
        x_offset = corner_offset(corner.x, min_x, max_x, width)
        y_offset = corner_offset(corner.y, min_y, max_y, depth)

        origin = Geom::Point3d.new(corner.x + x_offset, corner.y + y_offset, corner.z)
        axes = GeometryUtils::LocalAxes.new(
          origin,
          Geom::Vector3d.new(1, 0, 0),
          Geom::Vector3d.new(0, 1, 0),
          Geom::Vector3d.new(0, 0, 1)
        )

        FramingElements.create_corner_post(
          @entities,
          axes,
          height,
          Metadata.framing_member_tag('corner_post', next_sequence(:corner_post)),
          width: width,
          depth: depth
        )
      end
    end

    def corner_points
      @corner_points ||= begin
        points = @walls.flat_map do |wall|
          start_point = wall.axes.origin
          end_point = start_point.offset(wall.axes.xaxis, wall.length)
          [start_point, end_point]
        end

        deduplicate_points(points)
      end
    end

    def deduplicate_points(points)
      unique = []

      points.each do |point|
        next if unique.any? { |existing| (existing.distance(point)) <= GeometryUtils::EPSILON }

        unique << point
      end

      unique
    end

    def corner_offset(coordinate, min_value, max_value, size)
      midpoint = (min_value + max_value) / 2.0
      coordinate < midpoint ? size / 2.0 : -size / 2.0
    end
  end
end
