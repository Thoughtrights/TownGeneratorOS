package com.watabou.towngenerator.building;

import Type;
import openfl.errors.Error;
import openfl.geom.Point;

import com.watabou.geom.Polygon;
import com.watabou.geom.Segment;
import com.watabou.geom.Voronoi;
import com.watabou.geom.GeomUtils;
import com.watabou.utils.MathUtils;
import com.watabou.utils.Random;

import com.watabou.towngenerator.wards.*;

using com.watabou.utils.PointExtender;
using com.watabou.utils.ArrayExtender;

typedef Street = Polygon;

class Model {

	public static var instance	: Model;

	// Small Town	6
	// Large Town	10
	// Small City	15
	// Large City	24
	// Metropolis	40
	private var nPatches	: Int;

	private var plazaNeeded		: Bool;
	private var citadelNeeded	: Bool;
	private var wallsNeeded		: Bool;
	private var parksNeeded		: Int;
	private var farmsNeeded		: Int;
	private var templesNeeded	: Bool;
	private var riverNeeded		: Bool;
	private var coastNeeded		: Bool;

	// Water geometry, filled by buildWater() and consumed by the renderer.
	public var seaShape		: Polygon;		// filled sea polygon (coast)
	public var seaShoreLine	: Array<Point>;	// just the wavy shoreline of the sea
	public var riverShape	: Polygon;		// filled river ribbon (river)
	private var coastDir	: Point;		// unit vector pointing out to sea
	private var shoreDist	: Float = 0;	// projection of the shoreline along coastDir
	private var cityR		: Float = 0;	// approximate city radius
	public var riverPath	: Array<Point>;	// smoothed river centreline (for bridges)
	private var riverHalf	: Float = 0;	// base half the river's visible width
	private var riverHalves	: Array<Float>;	// per-centreline-vertex half-width (flare)
	public var bridges		: Array<Array<Point>>;	// each [bankA, bankB] deck endpoints
	public var docks		: Array<Polygon>;		// narrow I/L harbour docks

	// Below this patch count, folding the citadel into the main wall's
	// boundary produces a wall shape that isn't simply connected (too
	// little room around the citadel), which breaks street pathfinding.
	// Smaller cities fall back to the classic rim-attached citadel.
	private static inline var MIN_PATCHES_FOR_ENCLOSED_CITADEL = 20;

	private var citadelEnclosed	: Bool = false;

	public static var WARDS:Array<Class<Ward>> = [
		CraftsmenWard, CraftsmenWard, MerchantWard, CraftsmenWard, CraftsmenWard, CraftsmenWard,
		CraftsmenWard, CraftsmenWard, CraftsmenWard, CraftsmenWard, CraftsmenWard,
		CraftsmenWard, CraftsmenWard, CraftsmenWard, AdministrationWard, CraftsmenWard,
		Slum, CraftsmenWard, Slum, PatriciateWard, Market,
		Slum, CraftsmenWard, CraftsmenWard, CraftsmenWard, Slum,
		CraftsmenWard, CraftsmenWard, CraftsmenWard, MilitaryWard, Slum,
		CraftsmenWard, CraftsmenWard, PatriciateWard, Market, MerchantWard];

	public var topology	: Topology;

	public var patches	: Array<Patch>;
	public var waterbody: Array<Patch>;
	// For a walled city it's a list of patches within the walls,
	// for a city without walls it's just a list of all city wards
	public var inner	: Array<Patch>;
	public var citadel	: Patch;
	public var plaza	: Patch;
	public var center	: Point;

	public var border	: CurtainWall;
	public var wall		: CurtainWall;

	public var cityRadius	: Float;

	// List of all entrances of a city including castle gates
	public var gates	: Array<Point>;

	// Joined list of streets (inside walls) and roads (outside walls)
	// without diplicating segments
	public var arteries	: Array<Street>;
	public var streets	: Array<Street>;
	public var roads	: Array<Street>;
	public var inputWalls   : Bool;
	public var inputPlaza   : Bool;
	public var inputCitadel : Bool;

	public function new( nPatches=-1, seed=-1, inputWalls=true, inputPlaza=true, inputCitadel, inputParks=1, inputFarms=6, inputTemples=true, inputRiver=false, inputCoast=false ) {

		if (seed > 0) Random.reset( seed );
		this.nPatches = nPatches != -1 ? nPatches : 15;

		if (inputWalls == true) {
		   wallsNeeded = true;
		} else {
		   wallsNeeded = false;
		}
		if (inputPlaza == true) {
		   plazaNeeded = true;
		} else {
		   plazaNeeded = false;
		}
		if (inputCitadel == true) {
		   citadelNeeded = true;
		} else {
		   citadelNeeded = false;
		}
		parksNeeded = inputParks >= 0 ? inputParks : 0;
		farmsNeeded = inputFarms >= 0 ? inputFarms : 0;
		templesNeeded = inputTemples == true;
		riverNeeded = inputRiver == true;
		coastNeeded = inputCoast == true;

		do try {
			build();
			instance = this;
		} catch (e:Dynamic) {
			// Some layouts (e.g. a degenerate citadel/wall boundary) fail
			// downstream as native runtime errors rather than an Error we
			// throw ourselves; treat any failure as a cue to reroll, same
			// as the deliberate Error cases below.
			trace( e );
			instance = null;
		} while (instance == null);
	}

