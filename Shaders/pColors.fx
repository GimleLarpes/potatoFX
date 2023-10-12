///////////////////////////////////////////////////////////////////////////////////
// pColors.fx by Gimle Larpes
// Shader with tools for color correction and adjustments.
///////////////////////////////////////////////////////////////////////////////////

#include "ReShade.fxh"
#include "ReShadeUI.fxh"
#include "Oklab.fxh"

//White balance
uniform float WBTemperature < __UNIFORM_SLIDER_FLOAT1
	ui_min = -0.5; ui_max = 0.5;
	ui_label = "Temperature";
    ui_tooltip = "Color temperature adjustment (Blue <-> Yellow)";
	ui_category = "White balance";
> = 0.0;
uniform float WBTint < __UNIFORM_SLIDER_FLOAT1
	ui_min = -0.5; ui_max = 0.5;
	ui_label = "Tint";
    ui_tooltip = "Color tint adjustment (Magenta <-> Green)";
	ui_category = "White balance";
> = 0.0;
//Global adjustments
uniform float GlobalSaturation < __UNIFORM_SLIDER_FLOAT1
	ui_min = -1.0; ui_max = 1.0;
	ui_label = "Saturation";
    ui_tooltip = "Saturation adjustment";
	ui_category = "Global adjustments";
> = 0.0;
uniform float GlobalBrightness < __UNIFORM_SLIDER_FLOAT1
	ui_min = -1.0; ui_max = 1.0;
	ui_label = "Brightness";
	ui_tooltip = "Brightness adjustment";
	ui_category = "Global adjustments";
> = 0.0;

//Shadows midtones highlights
//Curve default values
#if BUFFER_COLOR_SPACE == 2		//scRGB
    #undef SHADOW_CT
	#undef SHADOW_CS
	#undef HIGHLIGHT_CT
	#undef HIGHLIGHT_CS
	#define SHADOW_CT 0.1
	#define SHADOW_CS 7.5
	#define HIGHLIGHT_CT 0.15
	#define HIGHLIGHT_CS 7.5
#elif BUFFER_COLOR_SPACE == 3	//HDR10 ST2084
    #undef SHADOW_CT
	#undef SHADOW_CS
	#undef HIGHLIGHT_CT
	#undef HIGHLIGHT_CS
	#define SHADOW_CT 0.03
	#define SHADOW_CS 7.5
	#define HIGHLIGHT_CT 0.05
	#define HIGHLIGHT_CS 7.5
#elif BUFFER_COLOR_SPACE == 4 	//HDR10 HLG
    #undef SHADOW_CT
	#undef SHADOW_CS
	#undef HIGHLIGHT_CT
	#undef HIGHLIGHT_CS
	#define SHADOW_CT 0.05
	#define SHADOW_CS 7.5
	#define HIGHLIGHT_CT 0.1
	#define HIGHLIGHT_CS 7.5
#else 							//Assume SDR
	#undef SHADOW_CT
	#undef SHADOW_CS
	#undef HIGHLIGHT_CT
	#undef HIGHLIGHT_CS
	#define SHADOW_CT 0.25
	#define SHADOW_CS 7.5
	#define HIGHLIGHT_CT 0.75
	#define HIGHLIGHT_CS 5.0
#endif

//Shadows
uniform float3 ShadowTintColor < __UNIFORM_COLOR_FLOAT3
	ui_label = "Tint";
	ui_tooltip = "Color to which shadows are tinted";
	ui_category = "Shadows";
> = float3(0.5, 0.7, 1.0);
uniform float ShadowSaturation < __UNIFORM_SLIDER_FLOAT1
	ui_min = -1.0; ui_max = 1.0;
	ui_label = "Saturation";
	ui_tooltip = "Saturation adjustment for shadows";
	ui_category = "Shadows";
> = 0.0;
uniform float ShadowBrightness < __UNIFORM_SLIDER_FLOAT1
	ui_min = -1.0; ui_max = 1.0;
	ui_label = "Brightness";
	ui_tooltip = "Brightness adjustment for shadows";
	ui_category = "Shadows";
> = 0.0;
uniform float ShadowThreshold < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "Threshold";
	ui_tooltip = "Threshold for what is considered shadows";
	ui_category = "Shadows";
> = SHADOW_CT;
uniform float ShadowCurveSlope < __UNIFORM_SLIDER_FLOAT1
	ui_min = 2.5; ui_max = 10.0;
	ui_label = "Curve Slope";
	ui_tooltip = "How steep the transition to shadows is";
	ui_category = "Shadows";
> = SHADOW_CS;
//Midtones
uniform float3 MidtoneTintColor < __UNIFORM_COLOR_FLOAT3
	ui_label = "Tint";
	ui_tooltip = "Color to which midtones are tinted";
	ui_category = "Midtones";
> = float3(1.0, 1.0, 1.0);
uniform float MidtoneSaturation < __UNIFORM_SLIDER_FLOAT1
	ui_min = -1.0; ui_max = 1.0;
	ui_label = "Saturation";
	ui_tooltip = "Saturation adjustment for midtones";
	ui_category = "Midtones";
> = 0.0;
uniform float MidtoneBrightness < __UNIFORM_SLIDER_FLOAT1
	ui_min = -1.0; ui_max = 1.0;
	ui_label = "Brightness";
	ui_tooltip = "Brightness adjustment for midtones";
	ui_category = "Midtones";
> = 0.0;
//Highlights
uniform float3 HighlightTintColor < __UNIFORM_COLOR_FLOAT3
	ui_label = "Tint";
	ui_tooltip = "Color to which highlights are tinted";
	ui_category = "Highlights";
