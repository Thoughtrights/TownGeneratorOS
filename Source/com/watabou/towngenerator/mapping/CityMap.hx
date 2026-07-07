package com.watabou.towngenerator.mapping;

import com.watabou.utils.Random;

import openfl.display.Shape;
import openfl.display.CapsStyle;
import openfl.display.JointStyle;
import openfl.display.Graphics;
import openfl.display.Sprite;
import openfl.geom.Point;

import com.watabou.utils.GraphicsExtender;

import com.watabou.geom.Polygon;
import com.watabou.geom.GeomUtils;

import com.watabou.towngenerator.wards.*;
import com.watabou.towngenerator.building.CurtainWall;
import com.watabou.towngenerator.building.Model;
import com.watabou.towngenerator.building.Patch;

using com.watabou.utils.ArrayExtender;
using com.watabou.utils.GraphicsExtender;
using com.watabou.utils.PointExtender;

class CityMap extends Sprite {

	public static var palette_type = 'ADVANCED';

	public static var palette = Palette.MOJEEB;
	public static var advanced_palette = AdvancedPalette.DEFAULT;

	// Roof hatching: a ridge line down each building's long axis plus a
	// few rafters perpendicular to it on one side, gable-roof style.
	public static var roofs:Bool = false;
	private static inline var ROOF_SPACING = 2.2;

	// Farm fields: a faint tint over the whole countryside patch plus a
	// few furrow lines, subtler than anything drawn inside the city.
	private static inline var FARM_FIELD_ALPHA = 0.1;
	private static inline var FARM_FURROW_ALPHA = 0.3;
	private static inline var FARM_FURROW_SPACING = 5.5;

	// Tower shape: 0 round (default), 1 square, 2 hexagon, 3 spiked,
	// 4 a random mix of the above per tower.
	public static var towerStyle:Int = 0;

	// Surrounding terrain: 0 none, 1 forest, 2 mountains, 3 swamp,
	// 4 cavern (the city sits in a giant cave).
	public static var terrain:Int = 0;

	// index 0 keeps the current MOJEEB/DEFAULT look; 1-9 select one of
	// the numbered earth-tone/architectural palette pairs.
	public static function applyPalette( index:Int ):Void {
		palette = Palette.fromIndex( index );
		advanced_palette = AdvancedPalette.fromIndex( index );
	}

	private var patches	: Array<PatchView>;

	private var brush	: Brush;
	private var brush_advanced	: BrushAdvanced;

	public function new( model:Model ) {
		super();

		brush = new Brush( palette );
		brush_advanced = new BrushAdvanced( advanced_palette );

		var model = Model.instance;
		var hasWater = model.seaShape != null || model.riverShape != null;

		patches = [];

		function renderPatch( patch:Patch ):Void {
			var patchView = new PatchView( patch );
			if (drawWard( patchView.graphics, patch ))
				addChild( patchView );
			patches.push( patchView );
		}

		// Surrounding terrain (forest / mountains / swamp) is the lowest
		// layer of all: farms, roads, water and buildings all draw over it,
		// so hillside blocks sit on the elevation colours and rivers and
		// seas cut smoothly through relief and groves.
		if (terrain >= 1 && terrain <= 3) {
			var terrainView = new Shape();
			drawTerrainScatter( terrainView.graphics, model );
			addChild( terrainView );
		}

		// Under the water: farmland and parks — open ground the water is
		// allowed to cut off. Then the water itself.
		if (hasWater) {
			for (patch in model.patches) {
				var c = Type.getClass( patch.ward );
				if (c == Farm || c == Park)
					renderPatch( patch );
			}

			var waterView = new Shape();
			drawWater( waterView.graphics, model );
			addChild( waterView );

			// Harbour docks reach from the shore out over the water; drawn under
			// the buildings so their landward ends read as attached to the town.
			if (model.docks != null && model.docks.length > 0) {
				var dockView = new Shape();
				drawDocks( dockView.graphics, model );
				addChild( dockView );
			}
		}

		for (road in model.roads) {
			var roadView = new Shape();
			drawRoad( roadView.graphics, road );
			addChild( roadView );
		}

		// Bridges span the water, drawn under the buildings so buildings on
		// the banks sit over the deck ends.
		if (model.bridges != null && model.bridges.length > 0) {
			var bridgeView = new Shape();
			for (bridge in model.bridges)
				drawBridge( bridgeView.graphics, bridge[0], bridge[1] );
			addChild( bridgeView );
		}

		// Over the water: the buildings, which must never overlap it. (With
		// no water, this pass draws everything, preserving the original look.)
		for (patch in model.patches) {
			if (hasWater) {
				var c = Type.getClass( patch.ward );
				if (c == Farm || c == Park)
					continue;
			}
			renderPatch( patch );
		}

		for (patch in patches)
			addChild( patch.hotArea );

		// The cavern swallows everything beyond its wall — drawn over the
		// countryside, under the city wall (which stands inside the cave).
		if (terrain == 4) {
			var caveView = new Shape();
			drawCavern( caveView.graphics, model );
			addChild( caveView );
		}

		var walls = new Shape();
		addChild( walls );

		if (model.wall != null)
			drawWall( walls.graphics, model.wall, false, model.center );

		if (model.citadel != null)
			drawWall( walls.graphics, cast( model.citadel.ward, Castle).wall, true, model.center );
	}

	// True if a building footprint touches the water, so it should be
	// dropped (a house straddling the bank) rather than drawn on top of it.
	private function buildingInWater( building:Polygon ):Bool {
		var m = Model.instance;
		if (m.seaShape == null && m.riverShape == null)
			return false;
		for (v in building)
			if (m.isWater( v ))
				return true;
		return false;
	}

	// Draws one patch's ward. Returns false for wards with nothing to draw.
	// Blend two colours; t=0 keeps a, t=1 gives b.
	private static function mix( a:Int, b:Int, t:Float ):Int {
		var ar = (a >> 16) & 0xFF, ag = (a >> 8) & 0xFF, ab = a & 0xFF;
		var br = (b >> 16) & 0xFF, bg = (b >> 8) & 0xFF, bb = b & 0xFF;
		return (Std.int( ar + (br - ar) * t ) << 16) |
		       (Std.int( ag + (bg - ag) * t ) << 8) |
		        Std.int( ab + (bb - ab) * t );
	}

