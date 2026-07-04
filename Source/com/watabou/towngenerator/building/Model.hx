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
	private var riverHalf	: Float = 0;	// half the river's visible width
	public var bridges		: Array<Array<Point>>;	// each [bankA, bankB] deck endpoints
	public var docks		: Array<Array<Point>>;	// each [base, tip] pier endpoints

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
	}

	// True if a point is under the sea / under the river, individually. Used
	// by the renderer to stroke only land-facing water edges so the two
	// bodies read as one merged surface where they meet.
	public function inSea( p:Point ):Bool
		return coastDir != null && seaProj( p ) > shoreDist;

	public function inRiver( p:Point ):Bool
		return riverPath != null && distToPath( p, riverPath ) < riverHalf;

	// A cluster of short piers reaching into the water near the city — its
	// harbour. Anchored to shore-facing land vertices closest to the centre
	// and spread out so they don't bunch up.
	private function buildDocks( cr:Float ):Void {
		if (coastDir == null) return;		// harbour is on the open sea

		var shoreVec = coastDir.rotate90();
		var pierLen = Math.max( 8, cr * 0.1 );

		// A row of piers spread along the shore near the city centre. For
		// each, march seaward from near the centre to find the waterline,
		// then reach a short way into the water.
		var wanted = 6;
		for (k in 0...wanted) {
			var t = (k - (wanted - 1) / 2) * cr * 0.16 + (Random.float() - 0.5) * cr * 0.05;
			var from = new Point( center.x + shoreVec.x * t, center.y + shoreVec.y * t );

			var waterline:Point = null;
			var hitWater = false;
			var stepN = 60;
			for (s in 0...stepN) {
				var d = s / stepN * cr * 2.0;
				var p = new Point( from.x + coastDir.x * d, from.y + coastDir.y * d );
				if (isWater( p )) { hitWater = true; break; }
				waterline = p;
			}
			// Only a real shoreline near the city gets a pier (skip rays that
			// never reach the water or meet it far out past the harbour).
			if (!hitWater || waterline == null || Point.distance( waterline, center ) > cr * 1.25)
				continue;

			var jitter = (Random.float() - 0.5) * pierLen * 0.4;
			var tip = new Point(
				waterline.x + coastDir.x * pierLen + shoreVec.x * jitter,
				waterline.y + coastDir.y * pierLen + shoreVec.y * jitter
			);
			docks.push( [waterline, tip] );
		}
	}

	// Projection of a point onto the sea-facing axis, measured from the
	// city centre. Larger = further out to sea.
	private inline function seaProj( p:Point ):Float
		return (p.x - center.x) * coastDir.x + (p.y - center.y) * coastDir.y;

	// True if a point lies in open water (sea or river).
	public function isWater( p:Point ):Bool {
		if (coastDir != null && seaProj( p ) > shoreDist)
			return true;
		if (riverPath != null && distToPath( p, riverPath ) < riverHalf)
			return true;
		return false;
	}

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
		// broad arc of districts fronts the water. The land mask keeps the
		// water from bleeding between kept buildings, so this can come fairly
		// far in without drowning the built-up gaps.
		shoreDist = cr * (0.58 + Random.float() * 0.12);

		// Flood every patch that reaches past the shoreline (any vertex), so
		// no building patch straddles the water. The plaza and citadel are
		// always kept dry so the city core stays intact. The small margin
		// covers the shoreline's cosmetic wobble.
		var margin = cr * 0.12;
		var flooded:Array<Patch> = [];
		for (p in patches)
			if (p != plaza && p != citadel) {
				var wet = false;
				for (v in p.shape)
					if (seaProj( v ) > shoreDist - margin) { wet = true; break; }
				if (wet)
					flooded.push( p );
			}
		for (p in flooded)
			floodPatch( p );

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
		var wob = cr * 0.08;	// shore wobble amplitude (kept small so the
								// flood margin can reliably cover it)
		var n = 40;
		var phase = Random.float() * Math.PI * 2;

		var pts:Array<Point> = [];
		for (i in 0...n + 1) {
			var t = -span + (2 * span) * i / n;
			// gentle multi-frequency wobble, biased slightly landward so the
			// sea always reaches the flooded patches (wards drawn on top hide
			// any overlap onto land)
			var wobble = Math.sin( phase + t / cr * 0.9 ) * wob + Math.sin( phase * 2.3 + t / cr * 2.4 ) * wob * 0.4 - wob * 0.35;
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
		// Visible river width: 4-10x a main street. A cleared corridor a
		// little wider than this keeps buildings off the banks; the ribbon
		// itself is the crisp water down the middle.
		var width = Ward.MAIN_STREET * (4 + Random.float() * 6);
		riverHalf = width / 2;
		var clearHalf = riverHalf + Math.max( 8, cr * 0.05 );

		// General flow direction across the map, and how far the river is
		// offset from the centre: near 0 runs through the city, near +/-cr
		// runs beside it. If there's a coast, aim flow roughly out to sea.
		var flowA = coastDir != null ? Math.atan2( coastDir.y, coastDir.x ) + (Random.float() - 0.5) * 0.6 : Random.float() * 2 * Math.PI;
		var dir = new Point( Math.cos( flowA ), Math.sin( flowA ) );
		var perp = dir.rotate90();
		// The river runs to one side of the city — grazing its edge or well
		// beside it — rather than through the dead centre (which would split
		// the city around the plaza with no way to bridge the halves). A
		// road that meets it gets a bridge. With a coast it stays nearer the
		// city so the estuary reads at the junction.
		var side = Random.bool() ? 1.0 : -1.0;
		var offset = coastDir != null
			? side * (0.4 + Random.float() * 0.35) * cr
			: side * (0.6 + Random.float() * 0.5) * cr;

		var thru = new Point( center.x + perp.x * offset, center.y + perp.y * offset );

		// A few control points from one edge of the map to the other, each
		// nudged sideways for gentle bends.
		var reach = cr * 2.6;
		var n = 6;
		var ctrl:Array<Point> = [];
		for (i in 0...n + 1) {
			var s = -reach + (2 * reach) * i / n;
			var bend = (Random.float() - 0.5) * cr * 0.55;
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
		riverPath = dense;

		// Flood the corridor: any patch that so much as touches it, so no
		// building patch is left straddling (and drawn over) the water.
		var flooded:Array<Patch> = [];
		for (p in patches)
			if (p != plaza && p != citadel) {
				var touches = distToPath( p.shape.centroid, riverPath ) < clearHalf;
				if (!touches)
					for (v in p.shape)
						if (distToPath( v, riverPath ) < clearHalf) { touches = true; break; }
				if (touches)
					flooded.push( p );
			}
		for (p in flooded)
			floodPatch( p );

		riverShape = buildRibbon( riverPath, riverHalf );
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

	// Once the streets exist, drop a bridge deck wherever a road actually
	// crosses the river — so bridges only appear where there's a road, and
	// each deck follows the road across the water.
	public function placeBridges():Void {
		bridges = [];
		if (riverPath == null || arteries == null) return;

		var margin = Math.max( 4, cityR * 0.04 );

		for (a in arteries)
			for (i in 0...a.length - 1) {
				var s0 = a[i];
				var s1 = a[i + 1];
				var sdx = s1.x - s0.x;
				var sdy = s1.y - s0.y;

				// Does this road segment cross the river centreline?
				for (j in 0...riverPath.length - 1) {
					var r0 = riverPath[j];
					var r1 = riverPath[j + 1];
					var t = GeomUtils.intersectLines( s0.x, s0.y, sdx, sdy, r0.x, r0.y, r1.x - r0.x, r1.y - r0.y );
					if (t == null || t.x < 0 || t.x > 1 || t.y < 0 || t.y > 1)
						continue;

					var c = new Point( s0.x + sdx * t.x, s0.y + sdy * t.x );

					var dup = false;
					for (br in bridges) {
						var bm = new Point( (br[0].x + br[1].x) / 2, (br[0].y + br[1].y) / 2 );
						if (Point.distance( bm, c ) < riverHalf * 1.5) { dup = true; break; }
					}
					if (dup) continue;

					// Deck runs along the road, spanning from bank to bank.
					var dir = new Point( sdx, sdy );
					dir.normalize( 1 );
					var fwd = 0.0;
					while (fwd < cityR && inRiver( new Point( c.x + dir.x * fwd, c.y + dir.y * fwd ) )) fwd += 1;
					var back = 0.0;
					while (back < cityR && inRiver( new Point( c.x - dir.x * back, c.y - dir.y * back ) )) back += 1;
					fwd += margin;
					back += margin;

					bridges.push( [
						new Point( c.x + dir.x * fwd, c.y + dir.y * fwd ),
						new Point( c.x - dir.x * back, c.y - dir.y * back )
					] );
					break;
				}
			}
	}

	// Turns a polyline into a closed ribbon polygon of the given half-width
	// by offsetting each vertex along its averaged normal.
	private function buildRibbon( path:Array<Point>, half:Float ):Polygon {
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
			left.push( new Point( path[i].x + nx * half, path[i].y + ny * half ) );
			right.push( new Point( path[i].x - nx * half, path[i].y - ny * half ) );
		}
		right.reverse();
		return new Polygon( left.concat( right ) );
	}

	// Open the wall where it runs along water (a quay / water-gate) rather
	// than walling off the harbour. Relies on CurtainWall.segments, which
	// tower-building and rendering already respect.
	private function openWaterWallSegments( w:CurtainWall ):Void {
		var shape = w.shape;
		var len = shape.length;
		for (i in 0...len) {
			var v0 = shape[i];
			var v1 = shape[(i + 1) % len];
			var mid = new Point( (v0.x + v1.x) / 2, (v0.y + v1.y) / 2 );

			var open = false;

			// Open the seaward-facing arc of the wall (a harbour quay): the
			// edge's outward normal points roughly out to sea and it sits on
			// the seaward side of the city. A thin beach may lie between the
			// quay and the waterline, so we key off facing, not a probe point.
			if (coastDir != null) {
				var out = mid.subtract( center );
				out.normalize( 1 );
				var facing = out.x * coastDir.x + out.y * coastDir.y;
				if (facing > 0.45 && seaProj( mid ) > shoreDist * 0.5)
					open = true;
			}

			// Open where the wall crosses the river (a water-gate).
			if (!open && riverPath != null && distToPath( mid, riverPath ) < riverHalf + 2)
				open = true;

			// ...but never open the stretch where the main wall meets the
			// citadel, or the wall would stop short of the castle instead of
			// wrapping around to connect to it.
			if (open && citadel != null) {
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
		}

		var radius = border.getRadius();
		patches = patches.filter( function( p:Patch ) return p.shape.distance( center ) < radius * 3 );

		gates = border.gates;

		if (citadel != null) {
			var castle = new Castle( this, citadel );
			castle.wall.buildTowers();
			citadel.ward = castle;

			if (citadel.shape.compactness < 0.75)
				throw new Error( "Bad citadel shape!" );

			gates = gates.concat( castle.wall.gates );
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
