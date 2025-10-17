require_relative 'geometry_utils'

module SPKarkas
  module WallExtractor
    Wall = Struct.new(
      :name,
      :axis,
      :side,
      :plane,
      :axes,
      :length,
      :height,
      :horizontal_range,
      :height_range,
      :openings,
      :primary_axis,
      :secondary_axis,
      :horizontal_origin,
      :base_elevation,
      keyword_init: true
    )

    module_function

    def extract(selection)
      prism_planes = selection.prism_planes
      raise ArgumentError, 'Призм не прошла валидацию.' if prism_planes.nil?

      axes = selection.axes
      axis_vectors = {
        x: axes.xaxis.clone,
        y: axes.yaxis.clone,
        z: axes.zaxis.clone
      }

      walls = []
      [:x, :y].each do |axis|
        faces = prism_planes[axis]
        next unless faces

        [:min, :max].each do |side|
          plane = faces[side]
          next unless plane

          walls << build_wall(axis, side, plane, axis_vectors)
        end
      end

      walls
    end

    def build_wall(axis, side, plane, axis_vectors)
      primary_axis, secondary_axis = GeometryUtils::PLANE_AXES[axis]
      primary_bounds = plane.bounds[primary_axis]
      secondary_bounds = plane.bounds[secondary_axis]

      raise ArgumentError, 'Отсутствуют границы плоскости для стены.' if primary_bounds.nil? || secondary_bounds.nil?

      origin = point_from_components(
        axis => plane.offset,
        primary_axis => primary_bounds.first,
        secondary_axis => secondary_bounds.first
      )

      xaxis = axis_vectors[primary_axis].clone
      xaxis.normalize!

      zaxis = axis_vectors[secondary_axis].clone
      zaxis.normalize!

      yaxis = xaxis.cross(zaxis)
      if yaxis.length <= GeometryUtils::EPSILON
        zaxis = plane.normal.cross(xaxis)
        if zaxis.length <= GeometryUtils::EPSILON
          yaxis = plane.normal.clone
          yaxis.normalize!
          zaxis = xaxis.cross(yaxis)
        else
          zaxis.normalize!
          yaxis = xaxis.cross(zaxis)
        end
      end

      yaxis.normalize!
      zaxis = xaxis.cross(yaxis)
      if zaxis.length <= GeometryUtils::EPSILON
        zaxis = yaxis.cross(xaxis)
      end
      zaxis.normalize!

      if yaxis.dot(plane.normal) < 0
        yaxis.reverse!
        zaxis = xaxis.cross(yaxis)
        if zaxis.length <= GeometryUtils::EPSILON
          zaxis = yaxis.cross(xaxis)
        end
        zaxis.normalize!
      end

      length = primary_bounds.last - primary_bounds.first
      height = secondary_bounds.last - secondary_bounds.first

      Wall.new(
        name: wall_name(axis, side),
        axis: axis,
        side: side,
        plane: plane,
        axes: GeometryUtils::LocalAxes.new(origin, xaxis, yaxis, zaxis),
        length: length,
        height: height,
        horizontal_range: [0.0, length],
        height_range: [0.0, height],
        openings: [],
        primary_axis: primary_axis,
        secondary_axis: secondary_axis,
        horizontal_origin: primary_bounds.first,
        base_elevation: secondary_bounds.first
      )
    end

    def point_from_components(components)
      Geom::Point3d.new(
        components[:x] || 0,
        components[:y] || 0,
        components[:z] || 0
      )
    end

    def wall_name(axis, side)
      axis_label = axis.to_s.upcase
      orientation = side == :min ? 'MIN' : 'MAX'
      "Wall #{axis_label} #{orientation}"
    end
  end
end