	// How sloppily each district is sketched (multiplier on `sketchy`):
	// slums are scrawled, patrician wards and the castle are drawn with care.
	private function wardSketchScale( cls:Class<Ward> ):Float {
		return if (cls == Slum) 1.7
		else if (cls == GateWard) 1.3
		else if (cls == Farm) 1.2
		else if (cls == MerchantWard) 0.85
		else if (cls == MilitaryWard) 0.75
		else if (cls == AdministrationWard) 0.6
		else if (cls == Cathedral || cls == PatriciateWard) 0.5
		else if (cls == Castle) 0.4
		else 1.0;
	}

	// A slight identifying tint per district type, blended faintly into the
	// building fill so neighbourhoods read differently without breaking the
	// palette: gold for merchants, plum for the patriciate, steel for the
	// military, blue-grey for administration, drab for the slums.
	private function wardTint( cls:Class<Ward> ):Int {
		return if (cls == MerchantWard) 0xC9A227
		else if (cls == PatriciateWard) 0x7A4E7E
		else if (cls == MilitaryWard) 0x46586A
		else if (cls == AdministrationWard) 0x4E6E8E
		else if (cls == Slum) 0x59493A
		else if (cls == Cathedral) 0xB8B2D0
		else -1;
	}
	private static inline var TINT = 0.13;

	private function drawWard( g:Graphics, patch:Patch ):Bool {
		var patchDrawn = true;
		var cls = Type.getClass( patch.ward );

		// Buildings must never overlap the water: clip out any individual
		// house that straddles the bank (open ground — farms, parks — is left
		// whole, since the water simply draws over it).
		var geo = patch.ward.geometry;
		if (geo != null && cls != Farm && cls != Park && (Model.instance.seaShape != null || Model.instance.riverShape != null))
			geo = [for (b in geo) if (!buildingInWater( b )) b];

		// Sloppiness varies by district (only matters when sketchy > 0)
		GraphicsExtender.sketchScale = wardSketchScale( cls );

		if (palette_type == 'NORMAL') {
			switch (cls) {
				case Castle:
					drawBuilding( g, geo, palette.light, palette.dark, Brush.NORMAL_STROKE * 2 );
					drawRoofHatching( g, geo, palette.dark );
				case Cathedral:
					drawBuilding( g, geo, palette.light, palette.dark, Brush.NORMAL_STROKE );
					drawRoofHatching( g, geo, palette.dark );
				case Market, CraftsmenWard, MerchantWard, GateWard, Slum, AdministrationWard, MilitaryWard, PatriciateWard:
					brush.setColor( g, palette.light, palette.dark );
					for (building in geo)
					    g.drawPolygon( building );
					drawRoofHatching( g, geo, palette.dark );
				case Farm:
					drawFarmField( g, patch.shape, palette.medium, palette.dark );
					brush.setColor( g, palette.light, palette.dark );
					for (building in geo)
					    g.drawPolygon( building );
					drawRoofHatching( g, geo, palette.dark );
				case Park:
					brush.setColor( g, palette.medium );
					for (grove in geo)
						g.drawPolygon( grove );
				default:
					patchDrawn = false;
			}
		}
		else if (palette_type == 'ADVANCED') {
			switch (cls) {
				case Castle:
					drawBuilding( g, geo, advanced_palette.plot_medium, advanced_palette.building, BrushAdvanced.NORMAL_STROKE * 2 );
					drawRoofHatching( g, geo, advanced_palette.building );
				case Cathedral:
					drawBuilding( g, geo, mix( advanced_palette.plot_medium, wardTint( Cathedral ), TINT ), advanced_palette.building, BrushAdvanced.NORMAL_STROKE );
					drawRoofHatching( g, geo, advanced_palette.building );
				case Market, CraftsmenWard, MerchantWard, GateWard, Slum, AdministrationWard, MilitaryWard, PatriciateWard:
					var tint = wardTint( cls );
					var fillMed = tint == -1 ? advanced_palette.plot_medium : mix( advanced_palette.plot_medium, tint, TINT );
					var fillDark = tint == -1 ? advanced_palette.plot_dark : mix( advanced_palette.plot_dark, tint, TINT );
					for (building in geo) {
					    if (Random.bool(0.8)) {
						brush.setColor( g, fillMed, advanced_palette.building );
					    } else {
						brush.setColor( g, fillDark, advanced_palette.building );
					    }
					    g.drawPolygon( building );
					}
					drawRoofHatching( g, geo, advanced_palette.building );
				case Farm:
					drawFarmField( g, patch.shape, advanced_palette.grass, advanced_palette.building );
					brush.setColor( g, advanced_palette.plot_medium, advanced_palette.building );
					for (building in geo)
						g.drawPolygon( building );
					drawRoofHatching( g, geo, advanced_palette.building );
				case Park:
					brush.setColor( g, advanced_palette.grass );
					for (grove in geo)
						g.drawPolygon( grove );
				default:
					patchDrawn = false;
			}
		}

		GraphicsExtender.sketchScale = 1.0;
		return patchDrawn;
	}

	// Each dock is an open polyline skeleton (I, L, or the bar of a T).
	// Drawn as narrow planking: a dark outline stroke with a lighter deck
	// stroke over it, then faint cross-ticks for plank texture.
	private function drawDocks( g:Graphics, model:Model ):Void {
		var deck = palette_type == 'ADVANCED' ? advanced_palette.plot_dark : palette.medium;
		var line = palette_type == 'ADVANCED' ? advanced_palette.building : palette.dark;

		var w = Ward.MAIN_STREET * 0.9;		// much narrower than before

		// dark outline under...
		g.lineStyle( w + Brush.NORMAL_STROKE * 2, line, 1, false, null, CapsStyle.SQUARE, JointStyle.MITER );
		for (dock in model.docks) {
			g.moveToPoint( dock[0] );
			for (i in 1...dock.length)
				g.lineToPoint( dock[i] );
		}

		// ...deck over
		g.lineStyle( w, deck, 1, false, null, CapsStyle.SQUARE, JointStyle.MITER );
		for (dock in model.docks) {
			g.moveToPoint( dock[0] );
			for (i in 1...dock.length)
				g.lineToPoint( dock[i] );
		}

		// plank ticks across each span
		g.lineStyle( Brush.THIN_STROKE, line, 0.4, false, null, CapsStyle.NONE );
		for (dock in model.docks)
			for (i in 0...dock.length - 1) {
				var a = dock[i];
				var b = dock[i + 1];
				var d = Point.distance( a, b );
				if (d < 0.001) continue;
				var ux = (b.x - a.x) / d, uy = (b.y - a.y) / d;
				var nx = -uy * w * 0.5, ny = ux * w * 0.5;
				var step = 2.4;
				var s = step;
				while (s < d - 0.5) {
					var px = a.x + ux * s, py = a.y + uy * s;
					g.moveTo( px + nx, py + ny );
					g.lineTo( px - nx, py - ny );
					s += step;
				}
			}
	}

