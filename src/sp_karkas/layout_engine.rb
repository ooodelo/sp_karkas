require_relative 'framing_elements'
require_relative 'metadata'
require_relative 'geometry_utils'

module SPKarkas
  class LayoutEngine
    STUD_SPACING = 400.mm
    EDGE_OFFSET = 45.mm
    JACK_STUD_OFFSET = FramingElements::DEFAULT_STUD_WIDTH

    def initialize(entities, walls, include_braces: true)
      @entities = entities
      @walls = walls
      @include_braces = include_braces
      @sequences = Hash.new(0)
    end

    def build
      studs = []
      headers = []
      braces = []

      @walls.each do |wall|
        studs.concat(place_wall_studs(wall))
        headers.concat(place_headers(wall))
        braces.concat(place_braces(wall)) if @include_braces
      end

      {
        studs: studs.compact,
        headers: headers.compact,
        braces: braces.compact
      }
    end

    private

    def place_wall_studs(wall)
      return [] if wall.length <= GeometryUtils::EPSILON

      length = wall.length
      height = wall.height
      positions = base_positions(length)
      openings = wall.openings

      openings.each do |opening|
        positions << opening.horizontal_range.first
        positions << opening.horizontal_range.last
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
      wall.openings.flat_map do |opening|
        jack_height = opening.vertical_range.last
        next [] if jack_height <= GeometryUtils::EPSILON

        left = opening.horizontal_range.first + JACK_STUD_OFFSET
        right = opening.horizontal_range.last - JACK_STUD_OFFSET

        next [] if right - left <= GeometryUtils::EPSILON

        [left, right].uniq.map do |offset|
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
      wall.openings.map do |opening|
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

    def place_braces(wall)
      return [] unless wall.openings.empty?
      return [] if wall.length <= GeometryUtils::EPSILON || wall.height <= GeometryUtils::EPSILON

      [
        FramingElements.create_brace(
          @entities,
          wall.axes,
          wall.horizontal_range.first,
          wall.horizontal_range.last,
          wall.height,
          Metadata.framing_member_tag('brace', next_sequence(:brace))
        ),
        FramingElements.create_brace(
          @entities,
          wall.axes,
          wall.horizontal_range.last,
          wall.horizontal_range.first,
          wall.height,
          Metadata.framing_member_tag('brace', next_sequence(:brace))
        )
      ].compact
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
      sorted = positions.map { |pos| [[pos, 0.0].max, length].min }
      sorted.sort.each_with_object([]) do |value, unique|
        unique << value unless unique.any? { |existing| (existing - value).abs <= GeometryUtils::EPSILON }
      end
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
  end
end
