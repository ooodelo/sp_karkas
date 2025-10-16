require 'sketchup.rb'
require_relative 'geometry_utils'
require_relative 'metadata'

module SPKarkas
  module FramingElements
    DEFAULT_STUD_WIDTH = 38.mm
    DEFAULT_STUD_DEPTH = 89.mm

    module_function

    def create_stud(entities, axes, length, offset_along, metadata = {})
      origin = axes.origin.offset(axes.xaxis, offset_along)
      build_prismatic_member(entities, origin, axes, DEFAULT_STUD_WIDTH, DEFAULT_STUD_DEPTH, length, metadata.merge('type' => 'stud'))
    end

    def create_header(entities, axes, start_offset, width, elevation, metadata = {})
      origin = axes.origin.offset(axes.xaxis, start_offset).offset(axes.zaxis, elevation)
      return nil if width <= GeometryUtils::EPSILON

      build_prismatic_member(
        entities,
        origin,
        axes,
        width,
        DEFAULT_STUD_DEPTH,
        DEFAULT_STUD_WIDTH,
        metadata.merge('type' => 'header')
      )
    end

    def create_brace(entities, axes, start_offset, end_offset, height, metadata = {})
      start_point = axes.origin.offset(axes.xaxis, start_offset)
      end_point = axes.origin.offset(axes.xaxis, end_offset).offset(axes.zaxis, height)
      vector = start_point.vector_to(end_point)
      return nil if vector.length <= GeometryUtils::EPSILON
      orientation = GeometryUtils::LocalAxes.new(start_point, vector.normalize, axes.yaxis, axes.zaxis)
      build_prismatic_member(
        entities,
        start_point,
        orientation,
        DEFAULT_STUD_WIDTH,
        DEFAULT_STUD_DEPTH,
        vector.length,
        metadata.merge('type' => 'brace')
      )
    end

    def build_prismatic_member(entities, origin, axes, width, depth, height, metadata)
      group = entities.add_group
      base = [
        Geom::Point3d.new(-width / 2.0, -depth / 2.0, 0),
        Geom::Point3d.new(width / 2.0, -depth / 2.0, 0),
        Geom::Point3d.new(width / 2.0, depth / 2.0, 0),
        Geom::Point3d.new(-width / 2.0, depth / 2.0, 0)
      ]
      face = group.entities.add_face(base)
      face.pushpull(height)
      transformation = Geom::Transformation.axes(origin, axes.xaxis, axes.yaxis, axes.zaxis)
      group.transform!(transformation)
      Metadata.apply(group, metadata)
      group
    end
  end
end