	private function drawBridge( g:Graphics, a:Point, b:Point ):Void {
		// A paper-coloured deck, no outline: it's drawn over the road so it
		// hides the road's crossing of the open water, and buildings drawn on
		// top of it hide the ends, so it reads as the road carrying across.
		// Wide enough to fully cover the road (incl. its darker underlay).
		g.lineStyle( (Ward.MAIN_STREET + Brush.NORMAL_STROKE) * 1.6, palette.paper, 1, false, null, CapsStyle.SQUARE );
		g.moveTo( a.x, a.y );
		g.lineTo( b.x, b.y );
	}

	private function drawWater( g:Graphics, model:Model ):Void {
		// Bank/shore outlines first...
		g.lineStyle( Brush.THICK_STROKE * 0.65, advanced_palette.water_dark, 0.9 );
		if (model.seaShape != null)
			g.drawPolygon( model.seaShape );
		if (model.riverShape != null)
			g.drawPolygon( model.riverShape );

		// ...then the fills on top of them. Each fill covers the water-facing
		// stretches of the outlines, leaving only the land-facing shoreline
		// visible — so where the river runs into the sea the outlines vanish
		// and the two bodies read as one merged surface. Sea and river are
		// filled separately so their overlap doesn't even-odd cancel.
		g.lineStyle( 0, 0, 0 );
		if (model.seaShape != null) {
			g.beginFill( advanced_palette.water );
			g.drawPolygon( model.seaShape );
			g.endFill();
		}
		if (model.riverShape != null) {
			g.beginFill( advanced_palette.water );
			g.drawPolygon( model.riverShape );
			g.endFill();
		}
	}

	private function drawRoad( g:Graphics, road:Street ):Void {
		// Skip any stretch that runs out over water — roads never show crossing
		// open water. Valid (near-perpendicular) river crossings are carried by
		// a bridge deck; oblique ones just stop at the bank.
		var m = Model.instance;
		var clip = m.seaShape != null || m.riverShape != null;

		function strokePolyline():Void {
			var pen = false;
			for (i in 0...road.length - 1) {
				var mid = new Point( (road[i].x + road[i + 1].x) / 2, (road[i].y + road[i + 1].y) / 2 );
				if (clip && m.isWater( mid )) { pen = false; continue; }
				if (!pen) { g.moveToPoint( road[i] ); pen = true; }
				g.lineToPoint( road[i + 1] );
			}
		}

		g.lineStyle( Ward.MAIN_STREET + Brush.NORMAL_STROKE, palette.medium, false, null, CapsStyle.NONE );
		strokePolyline();

		g.lineStyle( Ward.MAIN_STREET - Brush.NORMAL_STROKE, palette.paper );
		strokePolyline();
	}

	// March from a land point toward a water point and return the last spot
	// still on land — where the wall should stop and its bank tower stand.
	private function waterlineToward( land:Point, water:Point ):Point {
		var m = Model.instance;
		var d = Point.distance( land, water );
		var n = Std.int( Math.max( 8, d / 1.5 ) );
		var last = land;
		for (k in 1...n + 1) {
			var p = new Point( land.x + (water.x - land.x) * k / n, land.y + (water.y - land.y) * k / n );
			if (m.isWater( p )) break;
			last = p;
		}
		return last;
	}

	private function drawWall( g:Graphics, wall:CurtainWall, large:Bool, center:Point ):Void {
		g.lineStyle( Brush.THICK_STROKE, palette.dark );

		var m = Model.instance;
		var hasWater = m.seaShape != null || m.riverShape != null;
		var towerR = Brush.THICK_STROKE * (large ? 1.5 : 1);

		// Ends of wall stubs clipped at the waterline, each of which gets a
		// bank tower so both banks of a river gap read finished.
		var bankTowers:Array<Point> = [];

		// Draw only the enabled segments, so stretches opened for a harbour
		// quay or a river water-gate leave a gap instead of a solid wall.
		// A segment whose far vertex stands in the water is clipped at the
		// waterline instead of dipping in.
		var shape = wall.shape;
		var len = shape.length;
		for (i in 0...len)
			if (wall.segments[i]) {
				var a = shape[i];
				var b = shape[(i + 1) % len];

				if (hasWater) {
					var aw = m.isWater( a );
					var bw = m.isWater( b );
					if (aw && bw) continue;			// entirely in water: nothing to draw
					if (bw) {
						b = waterlineToward( a, b );
						bankTowers.push( b );
					} else if (aw) {
						a = waterlineToward( b, a );
						bankTowers.push( a );
					}
				}

				g.moveToPoint( a );
				g.lineToPoint( b );
			}

		// Skip gate and tower markings that fall in water — those stretches
		// are open water-gates / quay, not built defences.
		for (gate in wall.gates)
			if (!(hasWater && m.isWater( gate )))
				drawGate( g, wall.shape, gate );

		for (t in wall.towers)
			if (!(hasWater && m.isWater( t )))
				drawTower( g, t, towerR, center );

		for (t in bankTowers)
			drawTower( g, t, towerR, center );
	}

	private function outwardDir( p:Point, center:Point ):Point {
		var dx = p.x - center.x;
		var dy = p.y - center.y;
		var len = Math.sqrt( dx * dx + dy * dy );
		return len < 0.001 ? new Point( 1, 0 ) : new Point( dx / len, dy / len );
	}

	private function drawTower( g:Graphics, p:Point, r:Float, center:Point ) {
		var style = towerStyle == 4 ? Random.int( 0, 4 ) : towerStyle;

		brush.noStroke( g );
		g.beginFill( palette.dark );

		switch (style) {
			case 1:
				drawSquareTower( g, p, r, center );
			case 2:
				drawHexTower( g, p, r, center );
			case 3:
				drawSpikedTower( g, p, r, center );
			default:
				g.drawCircle( p.x, p.y, r );
		}

		g.endFill();
	}