	private function build():Void {
		streets = [];
		roads = [];

		buildPatches();
		buildWater();
		optimizeJunctions();
		buildWalls();
		buildStreets();
		createWards();
		buildGeometry();
	}

	private function buildPatches():Void {
		var sa = Random.float() * 2 * Math.PI;
		var points = [for (i in 0...nPatches * 8) {
			var a = sa + Math.sqrt( i ) * 5;
			var r = (i == 0 ? 0 : 10 + i * (2 + Random.float()));
			new Point( Math.cos( a ) * r, Math.sin( a ) * r );
		}];
		var voronoi = Voronoi.build( points );

		// Relaxing central wards
		for (i in 0...3) {
			var toRelax = [for (j in 0...3) voronoi.points[j]];
			toRelax.push( voronoi.points[nPatches] );
			voronoi = Voronoi.relax( voronoi, toRelax );
		}

		voronoi.points.sort( function( p1:Point, p2:Point )
			return MathUtils.sign( p1.length - p2.length ) );
		var regions = voronoi.partioning();

		patches = [];
		inner = [];

		// Reset in case a previous attempt in the retry loop got as far as
		// picking a citadel before failing later on; without this, a stale
		// reference from a discarded layout survives into this attempt.
		citadel = null;
		citadelEnclosed = false;

		var rimCitadelCandidate:Patch = null;

		var count = 0;
		for (r in regions) {
			var patch = Patch.fromRegion( r );
			patches.push( patch );

			if (count == 0) {
				center = patch.shape.min( function( p:Point ) return p.length );
				if (plazaNeeded)
					plaza = patch;
			} else if (count == nPatches && citadelNeeded) {
				rimCitadelCandidate = patch;
			}

			if (count < nPatches) {
				patch.withinCity = true;
				patch.withinWalls = wallsNeeded;
				inner.push( patch );
			}

			count++;
		}

		if (citadelNeeded) {
			citadelEnclosed = nPatches >= MIN_PATCHES_FOR_ENCLOSED_CITADEL;

			// A large enough city can sometimes host the citadel as a fully
			// interior keep, surrounded on every side by other city wards
			// and never touching the outer wall, rather than always sitting
			// on the rim attached to it.
			if (citadelEnclosed && Random.bool()) {
				var candidates = inner.filter( function( p:Patch )
					return p != plaza && getNeighbours( p ).every( function( n:Patch ) return inner.contains( n ) ) );
				if (candidates.length > 0) {
					citadel = candidates.random();
					inner.remove( citadel );
				}
			}

			if (citadel == null && rimCitadelCandidate != null) {
				citadel = rimCitadelCandidate;
				citadel.withinCity = true;
			}

			if (citadel != null)
				citadel.withinWalls = citadelEnclosed && wallsNeeded;
		}
	}

	private function buildWater():Void {
		waterbody = [];
		seaShape = null;
		seaShoreLine = null;
		riverShape = null;
		coastDir = null;
		riverPath = null;
		bridges = [];
		docks = [];

		if (!coastNeeded && !riverNeeded)
			return;

		// Overall city radius, used to place the shoreline, size the (finite)
		// sea polygon, and scale the river to the city rather than to absolute
		// distances the renderer can't handle.
		cityR = 0.0;
		for (p in inner)
			for (v in p.shape) {
				var d = Point.distance( v, center );
				if (d > cityR) cityR = d;
			}
		if (cityR <= 0) cityR = 100;

		// Coast first so an estuary river can be aimed at the shoreline.
		if (coastNeeded)
			buildCoast( cityR );
		if (riverNeeded)
			buildRiver( cityR );

		if (coastNeeded)
			buildDocks( cityR );
	}

	// True if a point is under the sea / under the river, individually. Used
	// by the renderer to stroke only land-facing water edges so the two
	// bodies read as one merged surface where they meet.
	public function inSea( p:Point ):Bool {
		if (coastDir == null) return false;
		var pr = seaProj( p );
		if (seaShoreLine == null) return pr > shoreDist;

		// Test against the actual wavy shoreline (not the straight shoreDist
		// line) so building/wall/road clipping matches the drawn sea exactly:
		// find the shoreline sample nearest along the coast and use its depth.
		var shoreVec = coastDir.rotate90();
		var tp = (p.x - center.x) * shoreVec.x + (p.y - center.y) * shoreVec.y;
		var best = Math.POSITIVE_INFINITY;
		var localShore = shoreDist;
		for (s in seaShoreLine) {
			var ts = (s.x - center.x) * shoreVec.x + (s.y - center.y) * shoreVec.y;
			var d = Math.abs( ts - tp );
			if (d < best) { best = d; localShore = seaProj( s ); }
		}
		return pr > localShore;
	}

	public function inRiver( p:Point ):Bool {
		if (riverPath == null) return false;
		// Use the local (possibly flared) half-width at the nearest centreline
		// vertex, so the wide estuary mouth counts as water too.
		var best = Math.POSITIVE_INFINITY;
		var bi = 0;
		for (i in 0...riverPath.length) {
			var d = Point.distance( p, riverPath[i] );
			if (d < best) { best = d; bi = i; }
		}
		var half = riverHalves != null ? riverHalves[bi] : riverHalf;
		return distToPath( p, riverPath ) < half + 1;
	}

