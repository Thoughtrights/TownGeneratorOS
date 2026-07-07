# Medieval Fantasy City Generator
An extended fork of the source of the [Medieval Fantasy City Generator](https://watabou.itch.io/medieval-fantasy-city-generator/) (also available [here](http://fantasycities.watabou.ru/?size=15&seed=682063530)).
The original open-source release lacked waterbodies and an options UI; this fork adds rivers with bridges and water-gates, coasts with harbours and docks, estuaries, surrounding terrain (woods, dense forest, topographic mountains, swamp, cavern), colour palettes, per-district tints, hand-sketched rendering, configurable parks/farms/temples/towers, and full control of everything through URL query arguments — so a map can be embedded anywhere as a lightly dynamic, procedural image.

You'll need [OpenFL](https://github.com/openfl/openfl) and [msignal](https://github.com/massiveinteractive/msignal) 
to run this code, both available through `haxelib`.



## Building
`sudo lime build html5`

## Example Query Arguments
`/?size=66&seed=7331619330&walls=1&markets=0&citadel=1&trans=1&menu=0&tooltips=0&parks=2&temples=1&palette=4&sketchy=1&roofs=1&farms=8&towers=4&river=1&coast=1&terrain=1`

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
| `sketchy` | `0`-`5` | Rough, hand-sketched edges on buildings, walls, and roads instead of perfectly straight lines. `0` (default) disables it; higher values make it progressively wavier. The scale is finer than it used to be (today's `5` equals the old `2`), and sloppiness varies by district — slums are scrawled, patrician wards and the castle are drawn with care. |
| `roofs` | `0` / `1` | Gable-roof lines on each building: a ridge line down its long axis, plus a few short rafters perpendicular to it on one side only. Works with every palette, and combines with `sketchy`. |
| `towers` | `0`-`4` | Wall tower shape. `0` (default) round; `1` square (flat face pointing outward); `2` hexagon (vertex pointing outward); `3` round with a few little spikes on the outward-facing side; `4` a random mix of the above per tower. |
| `river` | `0` / `1` | `1` runs a gently bending river through the city, with the built-up area on both banks joined by short bridges where the streets cross. Default `0`. See below. |
| `coast` | `0` / `1` | `1` puts the city on a coast: an open harbour front with narrow I/L/T-shaped plank docks reaching into the water and districts right on the waterline. Default `0`. `river=1&coast=1` makes an estuary. See below. |
| `terrain` | `0`-`5` | Surrounding terrain. `0` (default) none; `1` woods — scattered fused groves with lone trees between; `2` mountains — relief-map style: a summed elevation field rendered as filled hypsometric bands rising green lowlands → tan → ochre → grey → near-white summits, merging additively, in three scale classes up to great massifs larger than the city whose flanks only partially enter the view. The land flattens smoothly around the city, and rises keep clear of the river so it flows through the valley between the ranges; `3` swamp (grass tufts and damp pools); `4` cavern — the whole city sits inside a giant irregular cave: lobed rock walls, stalactite teeth, rocky outcroppings and clustered rock pillars, all fused into one continuous rock mass with a single unbroken lip; `5` dense forest — deep contiguous woodland (several times the tree mass of `1`) pressing in around the city, parting for farms, roads, and water. |
| `maxpage` | pixels | Cap the page: the map canvas never exceeds this many CSS pixels on a side. `0` (default) fills the window. |
| `trans` | `0` / `1` | Transparent background instead of the palette's paper color. |
| `menu` | `0` / `1` | Show/hide the city-size selection buttons. |
| `tooltips` | `0` / `1` | Show/hide ward tooltips. |

### Citadel placement

When `citadel=1`, the citadel is always enclosed by the main wall rather than merely touching it from outside. In large enough cities (`size` of 20 or more), it will sometimes appear as a fully interior keep — walled off on every side and not touching the outer wall at all — instead of the classic position attached to the city's rim. Smaller cities always use the classic rim-attached placement, since there isn't enough room for a clean interior keep.

### Farms

Farm patches get a faint tint over the whole plot plus a few furrow lines parallel to its long axis, so a field reads as a field at a glance — subtler than anything drawn inside the city itself, and independent of `sketchy`/`roofs`/palette choice. `farms` picks exactly how many countryside patches become farms (candidates need a reasonably compact shape, so the actual count is capped by how many suitable patches exist around the city).

### Water (`river`, `coast`)

Water is drawn as a solid, per-palette-harmonized colour (a slate blue on the default palette, muted teal/blue-grey on the earth-tone ones) so it reads clearly against the land. It's a geometric overlay rather than removed map cells: the patch layout underneath is left intact, so walls stay complete and streets route normally. The water is drawn over open ground and farmland, and anything solid that meets it is handled cleanly — individual houses that straddle the bank are clipped away (so buildings hug the waterline instead of whole blocks being deleted), the wall opens where it crosses the water, and no building, wall, tower, road, or street is ever drawn over open water.

- **`river=1`** lays a gently bending river, 4–10× the width of a road, through the city, bisecting the built-up area with districts on both banks. Streets cross it on short **bridges** laid perpendicular to the flow (the shortest span) wherever a road genuinely crosses; the wall opens into a water-gate on each bank where the river passes through it.
- **`coast=1`** puts the seaward side of the map under water, with a gently wavy shoreline the land clips against exactly, so a broad arc of districts sits right on the waterline. The city wall opens along the waterfront (a quay) instead of walling off the sea, and narrow plank **docks** — straight fingers, right-angled Ls, and T-heads, with plank texture — reach out from the harbour into the sea. Where a wall meets the water it stops at the bank with a tower, on both banks.
- **`river=1&coast=1`** aims the river at the sea so it becomes an estuary: the river widens toward its mouth and merges seamlessly into the sea (no line between the two), with the city sitting at the junction.

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

### Districts

Each district type carries a slight identifying tint blended into its building fill — gold for merchants, plum for the patriciate, steel for the military, blue-grey for administration, drab for the slums — so neighbourhoods read differently at a glance without breaking the palette.

## To Do

* Consider a dedicated dockside/harbour ward type that sits on the coast
* Options UI