	// A square tower with one flat face pointing directly outward, like
	// a small bastion, rather than the classic round turret.
	private function drawSquareTower( g:Graphics, p:Point, r:Float, center:Point ):Void {
		var e1 = outwardDir( p, center );
		var e2 = new Point( -e1.y, e1.x );
		g.drawPolygon( [
			new Point( p.x + e1.x * r + e2.x * r, p.y + e1.y * r + e2.y * r ),
			new Point( p.x - e1.x * r + e2.x * r, p.y - e1.y * r + e2.y * r ),
			new Point( p.x - e1.x * r - e2.x * r, p.y - e1.y * r - e2.y * r ),
			new Point( p.x + e1.x * r - e2.x * r, p.y + e1.y * r - e2.y * r )
		] );
	}

	// A hexagonal tower with a vertex pointing directly outward.
	private function drawHexTower( g:Graphics, p:Point, r:Float, center:Point ):Void {
		var e1 = outwardDir( p, center );
		var hex = Polygon.regular( 6, r );
		hex.rotate( Math.atan2( e1.y, e1.x ) );
		hex.offset( p );
		g.drawPolygon( hex );
	}

	// A round tower with a few little spikes on the side facing away
	// from the city, like small defensive spurs.
	private function drawSpikedTower( g:Graphics, p:Point, r:Float, center:Point ):Void {
		g.drawCircle( p.x, p.y, r );

		var e1 = outwardDir( p, center );
		var baseAngle = Math.atan2( e1.y, e1.x );
		var spikeLen = r * 0.9;
		var spikeHalfWidth = r * 0.35;

		for (i in -1...2) {
			var a = baseAngle + i * 0.5;
			var dx = Math.cos( a );
			var dy = Math.sin( a );
			var nx = -dy;
			var ny = dx;

			var baseX = p.x + dx * r;
			var baseY = p.y + dy * r;

			g.drawPolygon( [
				new Point( p.x + dx * (r + spikeLen), p.y + dy * (r + spikeLen) ),
				new Point( baseX + nx * spikeHalfWidth, baseY + ny * spikeHalfWidth ),
				new Point( baseX - nx * spikeHalfWidth, baseY - ny * spikeHalfWidth )
			] );
		}
	}

	private function drawGate( g:Graphics, wall:Polygon, gate:Point ) {
		g.lineStyle( Brush.THICK_STROKE * 2, palette.dark, false, null, CapsStyle.NONE );

		var dir = wall.next( gate ).subtract( wall.prev( gate ) );
		dir.normalize( Brush.THICK_STROKE * 1.5 );
		g.moveToPoint( gate.subtract( dir ) );
		g.lineToPoint( gate.add( dir ) );
	}

	private function drawBuilding( g:Graphics, blocks:Array<Polygon>, fill:Int, line:Int, thickness:Float ):Void {
		brush.setStroke( g, line, thickness * 2 );
		for (block in blocks) {
			g.drawPolygon( block );
		}

		brush.noStroke( g );
		brush.setFill( g, fill );
		for (block in blocks) {
			g.drawPolygon( block );
		}
	}

	// A gable roof, drawn schematically: a ridge line down the building's
	// long axis (the peak), plus a few short rafters perpendicular to it
	// on one side only (the other slope is left plain).
	private function drawRoofHatching( g:Graphics, blocks:Array<Polygon>, color:Int ):Void {
		if (!roofs)
			return;

		for (block in blocks)
			if (block.length >= 3)
				drawRoof( g, block, color );
	}

	// Finds the direction of a polygon's longest edge, as a unit vector.
	private function longestEdgeUnitDir( poly:Polygon ):Point {
		var dir:Point = null;
		var bestLen = -1.0;
		poly.forEdge( function( v0, v1 ) {
			var len = Point.distance( v0, v1 );
			if (len > bestLen) {
				bestLen = len;
				dir = v1.subtract( v0 );
			}
		} );

		if (dir == null)
			return null;
		var len = Math.sqrt( dir.x * dir.x + dir.y * dir.y );
		if (len < 0.001)
			return null;
		return new Point( dir.x / len, dir.y / len );
	}

	// A faint tint over the whole countryside patch plus a few furrows
	// parallel to its long axis, so a farm reads as a field at a glance
	// without competing visually with the city itself.
	private function drawFarmField( g:Graphics, shape:Polygon, fillColor:Int, lineColor:Int ):Void {
		g.lineStyle( 0, 0, 0 );
		g.beginFill( fillColor, FARM_FIELD_ALPHA );
		g.drawPolygon( shape );
		g.endFill();

		var u = longestEdgeUnitDir( shape );
		if (u == null)
			return;
		var ux = u.x, uy = u.y;
		var nx = -uy, ny = ux;

		var minB = Math.POSITIVE_INFINITY;
		var maxB = Math.NEGATIVE_INFINITY;
		for (v in shape) {
			var b = v.x * nx + v.y * ny;
			if (b < minB) minB = b;
			if (b > maxB) maxB = b;
		}

		g.lineStyle( Brush.THIN_STROKE, lineColor, FARM_FURROW_ALPHA );
		var furrow = minB + FARM_FURROW_SPACING / 2;
		while (furrow < maxB) {
			for (seg in clipLine( shape, nx * furrow, ny * furrow, ux, uy )) {
				g.moveToPoint( seg.p0 );
				g.lineToPoint( seg.p1 );
			}
			furrow += FARM_FURROW_SPACING;
		}
	}

