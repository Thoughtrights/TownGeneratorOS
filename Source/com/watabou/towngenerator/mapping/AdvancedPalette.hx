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
	       	      	  	      	  		   0x7FA5B8, 0xAFcada, 0x3C5A68,
							   0x747677, 0xA4A7A8, 0x627A82,
							   0xB7A98D, 0xA3916E, 0x4F453B  );

	// Numbered palettes (1-9) selectable via the "palette" URL param,
	// paired one-to-one with the numbered palettes in Palette.hx.
	// Earth-tone / architectural-diagram themes; index 0 keeps DEFAULT.
	public static var TERRACOTTA		= new AdvancedPalette( 0xD8C3A5, 0x9CAF88,
									0x5C8B93, 0x8FB8BE, 0x35606B,
									0xB09A82, 0x8F7860, 0x6B5642,
									0xC9A77C, 0xA8825A, 0x7A4B32  );
	public static var ARCH_BLUEPRINT	= new AdvancedPalette( 0xC7D2E0, 0x9BB0A8,
									0x3E6FA3, 0x7FA0C7, 0x1F3F63,
									0x9AA8BC, 0x71829B, 0x4C5C77,
									0xB9C6D6, 0x93A4BA, 0x3B4A63  );
	public static var SEPIA_INK		= new AdvancedPalette( 0xDCC9A3, 0xA69B6E,
									0x6E7C63, 0x9AA588, 0x455340,
									0xB2987A, 0x8C7355, 0x63513B,
									0xC6AC80, 0xA48A62, 0x5A4630  );
	public static var SAGE_STONE		= new AdvancedPalette( 0xCED0C1, 0x93A981,
									0x6C93A0, 0x9EBEC7, 0x3E6470,
									0xA8A99B, 0x83846F, 0x5C5D4C,
									0xBFC2AA, 0x9DA187, 0x5C6350  );
	public static var DESERT_SAND		= new AdvancedPalette( 0xE6C98F, 0xB7A25E,
									0x4E8798, 0x94C0C9, 0x2F5762,
									0xC7A876, 0xA0824F, 0x785C34,
									0xDBB983, 0xB5925C, 0x7A5230  );
	public static var CHARCOAL_COPPER	= new AdvancedPalette( 0xC7C1B8, 0x808C74,
									0x3E6E78, 0x74A2AA, 0x1F3F46,
									0x9C9088, 0x746A62, 0x4C443E,
									0xB68F6F, 0x976F4F, 0x7A5236  );
	public static var MOSS_BARK		= new AdvancedPalette( 0xC3C7A8, 0x74905A,
									0x3E6B5E, 0x76A296, 0x1F3F36,
									0x9C9678, 0x746E52, 0x4C4834,
									0xAB9B6E, 0x88794F, 0x4F3E2A  );
	public static var CLAY_CREAM		= new AdvancedPalette( 0xEAD5BC, 0xADAE7E,
									0x6E9CA8, 0xA3C9D0, 0x3E6873,
									0xCBAA8C, 0xA6845F, 0x7C5C3F,
									0xE0BE95, 0xBD9569, 0x8A5A3B  );
	public static var GRAPHITE		= new AdvancedPalette( 0xD6D6D0, 0xA6ACA0,
									0x64788A, 0xA0AEB4, 0x36414E,
									0xB0B0AA, 0x88887F, 0x5C5C54,
									0xC4C4BC, 0xA0A096, 0x504F49  );

	public static var NUMBERED:Array<AdvancedPalette> = [
		DEFAULT, TERRACOTTA, ARCH_BLUEPRINT, SEPIA_INK, SAGE_STONE,
		DESERT_SAND, CHARCOAL_COPPER, MOSS_BARK, CLAY_CREAM, GRAPHITE
	];

	public static function fromIndex( index:Int ):AdvancedPalette
		return NUMBERED[(index >= 0 && index < NUMBERED.length) ? index : 0];
}
