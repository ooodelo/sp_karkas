require 'sketchup.rb'
require_relative 'geometry_utils'
require_relative 'framing_elements'
require_relative 'metadata'
require_relative 'validator'
require_relative 'wall_extractor'
require_relative 'opening_extractor'
require_relative 'layout_engine'

module SPKarkas
  module AutoFramer
    extend self

    def activate
      model = Sketchup.active_model
      selection = SelectionScanner.new(model.selection).scan

      return if selection.nil?

      validation = Validator.validate(selection)
      unless validation.valid?
        UI.messagebox(validation.message)
        return
      end

      selection.prism_planes = validation.prism_planes
      selection.dimensions = validation.dimensions

      walls = WallExtractor.extract(selection)
      OpeningExtractor.assign!(walls)

      model.start_operation('SP Karkas Auto Framer', true)
      frame_group = build_frame(selection, walls)
      model.selection.clear
      model.selection.add(frame_group)
      model.commit_operation
      UI.messagebox('Каркас создан на месте выбранного параллелепипеда.')
    rescue StandardError => error
      model.abort_operation
      UI.messagebox("Auto Framer failed: #{error.message}")
      raise error
    end

    def build_frame(selection, walls)
      bounds = selection.bounds
      length = bounds.max.x - bounds.min.x
      width = bounds.max.y - bounds.min.y
      height = bounds.max.z - bounds.min.z

      frame_group = selection.parent_entities.add_group
      frame_group.name = 'SP Karkas Frame'

      layout = LayoutEngine.new(frame_group.entities, walls)
      layout_results = layout.build

      Metadata.apply(
        frame_group,
        Metadata.frame_tag(
          length: length,
          width: width,
          height: height,
          studs: layout_results[:studs].length,
          headers: layout_results[:headers].length,
          top_plates: layout_results[:top_plates].length,
          bottom_plates: layout_results[:bottom_plates].length,
          corner_posts: layout_results[:corner_posts].length
        )
      )

      frame_group
    end

    class SelectionScanner
      NormalizedSelection = Struct.new(:entities, :transformation, :parent_entities, :bounds, :world_vertices, :prism_planes, :dimensions) do
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

        NormalizedSelection.new(entities, transformation, parent_entities, bounds, world_vertices, nil, nil)
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