	private function drawRoof( g:Graphics, block:Polygon, color:Int ):Void {
		var u = longestEdgeUnitDir( block );
		if (u == null)
			return;
		var ux = u.x, uy = u.y;
		// Perpendicular to the ridge, i.e. across the building's width
		var nx = -uy;
		var ny = ux;

		var minA = Math.POSITIVE_INFINITY, maxA = Math.NEGATIVE_INFINITY; // along the ridge
		var minB = Math.POSITIVE_INFINITY, maxB = Math.NEGATIVE_INFINITY; // across the ridge
		for (v in block) {
			var a = v.x * ux + v.y * uy;
			var b = v.x * nx + v.y * ny;
			if (a < minA) minA = a;
			if (a > maxA) maxA = a;
			if (b < minB) minB = b;
			if (b > maxB) maxB = b;
		}

		// Ridge line: splits the building's width in half along its length
		var ridge = (minB + maxB) / 2;
		g.lineStyle( Brush.THIN_STROKE * 1.5, color, 0.55 );
		for (seg in clipLine( block, nx * ridge, ny * ridge, ux, uy )) {
			g.moveToPoint( seg.p0 );
			g.lineToPoint( seg.p1 );
		}

		// Rafters: short lines from the ridge out to the eave, only on
		// one (randomly chosen) side of the roof.
		var farEdge = Random.bool() ? maxB : minB;
		var lo = Math.min( ridge, farEdge );
		var hi = Math.max( ridge, farEdge );

		g.lineStyle( Brush.THIN_STROKE, color, 0.4 );
		var offset = minA + ROOF_SPACING / 2;
		while (offset < maxA) {
			for (seg in clipLine( block, ux * offset, uy * offset, nx, ny )) {
				var segLo = Math.max( Math.min( seg.t0, seg.t1 ), lo );
				var segHi = Math.min( Math.max( seg.t0, seg.t1 ), hi );
				if (segLo < segHi) {
					var px = ux * offset;
					var py = uy * offset;
					g.moveToPoint( new Point( px + nx * segLo, py + ny * segLo ) );
					g.lineToPoint( new Point( px + nx * segHi, py + ny * segHi ) );
				}
			}
			offset += ROOF_SPACING;
		}
	}

	// Intersects an infinite line (a point plus a direction) with the
	// polygon and pairs up the crossings (even-odd rule) into the
	// segments that lie inside it. Also returns each segment's raw
	// parameters along that direction, for further clipping.
	private function clipLine( block:Polygon, px:Float, py:Float, dx:Float, dy:Float ):Array<{p0:Point, p1:Point, t0:Float, t1:Float}> {
		var hits = [];
		block.forEdge( function( v0, v1 ) {
			var edx = v1.x - v0.x;
			var edy = v1.y - v0.y;
			var t = GeomUtils.intersectLines( px, py, dx, dy, v0.x, v0.y, edx, edy );
			if (t != null && t.y >= 0 && t.y <= 1)
				hits.push( t.x );
		} );

		hits.sort( function( a, b ) return a > b ? 1 : (a < b ? -1 : 0) );

		var segments = [];
		var i = 0;
		while (i + 1 < hits.length) {
			segments.push( {
				p0: new Point( px + dx * hits[i], py + dy * hits[i] ),
				p1: new Point( px + dx * hits[i + 1], py + dy * hits[i + 1] ),
				t0: hits[i],
				t1: hits[i + 1]
			} );
			i += 2;
		}
		return segments;
	}

	// ------------------------------------------------------------------
	// Surrounding terrain (the `terrain` URL param)

	private static function pointInPoly( p:Point, poly:Polygon ):Bool {
		var inside = false;
		var n = poly.length;
		var j = n - 1;
		for (i in 0...n) {
			var a = poly[i];
			var b = poly[j];
			if ((a.y > p.y) != (b.y > p.y) &&
			    p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x)
				inside = !inside;
			j = i;
		}
		return inside;
	}

	// Cached built-up patch shapes with bounding boxes, so the tens of
	// thousands of terrain ground checks stay cheap.
	private var tShapes:Array<Polygon>;
	private var tBB:Array<Float>;

	// A spot is free for terrain if it's on dry ground, outside every
	// built-up patch, and not on a road.
	private function terrainSpotFree( p:Point, model:Model ):Bool {
		if ((model.seaShape != null || model.riverShape != null) && model.isWater( p ))
			return false;

		if (tShapes == null) {
			tShapes = [];
			tBB = [];
			for (patch in model.patches)
				if (patch.ward != null && patch.ward.geometry != null && patch.ward.geometry.length > 0) {
					tShapes.push( patch.shape );
					var x0 = Math.POSITIVE_INFINITY, y0 = Math.POSITIVE_INFINITY;
					var x1 = Math.NEGATIVE_INFINITY, y1 = Math.NEGATIVE_INFINITY;
					for (v in patch.shape) {
						if (v.x < x0) x0 = v.x; if (v.x > x1) x1 = v.x;
						if (v.y < y0) y0 = v.y; if (v.y > y1) y1 = v.y;
					}
					tBB.push( x0 ); tBB.push( y0 ); tBB.push( x1 ); tBB.push( y1 );
				}
		}

		for (si in 0...tShapes.length) {
			var b = si * 4;
			if (p.x < tBB[b] || p.y < tBB[b + 1] || p.x > tBB[b + 2] || p.y > tBB[b + 3])
				continue;
			if (pointInPoly( p, tShapes[si] ))
				return false;
		}

		if (model.arteries != null)
			for (a in model.arteries)
				for (i in 0...a.length - 1) {
					var ax = a[i].x, ay = a[i].y;
					var dx = a[i + 1].x - ax, dy = a[i + 1].y - ay;
					var l2 = dx * dx + dy * dy;
					if (l2 < 1e-9) continue;
					var t = ((p.x - ax) * dx + (p.y - ay) * dy) / l2;
					t = t < 0 ? 0 : (t > 1 ? 1 : t);
					var ddx = p.x - (ax + dx * t), ddy = p.y - (ay + dy * t);
					if (ddx * ddx + ddy * ddy < 36) return false;
				}

		return true;
	}

	// Like terrainSpotFree, but requires a whole disc of radius r to be
	// clear, so a tree canopy can't poke under a neighbouring building.
	private function terrainClear( p:Point, r:Float, model:Model ):Bool {
		if (!terrainSpotFree( p, model )) return false;
		for (q in 0...4) {
			var a = q * Math.PI / 2;
			if (!terrainSpotFree( new Point( p.x + Math.cos( a ) * r, p.y + Math.sin( a ) * r ), model ))
				return false;
		}
		return true;
	}

	// A random free point in the countryside band around the city, or null.
	private function freeSpot( model:Model, cr:Float, c:Point, rMin:Float, rMax:Float ):Point {
		for (attempt in 0...40) {
			var ang = Random.float() * Math.PI * 2;
			var rad = cr * (rMin + Random.float() * (rMax - rMin));
			var p = new Point( c.x + Math.cos( ang ) * rad, c.y + Math.sin( ang ) * rad );
			if (terrainSpotFree( p, model ))
				return p;
		}
		return null;
	}

