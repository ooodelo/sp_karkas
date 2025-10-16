require 'sketchup.rb'
require 'extensions.rb'

module SPKarkas
  module AutoFramer
    EXTENSION_ID = 'sp_karkas.auto_framer'.freeze
    EXTENSION_NAME = 'SP Karkas Auto Framer'.freeze
    LOADER_PATH = File.join(File.dirname(__FILE__), 'src', 'sp_karkas', 'auto_framer.rb')

    unless defined?(@extension)
      @extension = SketchupExtension.new(EXTENSION_NAME, LOADER_PATH)
      @extension.description = 'Automatically frames selected wall groups with studs, headers, and metadata.'
      @extension.version = '0.1.0'
      @extension.creator = 'SP Karkas'
      Sketchup.register_extension(@extension, true)
    end
  end
end
