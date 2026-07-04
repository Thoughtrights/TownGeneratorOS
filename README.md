# Medieval Fantasy City Generator
This is the source code of the [Medieval Fantasy City Generator](https://watabou.itch.io/medieval-fantasy-city-generator/) (also available [here](http://fantasycities.watabou.ru/?size=15&seed=682063530)). It 
lacks some of the latest features, namely waterbodies, options UI and some smaller ones. Maybe I'll update it later. 

You'll need [OpenFL](https://github.com/openfl/openfl) and [msignal](https://github.com/massiveinteractive/msignal) 
to run this code, both available through `haxelib`.



## Building
`sudo lime build html5`

## Example Query Arguments
`/?size=66&seed=7331619330&walls=1&markets=0&citadel=1&trans=1&menu=0&tooltips=0&parks=2&palette=4`

## Query Arguments

| Param | Values | Description |
| --- | --- | --- |
| `size` | `6`-`70` | Number of patches/wards in the city. Roughly: Small Town 6, Large Town 10, Small City 15, Large City 24, Capital City 40+. |
| `seed` | any positive integer | PRNG seed. Omit for a random city. |
| `walls` | `0` / `1` | Whether the city has defensive walls. Any other value picks randomly. |
| `markets` | `0` / `1` | Whether the city has a central plaza/market. Any other value picks randomly. |
| `citadel` | `0` / `1` | Whether the city has a citadel. Any other value picks randomly. See below for placement behavior. |
| `parks` | `0`, `1`, `2`, ... | Exact number of parks to place in the city (not just a toggle). `0` removes them entirely. |
| `palette` | `0`-`9` | Color palette. `0` (or omitted) is the current default look; `1`-`9` select one of nine earth-tone/architectural-diagram palettes (see below). |
| `trans` | `0` / `1` | Transparent background instead of the palette's paper color. |
| `menu` | `0` / `1` | Show/hide the city-size selection buttons. |
| `tooltips` | `0` / `1` | Show/hide ward tooltips. |

### Citadel placement

When `citadel=1`, the citadel is always enclosed by the main wall rather than merely touching it from outside. In large enough cities (`size` of 20 or more), it will sometimes appear as a fully interior keep — walled off on every side and not touching the outer wall at all — instead of the classic position attached to the city's rim. Smaller cities always use the classic rim-attached placement, since there isn't enough room for a clean interior keep.

### Palettes

`palette=0` (default): the original look.

1. Terracotta — warm clay and sage
2. Arch Blueprint — cool architectural blue
3. Sepia Ink — hand-drawn sketch tones
4. Sage & Stone — muted landscape-architecture greens/greys
5. Desert Sand — warm ochre and sand
6. Charcoal & Copper — dark modern diagram with copper accents
7. Moss & Bark — deep forest greens and browns
8. Clay & Cream — soft adobe/Mediterranean tones
9. Graphite — monochrome minimalist diagram

## To Do

* Toggle on URL for the following:
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
* Citadel
  - Shapes of citadel building are not great