	// Narrow piers reaching from the harbour shore into the sea, near the
	// city centre. Each is stored as an open polyline (a stroke skeleton the
	// renderer draws as thin planking): a straight I, a right-angled L, or —
	// with a separate crossbar entry — a T. Docks only ever stand in the
	// sea, never up the river.
	private function buildDocks( cr:Float ):Void {
		docks = [];
		if (coastDir == null) return;		// harbour is on the open sea

		var shoreVec = coastDir.rotate90();

		var wanted = 5 + Random.int( 0, 4 );
		for (k in 0...wanted) {
			// a ray seaward from near the centre, to find the local waterline
			var t = (Random.float() - 0.5) * cr * 1.1;
			var from = new Point( center.x + shoreVec.x * t, center.y + shoreVec.y * t );

			var waterline:Point = null;
			var hit = false;
			var stepN = 80;
			for (s in 0...stepN) {
				var d = s / stepN * cr * 2.2;
				var p = new Point( from.x + coastDir.x * d, from.y + coastDir.y * d );
				if (inSea( p )) { hit = true; break; }
				if (inRiver( p )) { hit = false; break; }	// river bank: no pier here
				waterline = p;
			}
			if (!hit || waterline == null || Point.distance( waterline, center ) > cr * 1.3)
				continue;

			// the spine: from just landward of the waterline out into the sea
			var len = cr * (0.055 + Random.float() * 0.06);
			var base = new Point( waterline.x - coastDir.x * cr * 0.02, waterline.y - coastDir.y * cr * 0.02 );
			var tip  = new Point( waterline.x + coastDir.x * len, waterline.y + coastDir.y * len );

			var style = Random.float();
			if (style < 0.4) {
				// I: plain finger pier
				docks.push( [base, tip] );
			} else if (style < 0.75) {
				// L: the spine turns a right angle at its seaward end
				var arm = len * (0.35 + Random.float() * 0.3);
				var side = Random.bool() ? 1.0 : -1.0;
				docks.push( [base, tip,
					new Point( tip.x + shoreVec.x * arm * side, tip.y + shoreVec.y * arm * side )] );
			} else {
				// T: a crossbar centred on the seaward end
				var arm = len * (0.3 + Random.float() * 0.25);
				docks.push( [base, tip] );
				docks.push( [
					new Point( tip.x - shoreVec.x * arm, tip.y - shoreVec.y * arm ),
					new Point( tip.x + shoreVec.x * arm, tip.y + shoreVec.y * arm )] );
			}
		}
	}

	// Projection of a point onto the sea-facing axis, measured from the
	// city centre. Larger = further out to sea.
	private inline function seaProj( p:Point ):Float
		return (p.x - center.x) * coastDir.x + (p.y - center.y) * coastDir.y;

	// True if a point lies in open water (sea or river).
	public function isWater( p:Point ):Bool
		return inSea( p ) || inRiver( p );

	// Removes a patch from the model and records it as water.
	private function floodPatch( p:Patch ):Void {
		p.water = true;
		patches.remove( p );
		inner.remove( p );
		waterbody.push( p );
	}

	private function buildCoast( cr:Float ):Void {
		// A random direction pointing out to sea
		var a = Random.float() * 2 * Math.PI;
		coastDir = new Point( Math.cos( a ), Math.sin( a ) );

		// Put the shoreline partway across the seaward side of the city so a
		// broad arc of districts fronts the water. The water is a geometric
		// overlay (not removed patches): it's drawn over open land and farms,
		// clips the individual houses that straddle it, and opens the wall
		// where it crosses — so districts can sit right on the waterline.
		shoreDist = cr * (0.62 + Random.float() * 0.14);

		buildSeaShape( cr );
	}

	// A filled polygon covering the seaward side of the shoreline, with a
	// gently wavy coast so it doesn't read as a ruled line. Sized to a few
	// city radii — large enough to run off-screen, but not so large that the
	// html5 renderer treats the shape as an oversized (and unrenderable) box.
	private function buildSeaShape( cr:Float ):Void {
		if (cr <= 0) cr = 100;
		var shoreVec = coastDir.rotate90();				// along the shore
		var base = new Point( center.x + coastDir.x * shoreDist, center.y + coastDir.y * shoreDist );

		var span = cr * 5;		// along-shore half-length
		var far = cr * 5;		// how far out to sea to fill
		var wob = cr * 0.06;	// shore wobble amplitude
		var n = 60;
		var phase = Random.float() * Math.PI * 2;

		var pts:Array<Point> = [];
		for (i in 0...n + 1) {
			var t = -span + (2 * span) * i / n;
			// gentle multi-frequency wobble, unbiased (clipping now tracks the
			// actual shoreline via inSea, so no landward bias is needed)
			var wobble = Math.sin( phase + t / cr * 0.9 ) * wob + Math.sin( phase * 2.3 + t / cr * 2.4 ) * wob * 0.4;
			pts.push( new Point(
				base.x + shoreVec.x * t + coastDir.x * wobble,
				base.y + shoreVec.y * t + coastDir.y * wobble
			) );
		}

		seaShoreLine = pts;

		var poly = pts.copy();
		poly.push( new Point( pts[n].x + coastDir.x * far, pts[n].y + coastDir.y * far ) );
		poly.push( new Point( pts[0].x + coastDir.x * far, pts[0].y + coastDir.y * far ) );
		seaShape = new Polygon( poly );
	}

