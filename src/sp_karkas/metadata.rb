module SPKarkas
  module Metadata
    EXTENSION_NAMESPACE = 'SPKarkas::AutoFramer'.freeze

    module_function

    def apply(entity, metadata)
      metadata.each do |key, value|
        entity.set_attribute(EXTENSION_NAMESPACE, key, value)
      end
    end

    def wall_tag
      {
        'category' => 'wall',
        'version' => '0.1.0'
      }
    end

    def framing_member_tag(type, sequence)
      {
        'category' => 'framing_member',
        'member_type' => type,
        'sequence' => sequence
      }
    end

    def frame_tag(length:, width:, height:, columns:, beams:, braces:)
      {
        'category' => 'structural_frame',
        'version' => '0.2.0',
        'length_mm' => length.to_mm,
        'width_mm' => width.to_mm,
        'height_mm' => height.to_mm,
        'column_count' => columns,
        'beam_count' => beams,
        'brace_count' => braces
      }
    end
  end
end
