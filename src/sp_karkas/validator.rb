require_relative 'geometry_utils'

module SPKarkas
  module Validator
    MIN_SPAN = 0.3.m
    MIN_HEIGHT = 2.1.m
    MIN_OPENING_SPAN = 0.3.m
    MIN_OPENING_HEIGHT = 0.3.m

    ValidationResult = Struct.new(:valid?, :message, :prism_planes, :dimensions, keyword_init: true)

    class ValidationError < StandardError; end

    module_function

    def validate(selection)
      raise ValidationError, 'Не удалось определить выбранный объект.' if selection.nil?

      prism_planes = GeometryUtils.rectangular_prism?(selection.entities, selection.transformation)
      unless prism_planes
        return ValidationResult.new(
          valid?: false,
          message: 'Выбранный объект должен представлять прямоугольный параллелепипед без дополнительных элементов.'
        )
      end

      dimensions = compute_dimensions(selection.bounds)
      ensure_min_dimensions!(dimensions)
      ensure_openings_valid!(prism_planes)

      ValidationResult.new(valid?: true, message: nil, prism_planes: prism_planes, dimensions: dimensions)
    rescue ValidationError => error
      ValidationResult.new(valid?: false, message: error.message)
    end

    def compute_dimensions(bounds)
      {
        length: bounds.max.x - bounds.min.x,
        width: bounds.max.y - bounds.min.y,
        height: bounds.max.z - bounds.min.z
      }
    end

    def ensure_min_dimensions!(dimensions)
      if dimensions[:length] < MIN_SPAN || dimensions[:width] < MIN_SPAN
        raise ValidationError, format('Минимальный габарит в плане должен быть не менее %.0f мм.', MIN_SPAN.to_mm)
      end

      return unless dimensions[:height] < MIN_HEIGHT

      raise ValidationError, format('Высота объекта должна быть не менее %.0f мм.', MIN_HEIGHT.to_mm)
    end

    def ensure_openings_valid!(prism_planes)
      [:x, :y].each do |axis|
        planes = prism_planes[axis]
        next unless planes

        planes.each_value do |plane|
          validate_inner_loops(axis, plane)
        end
      end
    end

    def validate_inner_loops(axis, plane)
      return if plane.inner_loops.empty?

      primary_axis, secondary_axis = GeometryUtils::PLANE_AXES[axis]
      wall_bounds = plane.bounds
      raise ValidationError, 'Не удалось определить габариты плоскости стены.' if wall_bounds.nil?

      ranges = plane.inner_loops.map do |loop_points|
        validate_loop_rectangularity!(loop_points, axis, primary_axis, secondary_axis)

        primary_values = loop_points.map { |point| point.public_send(primary_axis) }
        secondary_values = loop_points.map { |point| point.public_send(secondary_axis) }
        primary_range = primary_values.minmax
        secondary_range = secondary_values.minmax

        ensure_within_bounds!(primary_range, wall_bounds[primary_axis])
        ensure_within_bounds!(secondary_range, wall_bounds[secondary_axis])
        ensure_opening_dimensions!(primary_range, secondary_range)

        { primary: primary_range, secondary: secondary_range }
      end

      ensure_no_overlap!(ranges)
    end

    def validate_loop_rectangularity!(loop_points, axis, primary_axis, secondary_axis)
      return if GeometryUtils.edges_axis_aligned?([loop_points], axis, primary_axis, secondary_axis)

      raise ValidationError, 'Все внутренние контуры должны быть прямоугольными и выровненными по глобальным осям.'
    end

    def ensure_within_bounds!(range, bounds)
      return if bounds &&
                range.first >= bounds.first - GeometryUtils::EPSILON &&
                range.last <= bounds.last + GeometryUtils::EPSILON

      raise ValidationError, 'Контур проема выходит за пределы допустимых размеров стены.'
    end

    def ensure_opening_dimensions!(primary_range, secondary_range)
      if (primary_range.last - primary_range.first) < MIN_OPENING_SPAN
        raise ValidationError, format('Ширина проема должна быть не менее %.0f мм.', MIN_OPENING_SPAN.to_mm)
      end

      return unless (secondary_range.last - secondary_range.first) < MIN_OPENING_HEIGHT

      raise ValidationError, format('Высота проема должна быть не менее %.0f мм.', MIN_OPENING_HEIGHT.to_mm)
    end

    def ensure_no_overlap!(ranges)
      ranges.combination(2) do |first, second|
        next unless overlap?(first[:primary], second[:primary]) && overlap?(first[:secondary], second[:secondary])

        raise ValidationError, 'Проемы на одной стене не должны перекрываться.'
      end
    end

    def overlap?(first, second)
      first.first < second.last - GeometryUtils::EPSILON && second.first < first.last - GeometryUtils::EPSILON
    end
  end
end