	// Scattered forest / mountains / swamp in a ring around the city.
	private function drawTerrainScatter( g:Graphics, model:Model ):Void {
		var cr = model.cityRadius;
		var c = model.center;

		switch (terrain) {
			case 1: // forest: fused organic groves, map-style
				var canopy = mix( advanced_palette.grass, 0x1E3320, 0.28 );
				var lineC = mix( canopy, palette.dark, 0.55 );
				var deep = mix( canopy, 0x14251A, 0.4 );

				// Groves: each is a clump of overlapping canopy blobs drawn
				// in two passes — every blob slightly enlarged in the outline
				// colour first, then the canopy fill over it — so the circles
				// fuse into one woodland mass with a single bumpy edge.
				var groves = 16 + Random.int( 0, 8 );
				for (gi in 0...groves) {
					var gc = freeSpot( model, cr, c, 0.55, 1.8 );
					if (gc == null) continue;

					var R = cr * (0.09 + Random.float() * 0.15);
					var blobs:Array<{x:Float, y:Float, r:Float}> = [];
					var m = 10 + Random.int( 0, 14 );
					for (bi in 0...m) {
						var a = Random.float() * Math.PI * 2;
						var d = Math.sqrt( Random.float() ) * R * 0.75;
						var p = new Point( gc.x + Math.cos( a ) * d, gc.y + Math.sin( a ) * d * 0.8 );
						var rr = R * (0.28 + Random.float() * 0.22);
						if (!terrainClear( p, rr * 0.9, model )) continue;
						blobs.push( {x: p.x, y: p.y, r: rr} );
					}
					if (blobs.length < 4) continue;

					// One fill per circle: overlapping circles in a single fill
					// cancel to rings under the even-odd rule, so each blob is
					// its own fill and the opaque overdraw unions them solidly.
					g.lineStyle( 0, 0, 0 );
					for (b in blobs) {
						g.beginFill( lineC );
						g.drawCircle( b.x, b.y, b.r + 0.9 );
						g.endFill();
					}
					for (b in blobs) {
						g.beginFill( canopy );
						g.drawCircle( b.x, b.y, b.r );
						g.endFill();
					}

					// interior texture: darker canopy clumps
					for (b in blobs)
						if (Random.bool( 0.45 )) {
							g.beginFill( deep, 0.35 );
							g.drawCircle( b.x + (Random.float() - 0.5) * b.r * 0.6, b.y + (Random.float() - 0.5) * b.r * 0.6, b.r * 0.4 );
							g.endFill();
						}
				}

				// ...and a few lone trees between the groves
				for (k in 0...30) {
					var p = freeSpot( model, cr, c, 0.55, 2.0 );
					if (p == null) continue;
					var r = 1.6 + Random.float() * 1.6;
					if (!terrainClear( p, r + 0.7, model )) continue;
					g.lineStyle( 0, 0, 0 );
					g.beginFill( lineC );
					g.drawCircle( p.x, p.y, r + 0.7 );
					g.endFill();
					g.beginFill( canopy );
					g.drawCircle( p.x, p.y, r );
					g.endFill();
				}

			case 2: // mountains: additive topographic contours (level-sets)
				drawTopoMountains( g, model, cr, c );

			case 3: // swamp: grass tufts over damp speckles
				var tuft = mix( advanced_palette.grass, 0x33441F, 0.45 );
				var damp = advanced_palette.water;
				var spots:Array<Point> = [];
				for (k in 0...450) {
					var ang = Random.float() * Math.PI * 2;
					var rad = cr * (0.55 + Random.float() * 1.5);
					var p = new Point( c.x + Math.cos( ang ) * rad, c.y + Math.sin( ang ) * rad );
					if (terrainSpotFree( p, model ))
						spots.push( p );
				}
				for (p in spots) {
					if (Random.bool( 0.5 )) {
						g.lineStyle( 0, 0, 0 );
						g.beginFill( damp, 0.28 );
						g.drawEllipse( p.x - 3, p.y - 1.1, 6, 2.2 );
						g.endFill();
					}
					g.lineStyle( Brush.THIN_STROKE, tuft, 0.95 );
					var blades = 3 + Random.int( 0, 3 );
					for (b in 0...blades) {
						var bx = p.x + (b - blades / 2) * 0.8;
						var lean = (Random.float() - 0.5) * 1.6;
						var hh = 1.6 + Random.float() * 1.8;
						g.moveTo( bx, p.y );
						g.lineTo( bx + lean, p.y - hh );
					}
				}
		}
	}

