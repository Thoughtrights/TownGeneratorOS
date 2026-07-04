package com.watabou.towngenerator.mapping;

class Palette {

	public var paper	: Int;
	public var light	: Int;
	public var medium	: Int;
	public var dark		: Int;

	public inline function new( paper, light, medium, dark ) {
		this.paper	= paper;
		this.light	= light;
		this.medium	= medium;
		this.dark	= dark;
	}

	public static var DEFAULT	= new Palette( 0xccc5b8, 0x99948a, 0x67635c, 0x1a1917 );
	public static var BLUEPRINT	= new Palette( 0x455b8d, 0x7383aa, 0xa1abc6, 0xfcfbff );
	public static var BW		= new Palette( 0xffffff, 0xcccccc, 0x888888, 0x000000 );
	public static var INK		= new Palette( 0xcccac2, 0x9a979b, 0x6c6974, 0x130f26 );
	public static var NIGHT		= new Palette( 0x000000, 0x402306, 0x674b14, 0x99913d );
	public static var ANCIENT	= new Palette( 0xccc5a3, 0xa69974, 0x806f4d, 0x342414 );
	public static var COLOUR	= new Palette( 0xfff2c8, 0xd6a36e, 0x869a81, 0x4c5950 );
	public static var SIMPLE	= new Palette( 0xffffff, 0x000000, 0x000000, 0x000000 );
	public static var MOJEEB	= new Palette( 0xF7EACA, 0xB8D4B4, 0xA6925E, 0x4A4647 );

	// Numbered palettes (1-9) selectable via the "palette" URL param.
	// Earth-tone / architectural-diagram themes; index 0 keeps MOJEEB.
	public static var TERRACOTTA		= new Palette( 0xEDE0D0, 0xC98F65, 0x8B5E3C, 0x3E2A1E );
	public static var ARCH_BLUEPRINT	= new Palette( 0xE7ECF2, 0x8FA4C0, 0x51678A, 0x1E2A3F );
	public static var SEPIA_INK		= new Palette( 0xEFE6D3, 0xB89A6E, 0x7C5E3C, 0x2B1E14 );
	public static var SAGE_STONE		= new Palette( 0xE8E6DC, 0xA9B29C, 0x707A63, 0x2E332A );
	public static var DESERT_SAND		= new Palette( 0xF2E4C6, 0xD9AE6E, 0xA8783F, 0x4A2F17 );
	public static var CHARCOAL_COPPER	= new Palette( 0xE4E1DC, 0x9C9690, 0x5E5954, 0x1B1815 );
	public static var MOSS_BARK		= new Palette( 0xE5E4D6, 0x8DA377, 0x556B45, 0x24301C );
	public static var CLAY_CREAM		= new Palette( 0xF4E9DC, 0xE0B79A, 0xB37F5C, 0x5A3626 );
	public static var GRAPHITE		= new Palette( 0xF0F0EE, 0xB8B8B4, 0x7A7A76, 0x232320 );

	public static var NUMBERED:Array<Palette> = [
		MOJEEB, TERRACOTTA, ARCH_BLUEPRINT, SEPIA_INK, SAGE_STONE,
		DESERT_SAND, CHARCOAL_COPPER, MOSS_BARK, CLAY_CREAM, GRAPHITE
	];

	public static function fromIndex( index:Int ):Palette
		return NUMBERED[(index >= 0 && index < NUMBERED.length) ? index : 0];
}
