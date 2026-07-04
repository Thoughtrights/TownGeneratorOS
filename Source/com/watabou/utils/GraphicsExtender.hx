package com.watabou.utils;

import openfl.geom.Point;
import openfl.display.Graphics;

using com.watabou.utils.PointExtender;

class GraphicsExtender {

	// When enabled, every edge drawn via drawPolygon/drawPolyline gets a
	// small random bow at its midpoint instead of being perfectly straight,
	// for a rougher, hand-sketched look. Independent of color palette.
	public static var sketchy:Bool = false;
	public static var sketchAmount:Float = 0.3;

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

	private static function sketchLineTo( g:Graphics, v0:Point, v1:Point ) {
		if (!sketchy) {
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

		// Perpendicular unit vector, offset scaled a little by edge length
		// so long walls get a gentle bow rather than an invisible wobble.
		var nx = -dy / len;
		var ny = dx / len;
		var amount = Math.min( sketchAmount * 4, sketchAmount + len * 0.02 );
		var jitter = (Random.float() - 0.5) * 2 * amount;

		var mx = (v0.x + v1.x) / 2 + nx * jitter;
		var my = (v0.y + v1.y) / 2 + ny * jitter;

		g.lineTo( mx, my );
		g.lineTo( v1.x, v1.y );
	}

	public static inline function moveToPoint( g:Graphics, p:Point )
		g.moveTo( p.x, p.y );

	public static inline function lineToPoint( g:Graphics, p:Point )
		g.lineTo( p.x, p.y );
}
