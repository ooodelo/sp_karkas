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
      selection = model.selection.grep(Sketchup::Group)

      if selection.length != 1
        UI.messagebox('Выберите одну группу-параллелепипед, прежде чем запускать SP Karkas Auto Framer.')
        return
      end

      shell_group = selection.first
      unless GeometryUtils.rectangular_prism?(shell_group)
        UI.messagebox('Выбранная группа должна представлять прямоугольный параллелепипед без дополнительных элементов.')
        return
      end

      model.start_operation('SP Karkas Auto Framer', true)
      frame_group = build_frame(shell_group)
      model.selection.clear
      model.selection.add(frame_group)
      model.commit_operation
      UI.messagebox('Каркас создан на месте выбранного параллелепипеда.')
    rescue StandardError => error
      model.abort_operation
      UI.messagebox("Auto Framer failed: #{error.message}")
      raise error
    end

    def build_frame(shell_group)
      bounds = shell_group.local_bounds
      length = bounds.max.x - bounds.min.x
      width = bounds.max.y - bounds.min.y
      height = bounds.max.z - bounds.min.z

      axes_origin = Geom::Point3d.new(bounds.min.x, bounds.min.y, bounds.min.z)
      axes = GeometryUtils::LocalAxes.new(
        axes_origin,
        Geom::Vector3d.new(1, 0, 0),
        Geom::Vector3d.new(0, 1, 0),
        Geom::Vector3d.new(0, 0, 1)
      )

      length_interval = [0, length]
      width_interval = [0, width]
      height_interval = [0, height]

      shell_group.entities.clear!
      shell_group.name = 'SP Karkas Frame'

      columns = layout_columns(shell_group.entities, axes, length_interval, width_interval, height_interval)
      beams = layout_beams(shell_group.entities, axes, length_interval, width_interval, height_interval)
      braces = layout_bracing(shell_group.entities, axes, length_interval, width_interval, height_interval)

      Metadata.apply(
        shell_group,
        Metadata.frame_tag(
          length: length,
          width: width,
          height: height,
          columns: columns.length,
          beams: beams.length,
          braces: braces.length
        )
      )

      shell_group
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

    unless file_loaded?(__FILE__)
      UI.menu('Plugins').add_item('SP Karkas Auto Framer') { activate }
      file_loaded(__FILE__)
    end
  end
end
