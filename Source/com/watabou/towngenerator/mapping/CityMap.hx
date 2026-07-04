package com.watabou.towngenerator.mapping;

import com.watabou.utils.Random;

import openfl.display.Shape;
import openfl.display.CapsStyle;
import openfl.display.Graphics;
import openfl.display.Sprite;
import openfl.geom.Point;

import com.watabou.geom.Polygon;
import com.watabou.geom.GeomUtils;

import com.watabou.towngenerator.wards.*;
import com.watabou.towngenerator.building.CurtainWall;
import com.watabou.towngenerator.building.Model;

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

		for (road in model.roads) {
			var roadView = new Shape();
			drawRoad( roadView.graphics, road );
			addChild( roadView );
		}

		patches = [];
		for (patch in model.patches) {
			var patchView = new PatchView( patch );
			var patchDrawn = true;

                        if (palette_type == 'NORMAL'){
				var g = patchView.graphics;
				switch (Type.getClass( patch.ward )) {
					case Castle:
						drawBuilding( g, patch.ward.geometry, palette.light, palette.dark, Brush.NORMAL_STROKE * 2 );
						drawRoofHatching( g, patch.ward.geometry, palette.dark );
					case Cathedral:
						drawBuilding( g, patch.ward.geometry, palette.light, palette.dark, Brush.NORMAL_STROKE );
						drawRoofHatching( g, patch.ward.geometry, palette.dark );
					case Market, CraftsmenWard, MerchantWard, GateWard, Slum, AdministrationWard, MilitaryWard, PatriciateWard:
						brush.setColor( g, palette.light, palette.dark );
						for (building in patch.ward.geometry)
						    g.drawPolygon( building );
						drawRoofHatching( g, patch.ward.geometry, palette.dark );
					case Farm:
						drawFarmField( g, patch.shape, palette.medium, palette.dark );
						brush.setColor( g, palette.light, palette.dark );
						for (building in patch.ward.geometry)
						    g.drawPolygon( building );
						drawRoofHatching( g, patch.ward.geometry, palette.dark );
					case Park:
						brush.setColor( g, palette.medium );
						for (grove in patch.ward.geometry)
							g.drawPolygon( grove );
					default:
						patchDrawn = false;
				}
			}
			else if (palette_type == 'ADVANCED'){
				var g = patchView.graphics;
				switch (Type.getClass( patch.ward )) {
					case Castle:
						drawBuilding( g, patch.ward.geometry, advanced_palette.plot_medium, advanced_palette.building, BrushAdvanced.NORMAL_STROKE * 2 );
						drawRoofHatching( g, patch.ward.geometry, advanced_palette.building );
					case Cathedral:
						drawBuilding( g, patch.ward.geometry, advanced_palette.plot_medium, advanced_palette.building, BrushAdvanced.NORMAL_STROKE );
						drawRoofHatching( g, patch.ward.geometry, advanced_palette.building );
					case Market, CraftsmenWard, MerchantWard, GateWard, Slum, AdministrationWard, MilitaryWard, PatriciateWard:
						brush.setColor( g, advanced_palette.plot_medium, advanced_palette.building );
						for (building in patch.ward.geometry) {
						    if (Random.bool(0.8)) {
							brush.setColor( g, advanced_palette.plot_medium, advanced_palette.building );
						    } else {
							brush.setColor( g, advanced_palette.plot_dark, advanced_palette.building );
						    }
						    g.drawPolygon( building );
						}
						drawRoofHatching( g, patch.ward.geometry, advanced_palette.building );
					case Farm:
						drawFarmField( g, patch.shape, advanced_palette.grass, advanced_palette.building );
						brush.setColor( g, advanced_palette.plot_medium, advanced_palette.building );
						for (building in patch.ward.geometry)
							g.drawPolygon( building );
						drawRoofHatching( g, patch.ward.geometry, advanced_palette.building );
					case Park:
						brush.setColor( g, advanced_palette.grass );
						for (grove in patch.ward.geometry)
							g.drawPolygon( grove );
					default:
						patchDrawn = false;
				}
			}

			patches.push( patchView );
			if (patchDrawn)
				addChild( patchView );
		}

		for (patch in patches)
			addChild( patch.hotArea );

		var walls = new Shape();
		addChild( walls );

		if (model.wall != null)
			drawWall( walls.graphics, model.wall, false, model.center );

		if (model.citadel != null)
			drawWall( walls.graphics, cast( model.citadel.ward, Castle).wall, true, model.center );
	}

	private function drawRoad( g:Graphics, road:Street ):Void {
		g.lineStyle( Ward.MAIN_STREET + Brush.NORMAL_STROKE, palette.medium, false, null, CapsStyle.NONE );
		g.drawPolyline( road );

		g.lineStyle( Ward.MAIN_STREET - Brush.NORMAL_STROKE, palette.paper );
		g.drawPolyline( road );
	}

	private function drawWall( g:Graphics, wall:CurtainWall, large:Bool, center:Point ):Void {
		g.lineStyle( Brush.THICK_STROKE, palette.dark );
		g.drawPolygon( wall.shape );

		for (gate in wall.gates)
			drawGate( g, wall.shape, gate );

		for (t in wall.towers)
			drawTower( g, t, Brush.THICK_STROKE * (large ? 1.5 : 1), center );
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
}