	// Smooths an open polyline, keeping its endpoints fixed.
	private function smoothOpen( path:Array<Point> ):Array<Point> {
		var m = path.length;
		if (m < 3) return path;
		var r = [path[0]];
		for (i in 1...m - 1)
			r.push( new Point(
				(path[i - 1].x + path[i].x * 2 + path[i + 1].x) / 4,
				(path[i - 1].y + path[i].y * 2 + path[i + 1].y) / 4
			) );
		r.push( path[m - 1] );
		return r;
	}

	// Shortest distance from a point to a polyline.
	private function distToPath( p:Point, path:Array<Point> ):Float {
		var best = Math.POSITIVE_INFINITY;
		for (i in 0...path.length - 1) {
			var a = path[i];
			var b = path[i + 1];
			var dx = b.x - a.x;
			var dy = b.y - a.y;
			var l2 = dx * dx + dy * dy;
			var t = l2 > 0 ? ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2 : 0.0;
			t = t < 0 ? 0 : (t > 1 ? 1 : t);
			var cx = a.x + dx * t;
			var cy = a.y + dy * t;
			var d = Point.distance( p, new Point( cx, cy ) );
			if (d < best) best = d;
		}
		return best;
	}

	private function buildRiver( cr:Float ):Void {
		// Visible river width: clearly wider than a street (4-10x a main
		// street). The river is a geometric overlay — patches stay put, the
		// ribbon is drawn over them, houses straddling it are clipped, the
		// wall opens where it crosses, and streets bridge it.
		var width = Ward.MAIN_STREET * (4 + Random.float() * 6);
		riverHalf = width / 2;

		// The river must never swallow the citadel or the plaza — try a
		// handful of layouts (varying course and offset); if none stays
		// clear, throw so the whole city rerolls (standard retry loop).
		for (attempt in 0...8) {
			// General flow direction across the map. With a coast, aim roughly
			// out to sea so the river reads as an estuary at the junction.
			var flowA = coastDir != null ? Math.atan2( coastDir.y, coastDir.x ) + (Random.float() - 0.5) * 0.7 : Random.float() * 2 * Math.PI;
			var dir = new Point( Math.cos( flowA ), Math.sin( flowA ) );
			var perp = dir.rotate90();
			// Run it through the city (near the centre) so it genuinely bisects
			// the built-up area, with the two banks joined by bridges. A modest
			// offset keeps the plaza on one side.
			var side = Random.bool() ? 1.0 : -1.0;
			var offset = side * (0.05 + Random.float() * 0.28) * cr;

			var thru = new Point( center.x + perp.x * offset, center.y + perp.y * offset );

			// A few control points from one edge of the map to the other, each
			// nudged sideways for gentle bends.
			var reach = cr * 2.8;
			var n = 6;
			var ctrl:Array<Point> = [];
			for (i in 0...n + 1) {
				var s = -reach + (2 * reach) * i / n;
				var bend = (Random.float() - 0.5) * cr * 0.5;
				ctrl.push( new Point(
					thru.x + dir.x * s + perp.x * bend,
					thru.y + dir.y * s + perp.y * bend
				) );
			}

			// Subdivide and smooth (open polyline, endpoints fixed) into a
			// flowing centreline.
			var dense:Array<Point> = [];
			for (i in 0...ctrl.length - 1) {
				var a = ctrl[i];
				var b = ctrl[i + 1];
				var steps = 4;
				for (k in 0...steps)
					dense.push( GeomUtils.interpolate( a, b, k / steps ) );
			}
			dense.push( ctrl[ctrl.length - 1] );

			for (pass in 0...3)
				dense = smoothOpen( dense );

			// Per-vertex half-width: constant upstream, flaring toward the sea
			// end so the river opens into a broad mouth at an estuary.
			var m = dense.length;
			var halves = [for (i in 0...m) riverHalf];
			if (coastDir != null) {
				// Which end runs out to sea (further along coastDir)
				var seaAtEnd = seaProj( dense[m - 1] ) > seaProj( dense[0] );
				for (i in 0...m) {
					var t = seaAtEnd ? i / (m - 1) : 1 - i / (m - 1);	// 0 upstream .. 1 at sea
					var flare = t < 0.55 ? 0.0 : (t - 0.55) / 0.45;		// last ~45% widens
					halves[i] = riverHalf * (1 + 1.7 * flare);
				}
			}

			// Clearance check: the river (at its widest anywhere, i.e. the
			// estuary flare if there is one) must keep a margin from the
			// citadel and the plaza.
			var maxHalf = riverHalf;
			for (h in halves) if (h > maxHalf) maxHalf = h;
			var clearance = maxHalf * 1.2 + 3;
			var blocked = false;
			if (citadel != null)
				for (v in citadel.shape)
					if (distToPath( v, dense ) < clearance) { blocked = true; break; }
			if (!blocked && plaza != null)
				if (distToPath( plaza.shape.centroid, dense ) < clearance)
					blocked = true;

			if (blocked) continue;

			riverPath = dense;
			riverHalves = halves;
			riverShape = buildRibbon( riverPath, halves );
			return;
		}

		throw new Error( "River can't avoid the citadel/plaza!" );
	}

	// Nearest land patch vertex to a point (used to anchor a bridge deck to
	// the street network on the bank).
	private function nearestLandVertex( c:Point, maxDist:Float ):Point {
		var best:Point = null;
		var bd = maxDist;
		for (p in patches)
			for (v in p.shape) {
				var d = Point.distance( v, c );
				if (d < bd) { bd = d; best = v; }
			}
		return best;
	}

