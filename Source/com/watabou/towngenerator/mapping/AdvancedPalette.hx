package com.watabou.towngenerator.mapping;

class AdvancedPalette {

	public var ground 	: Int;
	public var grass 	: Int;
	public var water 	: Int;
	public var water_light 	: Int;
	public var water_dark 	: Int;
	public var road_small 	: Int;
	public var road_medium 	: Int;
	public var road_large 	: Int;
	public var plot_medium	: Int;
	public var plot_dark	: Int;
	public var building 	: Int;

	public inline function new( ground, grass,
	       	      	       	    water, water_light, water_dark,
				    road_small, road_medium, road_large,
				    plot_medium, plot_dark, building) {
				    
		this.ground	    = ground;
		this.grass	    = grass;
		this.water	    = water;
		this.water_light    = water_light;
		this.water_dark	    = water_dark;
		this.road_small	    = road_small;
		this.road_medium    = road_medium;
		this.road_large	    = road_large;
		this.plot_medium    = plot_medium;
		this.plot_dark	    = plot_dark;
		this.building	    = building;
	}

	public static var DEFAULT   = new AdvancedPalette( 0xB0B78D, 0x8DB7A9,
	       	      	  	      	  		   0x3199D6, 0x96D0F2, 0x0B5077,
							   0x747677, 0xA4A7A8, 0x627A82,
							   0xB7A98D, 0xA3916E, 0x4F453B  );

}
