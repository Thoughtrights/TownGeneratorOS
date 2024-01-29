# Medieval Fantasy City Generator
This is the source code of the [Medieval Fantasy City Generator](https://watabou.itch.io/medieval-fantasy-city-generator/) (also available [here](http://fantasycities.watabou.ru/?size=15&seed=682063530)). It 
lacks some of the latest features, namely waterbodies, options UI and some smaller ones. Maybe I'll update it later. 

You'll need [OpenFL](https://github.com/openfl/openfl) and [msignal](https://github.com/massiveinteractive/msignal) 
to run this code, both available through `haxelib`.



## Building
`sudo lime build html5`

## Example Query Arguments
`/?size=66&seed=7331619330&walls=1&markets=0&citadel=1&trans=1&menu=0&tooltips=0`

## To Do

* Toggle on URL for the following:
  - Parks 0+
  - Temples 0+
  - Citadels > 1
  - Gates 1+
* Fix farms
* Make buildings nice
  - Slightly variable edges
  - No triangular buildings
* Add district coloration
* Add ocean & bays
* Add rivers
* Add configurable *fixed* color palettes
* Citadel
  - I like and don't like how it is attached to the wall.
  - Would be nicer if it was essentially a secondary inner wall?
  - Shapes of citadel building are not great
