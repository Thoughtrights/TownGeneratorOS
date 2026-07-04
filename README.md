# Medieval Fantasy City Generator
This is the source code of the [Medieval Fantasy City Generator](https://watabou.itch.io/medieval-fantasy-city-generator/) (also available [here](http://fantasycities.watabou.ru/?size=15&seed=682063530)). It 
lacks some of the latest features, namely waterbodies, options UI and some smaller ones. Maybe I'll update it later. 

You'll need [OpenFL](https://github.com/openfl/openfl) and [msignal](https://github.com/massiveinteractive/msignal) 
to run this code, both available through `haxelib`.



## Building
`sudo lime build html5`

## Example Query Arguments
`/?size=66&seed=7331619330&walls=1&markets=0&citadel=1&trans=1&menu=0&tooltips=0&parks=2&temples=1&palette=4&sketchy=1&roofs=1&farms=8&towers=4&river=1&coast=1`

## Query Arguments

| Param | Values | Description |
| --- | --- | --- |
| `size` | `6`-`70` | Number of patches/wards in the city. Roughly: Small Town 6, Large Town 10, Small City 15, Large City 24, Capital City 40+. |
| `seed` | any positive integer | PRNG seed. Omit for a random city. |
| `walls` | `0` / `1` | Whether the city has defensive walls. Any other value picks randomly. |
| `markets` | `0` / `1` | Whether the city has a central plaza/market. Any other value picks randomly. |
| `citadel` | `0` / `1` | Whether the city has a citadel. Any other value picks randomly. See below for placement behavior. |
| `parks` | `0`, `1`, `2`, ... | Exact number of parks to place in the city (not just a toggle). `0` removes them entirely. |
| `temples` | `0` / `1` | Whether the city has a main temple. `1` (default) guarantees one, placed as close to the plaza as possible; `0` removes it entirely. |
| `farms` | `0`, `1`, `2`, ... | Exact number of countryside patches to turn into farms (not just a fixed per-patch chance). `0` removes them entirely. Default `6`. See below for how they're drawn. |
| `palette` | `0`-`9` | Color palette. `0` (or omitted) is the current default look; `1`-`9` select one of nine earth-tone/architectural-diagram palettes (see below). |
| `sketchy` | `0`-`5` | Rough, hand-sketched edges on buildings, walls, and roads instead of perfectly straight lines. `0` (default) disables it; higher values make it progressively wavier and more displaced. Works with every palette. |
| `roofs` | `0` / `1` | Gable-roof lines on each building: a ridge line down its long axis, plus a few short rafters perpendicular to it on one side only. Works with every palette, and combines with `sketchy`. |
| `towers` | `0`-`4` | Wall tower shape. `0` (default) round; `1` square (flat face pointing outward); `2` hexagon (vertex pointing outward); `3` round with a few little spikes on the outward-facing side; `4` a random mix of the above per tower. |
| `river` | `0` / `1` | `1` runs a small river across the map, beside or through the city, with gradual bends and bridges where it meets the streets. Default `0`. See below. |
| `coast` | `0` / `1` | `1` puts the city on a coast: an open harbour front with piers reaching into the water, districts fronting the sea. Default `0`. `river=1&coast=1` makes an estuary. See below. |
| `trans` | `0` / `1` | Transparent background instead of the palette's paper color. |
| `menu` | `0` / `1` | Show/hide the city-size selection buttons. |
| `tooltips` | `0` / `1` | Show/hide ward tooltips. |

### Citadel placement

When `citadel=1`, the citadel is always enclosed by the main wall rather than merely touching it from outside. In large enough cities (`size` of 20 or more), it will sometimes appear as a fully interior keep — walled off on every side and not touching the outer wall at all — instead of the classic position attached to the city's rim. Smaller cities always use the classic rim-attached placement, since there isn't enough room for a clean interior keep.

### Farms

Farm patches get a faint tint over the whole plot plus a few furrow lines parallel to its long axis, so a field reads as a field at a glance — subtler than anything drawn inside the city itself, and independent of `sketchy`/`roofs`/palette choice. `farms` picks exactly how many countryside patches become farms (candidates need a reasonably compact shape, so the actual count is capped by how many suitable patches exist around the city).

### Water (`river`, `coast`)

Water is drawn as a solid, per-palette-harmonized colour (a slate blue on the default palette, muted teal/blue-grey on the earth-tone ones) so it reads clearly against the land. No buildings, farms, walls, streets, or towers are ever placed in the water.

- **`river=1`** lays a gently bending river, 4–10× the width of a road, across the map. It may run alongside the city or cut through it. Where it crosses the built-up area, bridges span it; a river running beside the city gets a single bridge at its nearest approach, one running through gets several.
- **`coast=1`** floods the seaward side of the map so a broad arc of districts fronts the water. The city wall opens along the waterfront (a quay) instead of walling off the sea, and a row of piers reaches out from the harbour.
- **`river=1&coast=1`** aims the river at the sea so it becomes an estuary, with the city sitting at the junction.

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
  - Citadels > 1
* Add district coloration
* Citadel
  - Shapes of citadel building are not great
