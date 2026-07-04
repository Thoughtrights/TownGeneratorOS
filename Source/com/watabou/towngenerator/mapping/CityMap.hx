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
					case Market, CraftsmenWard, MerchantWard, GateWard, Slum, AdministrationWard, MilitaryWard, PatriciateWard, Farm:
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
						brush.setColor( g, advanced_palette.grass, advanced_palette.building );
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
			drawWall( walls.graphics, model.wall, false );

		if (model.citadel != null)
			drawWall( walls.graphics, cast( model.citadel.ward, Castle).wall, true );
	}

	private function drawRoad( g:Graphics, road:Street ):Void {
		g.lineStyle( Ward.MAIN_STREET + Brush.NORMAL_STROKE, palette.medium, false, null, CapsStyle.NONE );
		g.drawPolyline( road );

		g.lineStyle( Ward.MAIN_STREET - Brush.NORMAL_STROKE, palette.paper );
		g.drawPolyline( road );
	}

	private function drawWall( g:Graphics, wall:CurtainWall, large:Bool ):Void {
		g.lineStyle( Brush.THICK_STROKE, palette.dark );
		g.drawPolygon( wall.shape );

		for (gate in wall.gates)
			drawGate( g, wall.shape, gate );

		for (t in wall.towers)
			drawTower( g, t, Brush.THICK_STROKE * (large ? 1.5 : 1) );
	}

	private function drawTower( g:Graphics, p:Point, r:Float ) {
		brush.noStroke( g );
		g.beginFill( palette.dark );
		g.drawCircle( p.x, p.y, r );
		g.endFill();
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

	private function drawRoof( g:Graphics, block:Polygon, color:Int ):Void {
		var dir:Point = null;
		var bestLen = -1.0;
		block.forEdge( function( v0, v1 ) {
			var len = Point.distance( v0, v1 );
			if (len > bestLen) {
				bestLen = len;
				dir = v1.subtract( v0 );
			}
		} );

		var len = Math.sqrt( dir.x * dir.x + dir.y * dir.y );
		if (len < 0.001)
			return;
		var ux = dir.x / len;
		var uy = dir.y / len;
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