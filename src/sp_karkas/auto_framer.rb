require 'sketchup.rb'
require_relative 'geometry_utils'
require_relative 'framing_elements'
require_relative 'metadata'

module SPKarkas
  module AutoFramer
    extend self

    COLUMN_SPACING = 3.m
    LEVEL_HEIGHT = 3.m

    def activate
      model = Sketchup.active_model
      selection = SelectionScanner.new(model.selection).scan

      return if selection.nil?

      prism_planes = GeometryUtils.rectangular_prism?(selection.entities, selection.transformation)
      unless prism_planes
        UI.messagebox('Выбранный объект должен представлять прямоугольный параллелепипед без дополнительных элементов.')
        return
      end

      selection.prism_planes = prism_planes

      model.start_operation('SP Karkas Auto Framer', true)
      frame_group = build_frame(selection)
      model.selection.clear
      model.selection.add(frame_group)
      model.commit_operation
      UI.messagebox('Каркас создан на месте выбранного параллелепипеда.')
    rescue StandardError => error
      model.abort_operation
      UI.messagebox("Auto Framer failed: #{error.message}")
      raise error
    end

    def build_frame(selection)
      bounds = selection.bounds
      length = bounds.max.x - bounds.min.x
      width = bounds.max.y - bounds.min.y
      height = bounds.max.z - bounds.min.z

      axes = selection.axes

      length_interval = [0, length]
      width_interval = [0, width]
      height_interval = [0, height]

      frame_group = selection.parent_entities.add_group
      frame_group.name = 'SP Karkas Frame'

      columns = layout_columns(frame_group.entities, axes, length_interval, width_interval, height_interval)
      beams = layout_beams(frame_group.entities, axes, length_interval, width_interval, height_interval)
      braces = layout_bracing(frame_group.entities, axes, length_interval, width_interval, height_interval)

      Metadata.apply(
        frame_group,
        Metadata.frame_tag(
          length: length,
          width: width,
          height: height,
          columns: columns.length,
          beams: beams.length,
          braces: braces.length
        )
      )

      frame_group
    end

    def layout_columns(entities, axes, length_interval, width_interval, height_interval)
      height = height_interval.last - height_interval.first
      x_positions = ([length_interval.first, length_interval.last] + GeometryUtils.evenly_spaced_positions(length_interval, COLUMN_SPACING)).uniq
      y_positions = ([width_interval.first, width_interval.last] + GeometryUtils.evenly_spaced_positions(width_interval, COLUMN_SPACING)).uniq

      sequence = 0
      x_positions.sort.flat_map do |x_offset|
        y_positions.sort.map do |y_offset|
          next unless GeometryUtils.on_boundary?(x_offset, length_interval) || GeometryUtils.on_boundary?(y_offset, width_interval)

          sequence += 1
          FramingElements.create_column(
            entities,
            axes,
            height,
            x_offset,
            y_offset,
            Metadata.framing_member_tag('column', sequence)
          )
        end
      end.compact
    end

    def layout_beams(entities, axes, length_interval, width_interval, height_interval)
      base = height_interval.first
      top = height_interval.last
      height = top - base

      level_count = (height / LEVEL_HEIGHT).floor
      intermediate_levels = (1...level_count).map { |index| base + index * LEVEL_HEIGHT }
      elevations = ([base, top] + intermediate_levels).uniq.sort

      sequence = 0
      elevations.flat_map do |elevation|
        adjusted_elevation = elevation
        members = []

        [width_interval.first, width_interval.last].each do |y_offset|
          sequence += 1
          members << FramingElements.create_beam_along_x(
            entities,
            axes,
            length_interval.first,
            length_interval.last,
            y_offset,
            adjusted_elevation,
            Metadata.framing_member_tag('beam', sequence)
          )
        end

        [length_interval.first, length_interval.last].each do |x_offset|
          sequence += 1
          members << FramingElements.create_beam_along_y(
            entities,
            axes,
            width_interval.first,
            width_interval.last,
            x_offset,
            adjusted_elevation,
            Metadata.framing_member_tag('beam', sequence)
          )
        end

        members.compact
      end
    end

    def layout_bracing(entities, axes, length_interval, width_interval, height_interval)
      height = height_interval.last - height_interval.first
      sequence = 0
      members = []

      [width_interval.first, width_interval.last].each do |y_offset|
        face_origin = axes.origin.offset(axes.yaxis, y_offset)
        face_axes = GeometryUtils::LocalAxes.new(face_origin, axes.xaxis, axes.yaxis, axes.zaxis)

        sequence += 1
        members << FramingElements.create_brace(
          entities,
          face_axes,
          length_interval.first,
          length_interval.last,
          height,
          Metadata.framing_member_tag('brace', sequence)
        )

        sequence += 1
        members << FramingElements.create_brace(
          entities,
          face_axes,
          length_interval.last,
          length_interval.first,
          height,
          Metadata.framing_member_tag('brace', sequence)
        )
      end

      [length_interval.first, length_interval.last].each do |x_offset|
        face_origin = axes.origin.offset(axes.xaxis, x_offset)
        face_axes = GeometryUtils::LocalAxes.new(face_origin, axes.yaxis, axes.xaxis, axes.zaxis)

        sequence += 1
        members << FramingElements.create_brace(
          entities,
          face_axes,
          width_interval.first,
          width_interval.last,
          height,
          Metadata.framing_member_tag('brace', sequence)
        )

        sequence += 1
        members << FramingElements.create_brace(
          entities,
          face_axes,
          width_interval.last,
          width_interval.first,
          height,
          Metadata.framing_member_tag('brace', sequence)
        )
      end

      members.compact
    end

    class SelectionScanner
      NormalizedSelection = Struct.new(:entities, :transformation, :parent_entities, :bounds, :world_vertices, :prism_planes) do
        def axes
          @axes ||= begin
            origin_local = Geom::Point3d.new(bounds.min.x, bounds.min.y, bounds.min.z)
            origin = origin_local.transform(transformation)
            xaxis = Geom::Vector3d.new(1, 0, 0).transform(transformation)
            yaxis = Geom::Vector3d.new(0, 1, 0).transform(transformation)
            zaxis = Geom::Vector3d.new(0, 0, 1).transform(transformation)
            xaxis.normalize!
            yaxis.normalize!
            zaxis.normalize!
            GeometryUtils::LocalAxes.new(origin, xaxis, yaxis, zaxis)
          end
        end

        def world_bounds
          @world_bounds ||= begin
            bounding_box = Geom::BoundingBox.new
            world_vertices.each { |vertex| bounding_box.add(vertex) }
            bounding_box
          end
        end
      end

      def initialize(selection)
        @selection = selection
      end

      def scan
        candidates = @selection.grep(Sketchup::Group) + @selection.grep(Sketchup::ComponentInstance)

        if candidates.length != 1
          UI.messagebox('Выберите один объект (группу или компонент), прежде чем запускать SP Karkas Auto Framer.')
          return nil
        end

        instance = candidates.first
        entities = extract_entities(instance)
        transformation = instance.transformation
        parent_entities = resolve_parent_entities(instance)
        bounds = GeometryUtils.compute_bounds(entities)
        world_vertices = collect_world_vertices(entities, transformation)

        NormalizedSelection.new(entities, transformation, parent_entities, bounds, world_vertices, nil)
      end

      private

      def extract_entities(instance)
        case instance
        when Sketchup::Group
          instance.entities
        when Sketchup::ComponentInstance
          instance.definition.entities
        else
          raise ArgumentError, "Unsupported selection type: #{instance.class}"
        end
      end

      def resolve_parent_entities(instance)
        parent = instance.parent
        return parent if parent.is_a?(Sketchup::Entities)
        return parent.entities if parent.respond_to?(:entities)

        raise ArgumentError, 'Unable to resolve parent entities for selection.'
      end

      def collect_world_vertices(entities, transformation)
        entities.grep(Sketchup::Edge).flat_map(&:vertices).uniq.map do |vertex|
          vertex.position.transform(transformation)
        end
      end
    end

    unless file_loaded?(__FILE__)
      UI.menu('Plugins').add_item('SP Karkas Auto Framer') { activate }
      file_loaded(__FILE__)
    end
  end
end
