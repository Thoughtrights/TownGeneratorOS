package com.watabou.towngenerator.building;

import Type;
import openfl.errors.Error;
import openfl.geom.Point;

import com.watabou.geom.Polygon;
import com.watabou.geom.Segment;
import com.watabou.geom.Voronoi;
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
	private var coastDir	: Point;		// unit vector pointing out to sea
	private var shoreDist	: Float = 0;	// projection of the shoreline along coastDir

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
		coastDir = null;

		if (coastNeeded)
			buildCoast();
	}

	// Projection of a point onto the sea-facing axis, measured from the
	// city centre. Larger = further out to sea.
	private inline function seaProj( p:Point ):Float
		return (p.x - center.x) * coastDir.x + (p.y - center.y) * coastDir.y;

	// True if a point lies in open water.
	public function isWater( p:Point ):Bool
		return coastDir != null && seaProj( p ) > shoreDist;

	private function buildCoast():Void {
		// A random direction pointing out to sea
		var a = Random.float() * 2 * Math.PI;
		coastDir = new Point( Math.cos( a ), Math.sin( a ) );

		// Overall city radius, used both to place the shoreline and to size
		// the (finite) sea polygon to the city rather than to an absolute
		// distance the renderer can't handle.
		var cr = 0.0;
		for (p in inner)
			for (v in p.shape) {
				var d = Point.distance( v, center );
				if (d > cr) cr = d;
			}

		// Put the shoreline partway across the seaward side of the city so a
		// broad arc of districts fronts the water. The land mask keeps the
		// water from bleeding between kept buildings, so this can come fairly
		// far in without drowning the built-up gaps.
		shoreDist = cr * (0.58 + Random.float() * 0.12);

		// Flood every patch seaward of the shoreline. The plaza and citadel
		// are always kept dry so the city core stays intact.
		var flooded:Array<Patch> = [];
		for (p in patches)
			if (p != plaza && p != citadel && seaProj( p.shape.centroid ) > shoreDist) {
				p.water = true;
				flooded.push( p );
			}

		// Remove flooded patches so nothing downstream is built on them
		for (p in flooded) {
			patches.remove( p );
			inner.remove( p );
		}
		waterbody = waterbody.concat( flooded );

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
		var wob = cr * 0.16;	// shore wobble amplitude
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

		var poly = pts.copy();
		poly.push( new Point( pts[n].x + coastDir.x * far, pts[n].y + coastDir.y * far ) );
		poly.push( new Point( pts[0].x + coastDir.x * far, pts[0].y + coastDir.y * far ) );
		seaShape = new Polygon( poly );
	}

	// Open the wall where it runs along water (a quay / water-gate) rather
	// than walling off the harbour. Relies on CurtainWall.segments, which
	// tower-building and rendering already respect.
	private function openWaterWallSegments( w:CurtainWall ):Void {
		if (coastDir == null)
			return;

		var shape = w.shape;
		var len = shape.length;
		for (i in 0...len) {
			var v0 = shape[i];
			var v1 = shape[(i + 1) % len];
			var mid = new Point( (v0.x + v1.x) / 2, (v0.y + v1.y) / 2 );

			// Open the seaward-facing arc of the wall (a harbour quay): the
			// edge's outward normal points roughly out to sea and it sits on
			// the seaward side of the city. A thin beach may lie between the
			// quay and the waterline, so we key off facing, not a probe point.
			var out = mid.subtract( center );
			out.normalize( 1 );
			var facing = out.x * coastDir.x + out.y * coastDir.y;
			if (facing > 0.45 && seaProj( mid ) > shoreDist * 0.5)
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
