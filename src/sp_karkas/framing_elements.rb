require 'sketchup.rb'
require_relative 'geometry_utils'
require_relative 'metadata'

module SPKarkas
  module FramingElements
    DEFAULT_STUD_WIDTH = 38.mm
    DEFAULT_STUD_DEPTH = 89.mm
    DEFAULT_COLUMN_WIDTH = 150.mm
    DEFAULT_COLUMN_DEPTH = 150.mm
    DEFAULT_BEAM_WIDTH = 60.mm
    DEFAULT_BEAM_DEPTH = 180.mm

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

      xaxis = vector.clone
      xaxis.normalize!

      up = axes.zaxis
      up = axes.yaxis if up.nil? || up.cross(xaxis).length <= GeometryUtils::EPSILON
      return nil if up.nil?

      yaxis = up.cross(xaxis)
      return nil if yaxis.length <= GeometryUtils::EPSILON

      yaxis.normalize!
      zaxis = xaxis.cross(yaxis)
      return nil if zaxis.length <= GeometryUtils::EPSILON
      zaxis.normalize!

      orientation = GeometryUtils::LocalAxes.new(start_point, xaxis, yaxis, zaxis)
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

    def create_column(entities, axes, height, offset_x, offset_y, metadata = {})
      base = axes.origin.offset(axes.xaxis, offset_x).offset(axes.yaxis, offset_y)
      build_prismatic_member(
        entities,
        base,
        axes,
        DEFAULT_COLUMN_WIDTH,
        DEFAULT_COLUMN_DEPTH,
        height,
        metadata.merge('type' => 'column')
      )
    end

    def create_beam_along_x(entities, axes, start_offset, end_offset, y_offset, elevation, metadata = {})
      return nil if start_offset.nil? || end_offset.nil?
      if end_offset < start_offset
        start_offset, end_offset = end_offset, start_offset
      end
      length = end_offset - start_offset
      return nil if length <= GeometryUtils::EPSILON

      origin = axes.origin
      origin = origin.offset(axes.xaxis, start_offset)
      origin = origin.offset(axes.yaxis, y_offset)
      origin = origin.offset(axes.zaxis, elevation)

      orientation = GeometryUtils::LocalAxes.new(origin, axes.yaxis, axes.zaxis, axes.xaxis)

      build_prismatic_member(
        entities,
        origin,
        orientation,
        DEFAULT_BEAM_WIDTH,
        DEFAULT_BEAM_DEPTH,
        length,
        metadata.merge('type' => 'beam')
      )
    end

    def create_beam_along_y(entities, axes, start_offset, end_offset, x_offset, elevation, metadata = {})
      return nil if start_offset.nil? || end_offset.nil?
      if end_offset < start_offset
        start_offset, end_offset = end_offset, start_offset
      end
      length = end_offset - start_offset
      return nil if length <= GeometryUtils::EPSILON

      origin = axes.origin
      origin = origin.offset(axes.xaxis, x_offset)
      origin = origin.offset(axes.yaxis, start_offset)
      origin = origin.offset(axes.zaxis, elevation)

      orientation = GeometryUtils::LocalAxes.new(origin, axes.xaxis, axes.zaxis, axes.yaxis)

      build_prismatic_member(
        entities,
        origin,
        orientation,
        DEFAULT_BEAM_WIDTH,
        DEFAULT_BEAM_DEPTH,
        length,
        metadata.merge('type' => 'beam')
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
