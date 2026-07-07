package com.watabou.utils;

import openfl.geom.Point;
import openfl.display.Graphics;

using com.watabou.utils.PointExtender;

class GraphicsExtender {

	// Intensity level: 0 disables it. Every level above that makes edges
	// drawn via drawPolygon/drawPolyline both wavier (more jittered points
	// per edge) and more displaced (bigger jitter), for a rougher,
	// hand-sketched look. Independent of color palette. The scale is finer
	// than it used to be: today's maximum (5) equals the old level 2, so
	// the steps in between give real precision instead of caricature.
	public static var sketchy:Int = 0;
	public static var sketchAmount:Float = 0.3;

	// Local multiplier on the jitter, so different districts can be drawn
	// with different sloppiness (a slum sketchier than a patrician ward).
	// 1.0 = neutral; the renderer sets and restores it per patch.
	public static var sketchScale:Float = 1.0;

	public static function drawPolygon( g:Graphics, p:Array<Point> ) {
		var last = p.length - 1;
		var prev = p[last];
		g.moveTo( prev.x, prev.y );
		for (ver in p) {
			sketchLineTo( g, prev, ver );
			prev = ver;
		}
	}

	public static function drawPolyline( g:Graphics, p:Array<Point> ) {
		g.moveTo( p[0].x, p[0].y );
		for (i in 1...p.length) {
			sketchLineTo( g, p[i - 1], p[i] );
		}
	}

	// Deterministic pseudo-random in [0,1) from an edge and a wobble index.
	// Drawing the same edge twice (e.g. a water fill and its bank outline)
	// wobbles identically, so strokes hug their fills exactly.
	private static inline function hash( x0:Float, y0:Float, x1:Float, y1:Float, i:Int ):Float {
		var s = Math.sin( x0 * 12.9898 + y0 * 78.233 + x1 * 37.719 + y1 * 4.417 + i * 93.989 ) * 43758.5453;
		return s - Math.floor( s );
	}

	private static function sketchLineTo( g:Graphics, v0:Point, v1:Point ) {
		if (sketchy <= 0) {
			g.lineTo( v1.x, v1.y );
			return;
		}

		var dx = v1.x - v0.x;
		var dy = v1.y - v0.y;
		var len = Math.sqrt( dx * dx + dy * dy );
		if (len < 0.001) {
			g.lineTo( v1.x, v1.y );
			return;
		}

		// The wobble is computed in a canonical direction (lexicographically
		// smaller endpoint first) so an edge drawn v0->v1 and v1->v0 traces
		// the exact same crooked line.
		var flip = (v1.x < v0.x) || (v1.x == v0.x && v1.y < v0.y);
		var c0 = flip ? v1 : v0;
		var c1 = flip ? v0 : v1;
		var cdx = c1.x - c0.x;
		var cdy = c1.y - c0.y;

		// Perpendicular unit vector, offset scaled a little by edge length
		// so long walls get a gentle bow rather than an invisible wobble.
		// eff maps level 5 to the old level 2's displacement.
		var nx = -cdy / len;
		var ny = cdx / len;
		var eff = sketchy * 0.4 * sketchScale;
		var amount = Math.min( sketchAmount * 4, sketchAmount + len * 0.02 ) * eff;

		var segments = 1 + Math.ceil( eff );
		var pts:Array<Point> = [];
		for (i in 1...Std.int( segments )) {
			var t = i / segments;
			var jitter = (hash( c0.x, c0.y, c1.x, c1.y, i ) - 0.5) * 2 * amount;
			pts.push( new Point( c0.x + cdx * t + nx * jitter, c0.y + cdy * t + ny * jitter ) );
		}

		if (flip) pts.reverse();
		for (p in pts)
			g.lineTo( p.x, p.y );
		g.lineTo( v1.x, v1.y );
	}

	public static inline function moveToPoint( g:Graphics, p:Point )
		g.moveTo( p.x, p.y );

	public static inline function lineToPoint( g:Graphics, p:Point )
		g.lineTo( p.x, p.y );
}