	// Mountains as a real elevation model, shaded like a relief map: a
	// few bumps of very different scales are summed into one heightfield,
	// and each elevation band is FILLED bottom-up with hypsometric tints
	// (green lowlands, tan and ochre slopes, grey and near-white summits),
	// traced with filled marching squares. Because every band is a level
	// of the same summed field, neighbouring rises merge additively and
	// bands can never overlap. Small bumps only ever reach the green
	// bands (hilly mounds); the great massifs — larger than the city and
	// anchored far out so only their flanks enter the view — climb the
	// whole ramp to the pale summits.
	private function drawTopoMountains( g:Graphics, model:Model, cr:Float, c:Point ):Void {

		// --- the bumps, in three scale classes ---
		var bumps:Array<{x:Float, y:Float, a:Float, b:Float, ct:Float, st:Float, h:Float, ph:Float}> = [];
		function addBump( band0:Float, band1:Float, r0:Float, r1:Float, h0:Float ):Void {
			var mc = freeSpot( model, cr, c, band0, band1 );
			if (mc == null) return;
			var theta = Random.float() * Math.PI;
			var a = cr * (r0 + Random.float() * (r1 - r0));
			bumps.push( {
				x: mc.x, y: mc.y,
				a: a, b: a * (0.5 + Random.float() * 0.35),
				ct: Math.cos( theta ), st: Math.sin( theta ),
				h: h0 * (0.8 + Random.float() * 0.4),
				ph: Random.float() * Math.PI * 2
			} );
		}

		// great massifs: bigger than the city, mostly beyond the frame
		var big = 2 + Random.int( 0, 2 );
		for (i in 0...big) addBump( 1.7, 2.7, 1.2, 2.6, 1.15 );
		// mid-size mountains
		var mid = 3 + Random.int( 0, 2 );
		for (i in 0...mid) addBump( 1.15, 2.1, 0.4, 0.8, 0.55 );
		// low hills: green mounds only
		var small = 4 + Random.int( 0, 3 );
		for (i in 0...small) addBump( 0.7, 1.9, 0.15, 0.3, 0.3 );
		if (bumps.length == 0) return;

		function field( px:Float, py:Float ):Float {
			var f = 0.0;
			for (bp in bumps) {
				var dx = px - bp.x, dy = py - bp.y;
				var u = dx * bp.ct + dy * bp.st;
				var v = -dx * bp.st + dy * bp.ct;
				var ang = Math.atan2( v, u );
				var wob = 1 + 0.13 * Math.sin( 3 * ang + bp.ph ) + 0.07 * Math.sin( 5 * ang - bp.ph );
				var r2 = (u * u) / (bp.a * bp.a) + (v * v) / (bp.b * bp.b);
				f += bp.h * Math.exp( -r2 * 2.2 / wob );
			}

			// The land flattens smoothly into the plain the city stands on:
			// a radial smoothstep fades every rise to zero toward the centre,
			// so contours curve gently around the settlement instead of being
			// chopped off cell-by-cell at its edge.
			var ddx = px - c.x, ddy = py - c.y;
			var rr = Math.sqrt( ddx * ddx + ddy * ddy ) / cr;
			var t = (rr - 0.8) / 0.4;
			t = t < 0 ? 0 : (t > 1 ? 1 : t);
			return f * t * t * (3 - 2 * t);
		}

		// --- the grid, clipped to a window around the view ---
		var win = cr * 3.3;
		var minX = Math.POSITIVE_INFINITY, minY = Math.POSITIVE_INFINITY;
		var maxX = Math.NEGATIVE_INFINITY, maxY = Math.NEGATIVE_INFINITY;
		for (bp in bumps) {
			minX = Math.min( minX, bp.x - bp.a * 1.6 ); maxX = Math.max( maxX, bp.x + bp.a * 1.6 );
			minY = Math.min( minY, bp.y - bp.a * 1.6 ); maxY = Math.max( maxY, bp.y + bp.a * 1.6 );
		}
		minX = Math.max( minX, c.x - win ); maxX = Math.min( maxX, c.x + win );
		minY = Math.max( minY, c.y - win ); maxY = Math.min( maxY, c.y + win );
		if (minX >= maxX || minY >= maxY) return;

		var cell = cr / 30;
		var nx = Std.int( Math.ceil( (maxX - minX) / cell ) ) + 1;
		var ny = Std.int( Math.ceil( (maxY - minY) / cell ) ) + 1;
		if (nx < 2 || ny < 2) return;

		var F = new Array<Float>();
		for (j in 0...ny)
			for (i in 0...nx)
				F.push( field( minX + i * cell, minY + j * cell ) );

		// For the relief fills only the city proper (the wall/border
		// circumference, plus the citadel) masks cells. Buildings, farms
		// and roads all draw over the terrain layer — hillside blocks sit
		// ON the elevation colours — and the water is drawn above the
		// relief, so shorelines stay smooth and mountains simply run down
		// into the sea or part for a river.
		// --- hypsometric tints, low to high, harmonized with the palette ---
		var levels = [0.13, 0.25, 0.37, 0.49, 0.61, 0.73, 0.85, 0.94];
		var ramp = [
			mix( 0x8FB07E, palette.paper, 0.3 ),
			mix( 0xB4C48D, palette.paper, 0.22 ),
			mix( 0xD6CD9C, palette.paper, 0.15 ),
			mix( 0xE0C285, palette.paper, 0.1 ),
			0xD8A96F,
			0xC0997A,
			0xB1ABA5,
			0xECEAE6
		];
		var lineC = mix( palette.dark, palette.medium, 0.35 );

		// One filled pass per band, painted bottom-up so each higher band
		// sits on the one below. Interior runs of fully-covered cells merge
		// into single rectangles; boundary cells contribute the exact
		// clipped polygon, so band edges are smooth.
		for (li in 0...levels.length) {
			var L = levels[li];
			g.lineStyle( 0, 0, 0 );
			g.beginFill( ramp[li] );

			for (j in 0...ny - 1) {
				var y0 = minY + j * cell;
				var y1 = y0 + cell;
				var runStart = -1;

				inline function flushRun( endI:Int ):Void {
					if (runStart != -1) {
						g.drawRect( minX + runStart * cell, y0, (endI - runStart) * cell, cell );
						runStart = -1;
					}
				}

				for (i in 0...nx - 1) {
					var f00 = F[j * nx + i],       f10 = F[j * nx + i + 1];
					var f01 = F[(j + 1) * nx + i], f11 = F[(j + 1) * nx + i + 1];
					var idx = (f00 > L ? 1 : 0) | (f10 > L ? 2 : 0) | (f11 > L ? 4 : 0) | (f01 > L ? 8 : 0);

					if (idx == 0) { flushRun( i ); continue; }
					if (idx == 15) { if (runStart == -1) runStart = i; continue; }
					flushRun( i );

					var x0 = minX + i * cell;
					var x1 = x0 + cell;

					inline function lerpT( fa:Float, fb:Float ):Float
						return fa == fb ? 0.5 : (L - fa) / (fb - fa);
					var top    = new Point( x0 + lerpT( f00, f10 ) * cell, y0 );
					var bottom = new Point( x0 + lerpT( f01, f11 ) * cell, y1 );
					var left   = new Point( x0, y0 + lerpT( f00, f01 ) * cell );
					var right  = new Point( x1, y0 + lerpT( f10, f11 ) * cell );
					var TL = new Point( x0, y0 ), TR = new Point( x1, y0 );
					var BR = new Point( x1, y1 ), BL = new Point( x0, y1 );

					inline function poly( pts:Array<Point> ):Void {
						g.moveTo( pts[0].x, pts[0].y );
						for (q in 1...pts.length)
							g.lineTo( pts[q].x, pts[q].y );
						g.lineTo( pts[0].x, pts[0].y );
					}

					var centerAbove = (f00 + f10 + f01 + f11) / 4 > L;
					switch (idx) {
						case 1:  poly( [TL, top, left] );
						case 2:  poly( [top, TR, right] );
						case 3:  poly( [TL, TR, right, left] );
						case 4:  poly( [right, BR, bottom] );
						case 5:
							if (centerAbove) poly( [TL, top, right, BR, bottom, left] );
							else { poly( [TL, top, left] ); poly( [right, BR, bottom] ); }
						case 6:  poly( [top, TR, BR, bottom] );
						case 7:  poly( [TL, TR, BR, bottom, left] );
						case 8:  poly( [left, bottom, BL] );
						case 9:  poly( [TL, top, bottom, BL] );
						case 10:
							if (centerAbove) poly( [top, TR, right, bottom, BL, left] );
							else { poly( [top, TR, right] ); poly( [left, bottom, BL] ); }
						case 11: poly( [TL, TR, right, bottom, BL] );
						case 12: poly( [right, BR, BL, left] );
						case 13: poly( [TL, top, right, BR, BL] );
						case 14: poly( [top, TR, BR, BL, left] );
						default:
					}
				}
				flushRun( nx - 1 );
			}
			g.endFill();
		}

		// A whisper of contour line on each band edge to keep the map feel
		g.lineStyle( Brush.THIN_STROKE, lineC, 0.25 );
		for (li in 1...levels.length) {
			var L = levels[li];
			for (j in 0...ny - 1)
				for (i in 0...nx - 1) {
					var f00 = F[j * nx + i],       f10 = F[j * nx + i + 1];
					var f01 = F[(j + 1) * nx + i], f11 = F[(j + 1) * nx + i + 1];
					var idx = (f00 > L ? 1 : 0) | (f10 > L ? 2 : 0) | (f11 > L ? 4 : 0) | (f01 > L ? 8 : 0);
					if (idx == 0 || idx == 15) continue;

					var x0 = minX + i * cell, y0 = minY + j * cell;
					var x1 = x0 + cell,       y1 = y0 + cell;
					inline function lerpT( fa:Float, fb:Float ):Float
						return fa == fb ? 0.5 : (L - fa) / (fb - fa);
					var top    = new Point( x0 + lerpT( f00, f10 ) * cell, y0 );
					var bottom = new Point( x0 + lerpT( f01, f11 ) * cell, y1 );
					var left   = new Point( x0, y0 + lerpT( f00, f01 ) * cell );
					var right  = new Point( x1, y0 + lerpT( f10, f11 ) * cell );

					inline function seg( a:Point, b:Point ):Void {
						g.moveTo( a.x, a.y );
						g.lineTo( b.x, b.y );
					}

					var centerAbove = (f00 + f10 + f01 + f11) / 4 > L;
					switch (idx) {
						case 1, 14:  seg( left, top );
						case 2, 13:  seg( top, right );
						case 3, 12:  seg( left, right );
						case 4, 11:  seg( right, bottom );
						case 5:
							if (centerAbove) { seg( top, right ); seg( left, bottom ); }
							else             { seg( left, top ); seg( right, bottom ); }
						case 6, 9:   seg( top, bottom );
						case 7, 8:   seg( left, bottom );
						case 10:
							if (centerAbove) { seg( left, top ); seg( right, bottom ); }
							else             { seg( top, right ); seg( left, bottom ); }
						default:
					}
				}
		}
	}

