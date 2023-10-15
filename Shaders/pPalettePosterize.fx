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
	ui_items = "Monochrome\0Analogous\0Complementary\0Triadic\0All colors\0";
	ui_category = "Settings";
> = 2;
uniform float3 BaseColor < __UNIFORM_COLOR_FLOAT3
	ui_label = "Base Color";
	ui_tooltip = "Color from which other colors are calculated";
	ui_category = "Settings";
> = float3(0.52, 0.05, 0.05);
uniform int NumColors < __UNIFORM_SLIDER_INT1
	ui_label = "Number of colors";
	ui_min = 2; ui_max = 16;
    ui_tooltip = "Number of colors to posterize to";
	ui_category = "Settings";
> = 4;
uniform float PaletteBalance < __UNIFORM_SLIDER_FLOAT1
	ui_label = "Palette Balance";
	ui_min = 0.01; ui_max = 2.0;
    ui_tooltip = "Adjusts thresholds for color palette";
	ui_category = "Settings";
> = 1.0;
uniform float DitheringFactor < __UNIFORM_SLIDER_FLOAT1
	ui_label = "Dithering";
	ui_min = 0.0; ui_max = 0.1;
    ui_tooltip = "Amount of dithering to be applied";
	ui_category = "Settings";
> = 0.02;
uniform bool DesaturateHighlights <
	ui_type = "bool";
	ui_label = "Desaturate highlights";
    ui_tooltip = "Creates a less harsh image";
	ui_category = "Settings";
> = false;
uniform float DesaturateFactor < __UNIFORM_SLIDER_FLOAT1
	ui_label = "Desaturate amount";
	ui_min = 0.0; ui_max = 1.0;
    ui_tooltip = "How much to desaturate highlights";
	ui_category = "Settings";
> = 0.75;
uniform bool UseApproximateTransforms <
	ui_type = "bool";
	ui_label = "Fast colorspace transform";
    ui_tooltip = "Use less accurate approximations instead of the full transform functions";
	ui_category = "Performance";
> = false;


//2x2 Bayer
static const int bayer[2 * 2] = {
	0, 2,
	3, 1
};

float3 PosterizeDitherPass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
	static const float PI = 3.1415927;

	//Do all color-stuff in Oklab color space
	static const float3 BaseColor = Oklab::RGB_to_LCh(BaseColor);
	color = (UseApproximateTransforms)
		? Oklab::Fast_DisplayFormat_to_LCh(color)
		: Oklab::DisplayFormat_to_LCh(color);

	//Dithering
	float m;
	if (DitheringFactor != 0.0)
	{
		static const float n = Oklab::InvNorm_Factor;
		const int2 xy = int2(texcoord * ReShade::ScreenSize) % 2.0;
		m = (bayer[xy.x + 2 * xy.y] * 0.25 - 0.5) * n * DitheringFactor;
	}
	else
	{
		m = 0.0;
	}

	float luminance = color.r + m;
	float luminance_norm = Oklab::Normalize(luminance);
	static const float PW_COMPENSATION = rcp(1 + Oklab::InvNorm_Factor - Oklab::HDR_PAPER_WHITE);
	float palette_control = PW_COMPENSATION * PaletteBalance;
	float hue_range;
	float hue_offset = 0.0;
	
	switch (PaletteType)
	{
		case 0: //Monochrome
		{
			hue_range = 0.0;
		} break;
		case 1: //Analogous
		{
			hue_range = PI/2.0;
		} break;
		case 2: //Complementary
		{
			hue_range = PI/2.0;
			hue_offset = (luminance_norm > 0.5 * palette_control)
				? PI*0.75
				: 0.0;
		} break;
		case 3: //Triadic
		{
			hue_range = PI/2.0;
			hue_offset = (luminance_norm > 0.33 * palette_control)
				? PI*0.4167 * floor(luminance_norm * 3.0 / palette_control)
				: 0.0;
		} break;
		case 4: //All colors
		{
			hue_range = PI*2.0;
		} break;
	}

	color.r = ceil(luminance * NumColors) / NumColors;
	color.g = DesaturateHighlights
		? BaseColor.g * (1 - (luminance_norm * luminance_norm) * DesaturateFactor)
		: BaseColor.g;
	color.b = BaseColor.b + (color.r - rcp(NumColors)) * hue_range + hue_offset;
	
	color = (UseApproximateTransforms)
		? Oklab::Fast_LCh_to_DisplayFormat(color)
		: Oklab::LCh_to_DisplayFormat(color);
	
	return color.rgb;
}

technique PalettePosterize <ui_tooltip = 
"Posterizes an image to a custom color palette.\n\n"
"(HDR compatible)";>
{
	pass
	{
		VertexShader = PostProcessVS; PixelShader = PosterizeDitherPass;
	}
}
