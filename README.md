# SP Karkas Auto Framer

SP Karkas Auto Framer is a SketchUp extension that detects simple wall groups and automatically adds framing elements such as studs, headers, and braces. The tool also tags each generated element with structured attributes that can be used by downstream workflows.

## Installation

1. Download or clone this repository.
2. Copy `sp_karkas.rb` along with the `src/` directory into your SketchUp plugins folder:
   ```
   ~/Library/Application Support/SketchUp 2023/SketchUp/Plugins
   ```
3. Restart SketchUp 2023 for macOS. The extension registers itself on startup.

## Usage

1. Create or import wall groups in your SketchUp model. Groups should be oriented upright and have a consistent thickness.
2. Select the wall groups you want to frame (or leave nothing selected to frame all detected walls).
3. Open the **Extensions → SP Karkas Auto Framer** menu command to generate studs, headers, braces, and metadata tags.

The extension applies default stud spacing and rough opening expansion values. Generated components remain standard groups so they can be further edited or replaced with custom components as needed.