> = float3(1.0, 0.95, 0.65);
uniform float HighlightSaturation < __UNIFORM_SLIDER_FLOAT1
	ui_min = -1.0; ui_max = 1.0;
	ui_label = "Saturation";
	ui_tooltip = "Saturation adjustment for highlights";
	ui_category = "Highlights";
> = 0.0;
uniform float HighlightBrightness < __UNIFORM_SLIDER_FLOAT1
	ui_min = -1.0; ui_max = 1.0;
	ui_label = "Brightness";
	ui_tooltip = "Brightness adjustment for highlights";
	ui_category = "Highlights";
> = 0.0;
uniform float HighlightThreshold < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "Threshold";
	ui_tooltip = "Threshold for what is considered highlights";
	ui_category = "Highlights";
> = HIGHLIGHT_CT;
uniform float HighlightCurveSlope < __UNIFORM_SLIDER_FLOAT1
	ui_min = 2.5; ui_max = 10.0;
	ui_label = "Curve Slope";
	ui_tooltip = "How steep the transition to highlights is";
	ui_category = "Highlights";
> = HIGHLIGHT_CS;


//Performance
uniform bool UseApproximateTransforms <
	ui_type = "bool";
	ui_label = "Fast colorspace transform";
    ui_tooltip = "Use less accurate approximations instead of the full transform functions";
	ui_category = "Performance";
> = false;


float get_weight(float v, float t, float s) //value, threshold, curve slope
{
	v = (v - t) * s;
	return (v > 1)
		? 1.0
		: (v < 0.0)
			? 0.0
			: v * v * (3 - 2 * v);
}



float3 ColorsPass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
	static const float PI = 3.1415927;

	//Do all color-stuff in Oklab color space
	color = (UseApproximateTransforms)
		? Oklab::Fast_DisplayFormat_to_Oklab(color)
		: Oklab::DisplayFormat_to_Oklab(color);
	

	////Processing
	//White balance calculations
	if (WBTemperature != 0.0 | WBTint != 0.0)
	{
		color.g = color.g - WBTint;
		color.b = (WBTint < 0)
			? color.b + WBTemperature + WBTint
			: color.b + WBTemperature;
	}
	const float luminance_norm = Oklab::Normalize(color.r);

	//Global adjustments
	color.r *= (1 + GlobalBrightness);
	color.gb *= (1 + GlobalSaturation);


	//Shadows-midtones-highlights colors
	static const float3 ShadowTintColor = Oklab::RGB_to_Oklab(ShadowTintColor) * (1 + GlobalSaturation);
	static const float ShadowTintColorC = Oklab::get_Oklab_Chromacity(ShadowTintColor);
	static const float3 MidtoneTintColor = Oklab::RGB_to_Oklab(MidtoneTintColor) * (1 + GlobalSaturation);
	static const float MidtoneTintColorC = Oklab::get_Oklab_Chromacity(MidtoneTintColor);
	static const float3 HighlightTintColor = Oklab::RGB_to_Oklab(HighlightTintColor) * (1 + GlobalSaturation);
	static const float HighlightTintColorC = Oklab::get_Oklab_Chromacity(HighlightTintColor);

	////Shadows-midtones-highlights
	//Shadows
	const float shadow_weight = get_weight(luminance_norm, ShadowThreshold, -ShadowCurveSlope);
	if (shadow_weight != 0.0)
	{
		color.r *= (1 + ShadowBrightness * shadow_weight);
		color.g = lerp(color.g, ShadowTintColor.g + (1 - ShadowTintColorC) * color.g, shadow_weight) * (1 + ShadowSaturation * shadow_weight);
		color.b = lerp(color.b, ShadowTintColor.b + (1 - ShadowTintColorC) * color.b, shadow_weight) * (1 + ShadowSaturation * shadow_weight);
	}
	//Highlights
	const float highlight_weight = get_weight(luminance_norm, HighlightThreshold, HighlightCurveSlope);
	if (highlight_weight != 0.0)
	{
		color.r *= (1 + HighlightBrightness * highlight_weight);
		color.g = lerp(color.g, HighlightTintColor.g + (1 - HighlightTintColorC) * color.g, highlight_weight) * (1 + HighlightSaturation * highlight_weight);
		color.b = lerp(color.b, HighlightTintColor.b + (1 - HighlightTintColorC) * color.b, highlight_weight) * (1 + HighlightSaturation * highlight_weight);
	}
	//Midtones
	const float midtone_weight = max(1 - (shadow_weight + highlight_weight), 0.0);
	if (midtone_weight != 0.0)
	{
		color.r *= (1 + MidtoneBrightness * midtone_weight);
		color.g = lerp(color.g, MidtoneTintColor.g + (1 - MidtoneTintColorC) * color.g, midtone_weight) * (1 + MidtoneSaturation * midtone_weight);
		color.b = lerp(color.b, MidtoneTintColor.b + (1 - MidtoneTintColorC) * color.b, midtone_weight) * (1 + MidtoneSaturation * midtone_weight);
	}
	
	

	color = (UseApproximateTransforms)
		? Oklab::Fast_Oklab_to_DisplayFormat(color)
		: Oklab::Oklab_to_DisplayFormat(color);
	
	return color.rgb;
}

technique Colors <ui_tooltip = "Shader with tools for color correction and adjustments.";>
{
	pass
	{
		VertexShader = PostProcessVS; PixelShader = ColorsPass;
	}
}