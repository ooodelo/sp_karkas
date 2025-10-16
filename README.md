# SP Karkas Auto Framer

SP Karkas Auto Framer is a SketchUp extension that формирует пространственный каркас здания на основе выделенного прямоугольного параллелепипеда. Инструмент заменяет исходный объем на систему стоек, ригелей и раскосов, а также присваивает структурированные атрибуты для дальнейших расчетов.

## Installation

1. Download or clone this repository.
2. Copy `sp_karkas.rb` along with the `src/` directory into your SketchUp plugins folder:
   ```
   ~/Library/Application Support/SketchUp 2023/SketchUp/Plugins
   ```
3. Restart SketchUp 2023 for macOS. The extension registers itself on startup.

## Usage

1. Постройте или импортируйте внешний контур здания в виде группы прямоугольного параллелепипеда.
2. Выделите только эту группу.
3. Запустите команду **Extensions → SP Karkas Auto Framer**.

Плагин проверяет корректность оболочки, очищает её содержимое, формирует нормативный шаг стоек, ригелей и раскосов и назначает атрибуты на собранный каркас.