	// A giant cave: everything beyond the cave wall is rock-dark, with a
	// jagged rim closing around the city.
	private function drawCavern( g:Graphics, model:Model ):Void {
		var cr = model.cityRadius;
		var c = model.center;

		// Jagged cave-wall rim (counter-clockwise, so it punches a hole in
		// the clockwise dark surround under the nonzero fill rule).
		var n = 56;
		var rim:Array<Point> = [];
		var radii:Array<Float> = [];
		for (i in 0...n) {
			var base = cr * 1.32;
			var wob = 1 + (Random.float() - 0.5) * 0.24 + Math.sin( i * 2.7 ) * 0.05;
			radii.push( base * wob );
		}
		// smooth the radii a touch so the rim reads as rock, not noise
		for (pass in 0...2)
			radii = [for (i in 0...n) (radii[(i + n - 1) % n] + radii[i] * 2 + radii[(i + 1) % n]) / 4];
		for (i in 0...n) {
			var a = -(i / n) * Math.PI * 2;	// negative: reverse winding
			rim.push( new Point( c.x + Math.cos( a ) * radii[i], c.y + Math.sin( a ) * radii[i] ) );
		}

		var rock = mix( palette.dark, 0x000000, 0.45 );
		var far = cr * 6;

		g.lineStyle( 0, 0, 0 );
		g.beginFill( rock );
		// outer square, clockwise
		g.moveTo( c.x - far, c.y - far );
		g.lineTo( c.x + far, c.y - far );
		g.lineTo( c.x + far, c.y + far );
		g.lineTo( c.x - far, c.y + far );
		g.lineTo( c.x - far, c.y - far );
		// inner rim, reverse winding: the cave opening
		g.moveTo( rim[0].x, rim[0].y );
		for (i in 1...n)
			g.lineTo( rim[i].x, rim[i].y );
		g.lineTo( rim[0].x, rim[0].y );
		g.endFill();

		// the rock lip
		g.lineStyle( Brush.THICK_STROKE * 1.2, palette.dark, 1 );
		g.moveTo( rim[0].x, rim[0].y );
		for (i in 1...n)
			g.lineTo( rim[i].x, rim[i].y );
		g.lineTo( rim[0].x, rim[0].y );

		// stalactite teeth along the rim, pointing into the cave
		g.lineStyle( 0, 0, 0 );
		g.beginFill( rock );
		var i = 0;
		while (i < n) {
			var p0 = rim[i];
			var p1 = rim[(i + 1) % n];
			var mx = (p0.x + p1.x) / 2, my = (p0.y + p1.y) / 2;
			var inx = c.x - mx, iny = c.y - my;
			var il = Math.sqrt( inx * inx + iny * iny );
			var tl = cr * (0.03 + Random.float() * 0.05);
			g.moveTo( p0.x, p0.y );
			g.lineTo( mx + inx / il * tl, my + iny / il * tl );
			g.lineTo( p1.x, p1.y );
			g.lineTo( p0.x, p0.y );
			i += 1 + Random.int( 0, 2 );
		}
		g.endFill();
	}
}