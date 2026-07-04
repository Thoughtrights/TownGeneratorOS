package com.watabou.towngenerator.wards;

import openfl.geom.Point;
import com.watabou.towngenerator.building.Patch;
import com.watabou.towngenerator.building.Model;
import com.watabou.towngenerator.building.CurtainWall;

using com.watabou.utils.ArrayExtender;

class Castle extends Ward {

	public var wall	: CurtainWall;

	public function new( model:Model, patch:Patch ) {
		super( model, patch );

		wall = new CurtainWall( true, model, [patch], patch.shape.filter(
			function( v:Point ) return model.patchByVertex( v ).some(
				function( p:Patch ) return !p.withinCity
			)
		) );
	}

	override public function createGeometry() {
		var block = patch.shape.shrinkEq( Ward.MAIN_STREET * 2 );
		// A dropped sub-block surrounded by kept ones reads as a hole in
		// the middle of the keep, so fill stays high (though not 1, to
		// keep a little variation) to make that rare rather than impossible.
		geometry = Ward.createOrthoBuilding( block, Math.sqrt( block.square ) * 4, 0.8 );
	}

	override public inline function getLabel() return "Castle";
}
