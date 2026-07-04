package com.watabou.utils;

import openfl.geom.Point;
import openfl.display.Graphics;

using com.watabou.utils.PointExtender;

class GraphicsExtender {

	// Intensity level: 0 disables it. Every level above that makes edges
	// drawn via drawPolygon/drawPolyline both wavier (more jittered points
	// per edge) and more displaced (bigger jitter), for a rougher,
	// hand-sketched look. Independent of color palette.
	public static var sketchy:Int = 0;
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

		// Perpendicular unit vector, offset scaled a little by edge length
		// so long walls get a gentle bow rather than an invisible wobble.
		// Higher levels get both a bigger offset and more wobble points.
		var nx = -dy / len;
		var ny = dx / len;
		var amount = Math.min( sketchAmount * 4, sketchAmount + len * 0.02 ) * sketchy;

		var segments = 1 + sketchy;
		for (i in 1...segments) {
			var t = i / segments;
			var jitter = (Random.float() - 0.5) * 2 * amount;
			var px = v0.x + dx * t + nx * jitter;
			var py = v0.y + dy * t + ny * jitter;
			g.lineTo( px, py );
		}
		g.lineTo( v1.x, v1.y );
	}

	public static inline function moveToPoint( g:Graphics, p:Point )
		g.moveTo( p.x, p.y );

	public static inline function lineToPoint( g:Graphics, p:Point )
		g.lineTo( p.x, p.y );
}
