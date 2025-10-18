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

    def frame_tag(length:, width:, height:, studs:, headers:, top_plates:, bottom_plates:, corner_posts:)
      {
        'category' => 'structural_frame',
        'version' => '0.3.0',
        'length_mm' => length.to_mm,
        'width_mm' => width.to_mm,
        'height_mm' => height.to_mm,
        'stud_count' => studs,
        'header_count' => headers,
        'top_plate_count' => top_plates,
        'bottom_plate_count' => bottom_plates,
        'corner_post_count' => corner_posts
      }
    end
  end
end
