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
  end
end