	// Link the two banks at a crossing so a street may bridge the river here.
	// No deck is drawn yet — that happens once the streets actually exist.
	private function linkCrossing( ci:Int ):Void {
		var m = riverPath.length;
		var c = riverPath[ci];
		var a1 = riverPath[ci > 0 ? ci - 1 : 0];
		var a2 = riverPath[ci < m - 1 ? ci + 1 : m - 1];
		var perp = new Point( -(a2.y - a1.y), a2.x - a1.x );
		perp.normalize( riverHalf + Math.max( 4, cityR * 0.04 ) );

		var na = nearestLandVertex( new Point( c.x + perp.x, c.y + perp.y ), riverHalf * 3 );
		var nb = nearestLandVertex( new Point( c.x - perp.x, c.y - perp.y ), riverHalf * 3 );
		if (na != null && nb != null)
			topology.addLink( na, nb );
	}

	// Offer the street network crossings where the river runs through / past
	// the city, so roads can span it. A river through the built area gets
	// several, one running alongside gets one at its closest approach.
	private function linkRiverCrossings():Void {
		if (riverPath == null) return;

		var m = riverPath.length;
		var first = -1, last = -1, nearest = 0;
		var nearestD = Math.POSITIVE_INFINITY;
		for (i in 0...m) {
			var d = Point.distance( riverPath[i], center );
			if (d < nearestD) { nearestD = d; nearest = i; }
			if (d < cityR * 1.05) {
				if (first < 0) first = i;
				last = i;
			}
		}

		if (first < 0 || last <= first) {
			if (nearestD < cityR * 1.6)
				linkCrossing( nearest );
			return;
		}

		var spanLen = 0.0;
		for (i in first...last)
			spanLen += Point.distance( riverPath[i], riverPath[i + 1] );
		var count = 1 + Std.int( spanLen / (cityR * 0.7) );
		if (count > 4) count = 4;

		for (b in 0...count)
			linkCrossing( first + Std.int( (last - first) * (b + 0.5) / count ) );
	}

	// Nearest point on the river centreline to p, with the local flow
	// direction (unit) and half-width there. Used to lay a bridge square
	// across the river.
	private function nearestOnRiver( p:Point ):{ c:Point, dir:Point, half:Float } {
		var best = Math.POSITIVE_INFINITY;
		var bc = riverPath[0];
		var bdir = new Point( 1, 0 );
		var bhalf = riverHalf;
		for (i in 0...riverPath.length - 1) {
			var a = riverPath[i];
			var b = riverPath[i + 1];
			var dx = b.x - a.x;
			var dy = b.y - a.y;
			var l2 = dx * dx + dy * dy;
			if (l2 < 1e-9) continue;
			var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2;
			t = t < 0 ? 0 : (t > 1 ? 1 : t);
			var cx = a.x + dx * t;
			var cy = a.y + dy * t;
			var d = (p.x - cx) * (p.x - cx) + (p.y - cy) * (p.y - cy);
			if (d < best) {
				best = d;
				bc = new Point( cx, cy );
				var l = Math.sqrt( l2 );
				bdir = new Point( dx / l, dy / l );
				bhalf = riverHalves != null ? (riverHalves[i] + riverHalves[i + 1]) / 2 : riverHalf;
			}
		}
		return { c: bc, dir: bdir, half: bhalf };
	}

	// Which side of the river centreline a point is on (+1 / -1), by the
	// nearest centreline segment. 0 only for a degenerate path.
	private function riverSide( p:Point ):Float {
		var best = Math.POSITIVE_INFINITY;
		var side = 0.0;
		for (i in 0...riverPath.length - 1) {
			var a = riverPath[i];
			var b = riverPath[i + 1];
			var dx = b.x - a.x;
			var dy = b.y - a.y;
			var l2 = dx * dx + dy * dy;
			if (l2 < 1e-9) continue;
			var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2;
			t = t < 0 ? 0 : (t > 1 ? 1 : t);
			var cx = a.x + dx * t;
			var cy = a.y + dy * t;
			var d = (p.x - cx) * (p.x - cx) + (p.y - cy) * (p.y - cy);
			if (d < best) {
				best = d;
				side = ((p.x - a.x) * dy - (p.y - a.y) * dx) > 0 ? 1.0 : -1.0;
			}
		}
		return side;
	}

