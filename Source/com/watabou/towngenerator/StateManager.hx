package com.watabou.towngenerator;

import com.watabou.utils.Random;

#if html5
import js.Browser;
import js.html.URLSearchParams;
#end

class StateManager {

	private static inline var SIZE = "size";
	private static inline var SEED = "seed";
	private static inline var WALL = "walls";
	private static inline var PLAZA = "markets";
	private static inline var CITADEL = "citadel";
	private static inline var TRANS = "trans";

	public static var size	: Int = 15;
	public static var seed	: Int = -1;
	public static var wall	: Bool= false;
	public static var plaza	: Bool= false;
	public static var citadel : Bool= false;
	public static var trans : Bool= false;

	public static function pullParams() {
		#if html5
		var params = new URLSearchParams( Browser.location.search );
		if (params != null) {
			var size1 = Std.parseInt( params.get( SIZE ) );
			if (size1 != null) size = (size1 >= 6 ? (size1 <= 70 ? size1: 70) : 6);

			var seed1 = Std.parseInt( params.get( SEED ) );
			if (seed1 != null) seed = (seed1 > 0 ? seed1 : -1);

			/* There is no Std.parseBool, so let's use 0/1 */
			var wall1 = Std.parseInt( params.get( WALL ) );
			if (wall1 != null) {
			   if (wall1 == 0) {
			      wall = false;
			   } else if (wall1 == 1) {
			      wall = true;
			   } else {
			      Random.reset();
			      wall = Random.bool();
			   }
		        }
			var plaza1 = Std.parseInt( params.get( PLAZA ) );
			if (plaza1 != null) {
			   if (plaza1 == 0) {
			      plaza = false;
			   } else if (plaza1 == 1) {
			      plaza = true;
			   } else {
			      Random.reset();
			      plaza = Random.bool();
			   }
		        }
			var citadel1 = Std.parseInt( params.get( CITADEL ) );
			if (citadel1 != null) {
			   if (citadel1 == 0) {
			      citadel = false;
			   } else if (citadel1 == 1) {
			      citadel = true;
			   } else {
			      Random.reset();
			      citadel = Random.bool();
			   }
		        }
			var trans1 = Std.parseInt( params.get( TRANS ) );
			if (trans1 != null) {
			   if (trans1 == 1) {
			      trans = true;
			   } else {
			      trans = false;
			   }
		        }
		}
		#end
	}

	public static function pushParams() {
		if (seed == -1) {
			Random.reset();
			seed = Random.getSeed();
		}

		var wallArg = 0;
		if (wall == true) {
		   	wallArg = 1;
		}
		var plazaArg = 0;
		if (plaza == true) {
		   	plazaArg = 1;
		}
		var citadelArg = 0;
		if (citadel == true) {
		   	citadelArg = 1;
		}
		var transArg = 0;
		if (trans == true) {
		   	transArg = 1;
		}

		#if html5
		var loc = Browser.location;
		var search1 = loc.search;
		var search2 = '?$SIZE=$size&$SEED=$seed&$WALL=$wallArg&$PLAZA=$plazaArg&$CITADEL=$citadelArg&$TRANS=$transArg';
		// The next line is not entirely correct, it doesn't take into account hashes
		var url = search1 != "" ? loc.href.split( search1 ).join( search2 ) : loc.href + search2;
		Browser.window.history.replaceState( {size: size, seed: seed, wall: wallArg, plaza: plazaArg, citadel: citadelArg, trans: transArg}, getStateName(), url );
		#end
	}

	private static function getStateName():String {
		return if (size >= 6 && size < 10)
			"Small Town"
		else if (size >= 10 && size < 15)
			"Large Town"
		else if (size >= 15 && size <24)
			"Small City"
		else if (size >= 24 && size < 40)
			"Large City"
		else if (size >= 40)
			"Capital City"
		else
			"Unknown state";
	}
}
