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
> = 1;
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
	const float PI = 3.1415927;//REMOVE IF UNUSED
	
	float t = FrameCount * 0.2783;
	t %= 10000; //protect against large numbers
	float luma = dot(color, float3(0.2126, 0.7152, 0.0722));

	//do all colour-stuff in Oklab color space
	
	switch (PaletteType)
	{
		case 0: //Monochrome
		{
			//Something
		} break;
		case 1: //Analogous
		{
			//Something
		} break;
		case 2: //Complementary
		{
			//Something
		} break;
	}

	color.rgb = Oklab::sRGB_to_Linear(color.rgb);//Test Oklab.fxh
	color.rgb = Oklab::Linear_to_sRGB(color.rgb);
	
	//color.rgb = luma;
	
	return color.rgb;
}

technique PalettePosterize <ui_tooltip = "Posterizes an image to a custom color palette.";>
{
	pass
	{
		VertexShader = PostProcessVS; PixelShader = PosterizeDitherPass;
	}
}