	// Once the streets exist, drop a bridge deck wherever a road crosses the
	// river. Each deck is laid perpendicular to the river (the shortest
	// possible span) and centred on the centreline — so it always reads short
	// and square, whatever angle the road approaches at.
	//
	// Crossings are found by walking each artery in small steps and watching
	// for stretches that dip into the river with land on both sides — robust
	// against any segment length or river curvature (a side-of-centreline
	// test can miss real crossings near sharp bends). A road that merely
	// *ends* in the water (clipped at the bank) is not a crossing. Decks are
	// kept apart, capped in number, and never attempted across a flared
	// estuary mouth (too wide to bridge — the road stops at the bank).
	public function placeBridges():Void {
		bridges = [];
		if (riverPath == null || arteries == null) return;

		var margin = Math.max( 3, cityR * 0.03 );
		var maxBridges = 5;
		var maxBridgeHalf = riverHalf * 1.35;	// wider than this (estuary mouth): no bridge
		var step = 2.0;

		// Sample every artery densely, remembering the on-land samples: a
		// bridge only goes where there's road on both banks to serve it.
		var landSamples:Array<Point> = [];
		var wetSamples:Array<Point> = [];
		for (a in arteries)
			for (i in 0...a.length - 1) {
				var p0 = a[i];
				var p1 = a[i + 1];
				var d = Point.distance( p0, p1 );
				var n = Math.ceil( d / step );
				for (k in 0...Std.int( n ) + 1) {
					var p = GeomUtils.interpolate( p0, p1, k / n );
					if (inRiver( p ))
						wetSamples.push( p )
					else
						landSamples.push( p );
				}
			}

		// A crossing must be usable from both banks. (An artery is often
		// chained so that it *ends* mid-river and another one continues on
		// the far side, so bridgeability is judged geometrically per wet
		// spot, not within any single artery.)
		var serveDist = riverHalf * 1.6 + margin * 2;
		for (wp in wetSamples) {
			if (bridges.length >= maxBridges) break;

			var near = nearestOnRiver( wp );

			// Too wide to bridge (flared estuary mouth)
			if (near.half > maxBridgeHalf) continue;

			// Keep decks well apart
			var dup = false;
			for (br in bridges) {
				var bm = new Point( (br[0].x + br[1].x) / 2, (br[0].y + br[1].y) / 2 );
				if (Point.distance( bm, near.c ) < Math.max( near.half * 3, riverHalf * 4 )) { dup = true; break; }
			}
			if (dup) continue;

			// Deck square across the river, centred on the centreline.
			var perp = new Point( -near.dir.y, near.dir.x );
			var reach = near.half + margin;
			var endA = new Point( near.c.x + perp.x * reach, near.c.y + perp.y * reach );
			var endB = new Point( near.c.x - perp.x * reach, near.c.y - perp.y * reach );

			// Both ends must land on solid ground...
			if (isWater( endA ) || isWater( endB )) continue;

			// ...with road nearby on each bank.
			var servedA = false, servedB = false;
			for (lp in landSamples) {
				if (!servedA && Point.distance( lp, endA ) < serveDist) servedA = true;
				if (!servedB && Point.distance( lp, endB ) < serveDist) servedB = true;
				if (servedA && servedB) break;
			}
			if (!servedA || !servedB) continue;

			bridges.push( [endA, endB] );
		}
	}

	// Turns a polyline into a closed ribbon polygon, offsetting each vertex
	// along its averaged normal by that vertex's half-width (so the ribbon
	// can flare, e.g. at a river mouth).
	private function buildRibbon( path:Array<Point>, halves:Array<Float> ):Polygon {
		var left:Array<Point> = [];
		var right:Array<Point> = [];
		var m = path.length;
		for (i in 0...m) {
			var a = path[i > 0 ? i - 1 : 0];
			var b = path[i < m - 1 ? i + 1 : m - 1];
			var dx = b.x - a.x;
			var dy = b.y - a.y;
			var len = Math.sqrt( dx * dx + dy * dy );
			if (len < 0.0001) len = 1;
			var nx = -dy / len;
			var ny = dx / len;
			var h = halves[i];
			left.push( new Point( path[i].x + nx * h, path[i].y + ny * h ) );
			right.push( new Point( path[i].x - nx * h, path[i].y - ny * h ) );
		}
		right.reverse();
		return new Polygon( left.concat( right ) );
	}

	// Open the wall where it runs along water (a quay / water-gate) rather
	// than walling off the harbour. Relies on CurtainWall.segments, which
	// tower-building and rendering already respect.
	private function openWaterWallSegments( w:CurtainWall, isCastle=false ):Void {
		var shape = w.shape;
		var len = shape.length;
		for (i in 0...len) {
			var v0 = shape[i];
			var v1 = shape[(i + 1) % len];
			var mid = new Point( (v0.x + v1.x) / 2, (v0.y + v1.y) / 2 );

			// Open any wall edge that actually lies in water — the seaward
			// harbour arc for a coast, or the two crossings of a river
			// (its water-gates). Everywhere else the wall stays complete.
			var open = isWater( mid );

			// On the main wall, never open the stretch where it meets the
			// citadel, or it would stop short of the castle instead of
			// wrapping around to connect to it — but only on land: a wall
			// edge standing in the open sea is never kept, even next to a
			// castle (that's how castle-side walls ended up striding out
			// into the harbour). The castle's own wall is exempt entirely.
			if (open && !isCastle && citadel != null && !inSea( mid )) {
				for (cv in citadel.shape)
					if (Point.distance( mid, cv ) < cityR * 0.22) { open = false; break; }
			}

			if (open)
				w.segments[i] = false;
		}
	}

