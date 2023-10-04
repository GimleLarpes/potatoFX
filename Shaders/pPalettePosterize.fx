///////////////////////////////////////////////////////////////////////////////////
// pPalettePosterize.fx by Gimle Larpes
// Posterizes an image to a custom color palette.
///////////////////////////////////////////////////////////////////////////////////

#include "ReShade.fxh"
#include "ReShadeUI.fxh"
#include "Oklab.fxh"
uniform int PaletteType < __UNIFORM_RADIO_INT1
	ui_label = "Color palette";
	ui_tooltip = "Type of color palette to use";
	ui_items = "Monochrome\0Analogous\0Complementary\0";
> = 0;
uniform float3 BaseColor < __UNIFORM_COLOR_FLOAT3
	ui_label = "Base Color";
	ui_tooltip = "Color from which other colors are calculated";
> = float3(0.75, 0.25, 0.25);
uniform int NumColors < __UNIFORM_SLIDER_INT1
	ui_label = "Number of colors";
	ui_min = 2; ui_max = 32;
    ui_tooltip = "Number of colors to posterize to";
> = 8;
uniform float DitheringFactor < __UNIFORM_SLIDER_FLOAT1
	ui_label = "Dithering";
	ui_min = 0.0; ui_max = 1.0;
    ui_tooltip = "Amount of dithering to be applied";
> = 1.0;

uniform int FrameCount < source = "framecount"; >; //use to vary dithering every frame(?)

float3 PosterizeDitherPass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
	const float PI = 3.1415927;
	
	float t = FrameCount * 0.2783;
	t %= 10000; //protect against large numbers

	//do all color-stuff in Oklab color space
	float3 BaseColor = Oklab::sRGB_to_LCh(BaseColor);
	color = Oklab::sRGB_to_LCh(color);

	float luminance = color.r;
	float hue_range;
	
	switch (PaletteType)
	{
		case 0: //Monochrome
		{
			hue_range = 0.0;
		} break;
		case 1: //Analogous
		{
			hue_range = PI/2;
		} break;
		case 2: //Complementary how to do actual complementary colors?
		{
			hue_range = PI*2;
		} break;
	}

	color.r = ceil(color.r * NumColors) / NumColors;
	color.g = BaseColor.g;
	color.b = BaseColor.b + (color.r - 0.490874) * hue_range;
	
	color = Oklab::LCh_to_sRGB(color);
	
	return color.rgb;
}

technique PalettePosterize <ui_tooltip = "Posterizes an image to a custom color palette.";>
{
	pass
	{
		VertexShader = PostProcessVS; PixelShader = PosterizeDitherPass;
	}
}
