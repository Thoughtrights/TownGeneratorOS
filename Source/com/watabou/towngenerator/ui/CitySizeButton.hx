package com.watabou.towngenerator.ui;

import com.watabou.coogee.Game;
import com.watabou.utils.Random;

import com.watabou.towngenerator.building.Model;

class CitySizeButton extends Button {

	private var size : Int;

	public function new( label:String, minSize:Int, maxSize:Int ) {
		super( label );

		size = minSize + Std.int( Math.random() * (maxSize - minSize) );

		click.add( onClick );
	}

	private function onClick():Void {
		StateManager.pullParams();
		// Overwrite only size and seed; keep everything else the user has set
		StateManager.size = size;
		StateManager.seed = Random.getSeed();
		StateManager.pushParams();

		new Model( StateManager.size,
		    	   StateManager.seed,
		    	   StateManager.wall,
			   StateManager.plaza,
			   StateManager.citadel,
			   StateManager.parks,
			   StateManager.farms,
			   StateManager.temples,
			   StateManager.river,
			   StateManager.coast,
			   StateManager.moat );

		Game.switchScene( TownScene );
	}
}