	private function buildWalls():Void {
		var reserved = citadel != null ? citadel.shape.copy() : [];

		// Fold the citadel into the walled area so the main wall wraps
		// around it instead of stopping at its inner-facing edge, leaving
		// the castle's own wall (built below) as a secondary inner wall.
		// Only attempted for large enough cities; see citadelEnclosed.
		var wallPatches = citadelEnclosed ? inner.concat( [citadel] ) : inner;

                border = new CurtainWall( wallsNeeded, this, wallPatches, reserved );
		if (coastNeeded || riverNeeded)
			openWaterWallSegments( border );
		if (wallsNeeded) {
			wall = border;
			wall.buildTowers();
			// No towers standing out in the harbour or river
			if (coastNeeded || riverNeeded)
				wall.towers = wall.towers.filter( function( t:Point ) return !isWater( t ) );
		}

		var radius = border.getRadius();
		patches = patches.filter( function( p:Patch ) return p.shape.distance( center ) < radius * 3 );

		// Drop any gate that fell in water (a seaward or mid-river vertex); a
		// street shouldn't march out into the harbour or river. The wall is
		// already opened there. Land gates keep their streets, which bridge
		// the river where they cross it.
		gates = border.gates.filter( function( g:Point ) return !isWater( g ) );

		if (citadel != null) {
			var castle = new Castle( this, citadel );
			// A castle can sit on the river/coast too — open its own wall where
			// it meets the water, just like the main wall.
			if (coastNeeded || riverNeeded)
				openWaterWallSegments( castle.wall, true );
			castle.wall.buildTowers();
			if (coastNeeded || riverNeeded)
				castle.wall.towers = castle.wall.towers.filter( function( t:Point ) return !isWater( t ) );
			citadel.ward = castle;

			if (citadel.shape.compactness < 0.75)
				throw new Error( "Bad citadel shape!" );

			gates = gates.concat( castle.wall.gates.filter( function( g:Point ) return !isWater( g ) ) );
		}
	}

	public static function findCircumference( wards:Array<Patch> ):Polygon {
		if (wards.length == 0)
			return new Polygon()
		else if (wards.length == 1)
			return new Polygon( wards[0].shape );

		var A:Array<Point> = [];
		var B:Array<Point> = [];

		for (w1 in wards)
			w1.shape.forEdge( function(a, b ) {
				var outerEdge = true;
				for (w2 in wards)
					if (w2.shape.findEdge( b, a ) != -1) {
						outerEdge = false;
						break;
					}
				if (outerEdge) {
					A.push( a );
					B.push( b );
				}
			} );

		var result = new Polygon();
		var index = 0;
		do {
			result.push( A[index] );
			index = A.indexOf( B[index] );
		} while (index != 0);

		return result;
	}

	public function patchByVertex( v:Point ):Array<Patch> {
		return patches.filter(
			function( patch:Patch ) return patch.shape.contains( v )
		);
	}

	private function buildStreets():Void {

		function smoothStreet( street:Street ):Void {
			var smoothed = street.smoothVertexEq( 3 );
			for (i in 1...street.length-1)
				street[i].set( smoothed[i] );
		}

		topology = new Topology( this );

		if (riverPath != null)
			linkRiverCrossings();

		for (gate in gates) {
			// Each gate is connected to the nearest corner of the plaza or to the central junction
			var end:Point = plaza != null ?
				plaza.shape.min( function( v ) return Point.distance( v, gate ) ) :
				center;

			// optimizeJunctions may have merged the endpoint's exact vertex
			// away (its Point no longer sits in any shape, so it has no
			// topology node) — snap to the nearest node that exists, or no
			// street can ever be built to it.
			if (topology.pt2node[end] == null) {
				var best:Point = null;
				var bd = Math.POSITIVE_INFINITY;
				for (p in topology.node2pt) {
					var d = Point.distance( p, end );
					if (d < bd) { bd = d; best = p; }
				}
				if (best != null) end = best;
			}

			var street = topology.buildPath( gate, end, topology.outer );
			if (street != null) {
				streets.push( street );

				if (border.gates.contains( gate )) {
					var dir = gate.norm( 1000 );
					var start = null;
					var dist = Math.POSITIVE_INFINITY;
					for (p in topology.node2pt) {
						var d = Point.distance( p, dir );
						if (d < dist) {
							dist = d;
							start = p;
						}
					}

					var road = topology.buildPath( start, gate, topology.inner );
					if (road != null)
						roads.push( road );
				}
			} else if (riverNeeded || coastNeeded) {
				// With water in play a stray gate can end up cut off from the
				// plaza (e.g. across the river). Tolerate it — skip that one
				// street — rather than throwing the whole city away and
				// regenerating, which is slow and can loop.
				continue;
			} else
				throw new Error( "Unable to build a street!" );
		}

		tidyUpRoads();

		for (a in arteries)
			smoothStreet( a );

		placeBridges();
	}

	private function tidyUpRoads() {
		var segments = new Array<Segment>();
		function cut2segments( street:Street ) {
			var v0:Point = null;
			var v1:Point = street[0];
			for (i in 1...street.length) {
				v0 = v1;
				v1 = street[i];

				// Removing segments which go along the plaza
				if (plaza != null && plaza.shape.contains( v0 ) && plaza.shape.contains( v1 ))
					continue;

				var exists = false;
				for (seg in segments)
					if (seg.start == v0 && seg.end == v1) {
						exists = true;
						break;
					}

				if (!exists)
					segments.push( new Segment( v0, v1 ) );
			}
		}

		for (street in streets)
			cut2segments( street );
		for (road in roads)
			cut2segments( road );

		arteries = [];
		while (segments.length > 0) {
			var seg = segments.pop();

			var attached = false;
			for (a in arteries)
				if (a[0] == seg.end) {
					a.unshift( seg.start );
					attached = true;
					break;
				} else if (a.last() == seg.start) {
					a.push( seg.end );
					attached = true;
					break;
				}

			if (!attached)
				arteries.push( [seg.start, seg.end] );
		}
	}

	private function optimizeJunctions():Void {

		var patchesToOptimize:Array<Patch> =
			citadel == null ? inner : inner.concat( [citadel] );

		var wards2clean:Array<Patch> = [];
		for (w in patchesToOptimize) {
			var index = 0;
			while (index < w.shape.length) {

				var v0:Point = w.shape[index];
				var v1:Point = w.shape[(index + 1) % w.shape.length];

				if (v0 != v1 && Point.distance( v0, v1 ) < 8) {
					for (w1 in patchByVertex( v1 )) if (w1 != w) {
						w1.shape[w1.shape.indexOf( v1 )] = v0;
						wards2clean.push( w1 );
					}

					v0.addEq( v1 );
					v0.scaleEq( 0.5 );

					w.shape.remove( v1 );
				}
				index++;
			}
		}

		// Removing duplicate vertices
		for (w in wards2clean)
			for (i in 0...w.shape.length) {
				var v = w.shape[i];
				var dupIdx;
				while ((dupIdx = w.shape.indexOf( v, i + 1 )) != -1)
					w.shape.splice( dupIdx, 1 );
			}
	}

	private function createWards():Void {
		var unassigned = inner.copy();
		if (plaza != null) {
			plaza.ward = new Market( this, plaza );
			unassigned.remove( plaza );
		}

		// Assigning inner city gate wards
		for (gate in border.gates)
			for (patch in patchByVertex( gate ))
				if (patch.withinCity && patch.ward == null && Random.bool( wall == null ? 0.2 : 0.5 )) {
					patch.ward = new GateWard( this, patch );
					unassigned.remove( patch );
				}

		// Assigning the main temple: an explicit on/off toggle rather than
		// leaving its appearance to WARDS shuffle luck. Still uses
		// Cathedral.rateLocation so it lands as close to the plaza as possible.
		if (templesNeeded && unassigned.length > 0) {
			var rateFunc = Reflect.field( Cathedral, "rateLocation" );
			var bestPatch = unassigned.min( function( patch:Patch )
				return Reflect.callMethod( Cathedral, rateFunc, [this, patch] ) );
			bestPatch.ward = new Cathedral( this, bestPatch );
			unassigned.remove( bestPatch );
		}

		// Assigning parks: an explicit count rather than leaving it to WARDS shuffle luck
		for (i in 0...parksNeeded) {
			if (unassigned.length == 0) break;
			var patch = unassigned.random();
			patch.ward = new Park( this, patch );
			unassigned.remove( patch );
		}

		var wards = WARDS.copy();
		// some shuffling
		for (i in 0...Std.int(wards.length / 10)) {
			var index = Random.int( 0, (wards.length - 1) );
			var tmp = wards[index];
			wards[index] = wards[index + 1];
			wards[index+1] = tmp;
		}

		// Assigning inner city wards
		while (unassigned.length > 0) {
			var bestPatch:Patch = null;

			var wardClass = wards.length > 0 ? wards.shift() : Slum;
			var rateFunc = Reflect.field( wardClass, "rateLocation" );

			if (rateFunc == null)
				do
					bestPatch = unassigned.random()
				while (bestPatch.ward != null);
			else
				bestPatch = unassigned.min( function( patch:Patch ) {
					return patch.ward == null ? Reflect.callMethod( wardClass, rateFunc, [this, patch] ) : Math.POSITIVE_INFINITY;
				} );

			bestPatch.ward = Type.createInstance( wardClass, [this, bestPatch] );

			unassigned.remove( bestPatch );
		}

		// Outskirts
		if (wall != null)
			for (gate in wall.gates) if (!Random.bool( 1 / (nPatches - 5) )) {
				for (patch in patchByVertex( gate ))
					if (patch.ward == null) {
						patch.withinCity = true;
						patch.ward = new GateWard( this, patch );
					}
			}

		// Calculating radius and processing countryside
		cityRadius = 0;
		var farmCandidates:Array<Patch> = [];
		for (patch in patches)
			if (patch.withinCity) {
				// Radius of the city is the farthest point of all wards from the center
				for (v in patch.shape)
					cityRadius = Math.max( cityRadius, v.length );
			} else if (patch.ward == null) {
				if (patch.shape.compactness >= 0.7)
					farmCandidates.push( patch );
				else
					patch.ward = new Ward( this, patch );
			}

		// An explicit count rather than a fixed per-patch chance
		var farmCount = farmsNeeded < farmCandidates.length ? farmsNeeded : farmCandidates.length;
		for (i in 0...farmCount) {
			var patch = farmCandidates.random();
			patch.ward = new Farm( this, patch );
			farmCandidates.remove( patch );
		}
		for (patch in farmCandidates)
			patch.ward = new Ward( this, patch );
	}

	private function buildGeometry()
		for (patch in patches)
			patch.ward.createGeometry();


	public function getNeighbour( patch:Patch, v:Point ):Patch {
		var next = patch.shape.next( v );
		for (p in patches)
			if (p.shape.findEdge( next, v ) != -1)
				return p;
		return null;
	}

	public function getNeighbours( patch:Patch ):Array<Patch>
		return patches.filter( function( p:Patch ) return p != patch && p.shape.borders( patch.shape ) );

	// A ward is "enclosed" if it belongs to the city and
	// it's surrounded by city wards and water
	public function isEnclosed( patch:Patch ):Bool {
		return patch.withinCity && (patch.withinWalls || getNeighbours( patch ).every( function( p:Patch ) return p.withinCity ));
	}
}
