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
> = 0.25;
uniform float ShadowCurveSlope < __UNIFORM_SLIDER_FLOAT1
	ui_min = 2.5; ui_max = 10.0;
	ui_label = "Curve Slope";
	ui_tooltip = "How steep the transition to shadows is";
	ui_category = "Shadows";
> = 7.5;
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
> = 0.75;
uniform float HighlightCurveSlope < __UNIFORM_SLIDER_FLOAT1
	ui_min = 2.5; ui_max = 10.0;
	ui_label = "Curve Slope";
	ui_tooltip = "How steep the transition to highlights is";
	ui_category = "Highlights";
> = 5.0;



//Performance
uniform bool UseApproximateTransforms <
	ui_type = "bool";
	ui_label = "Fast colorspace transform";
    ui_tooltip = "Use less accurate approximations instead of the full transform functions";
	ui_category = "Performance";
> = false;


float get_weight(float v, float t, float s) //maybe faster than a normal smoothstep
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

	//Shadows-midtones-highlighs colors, use polar coordinates because it makes tinting easier
	static const float3 ShadowTintColor = Oklab::RGB_to_LCh(ShadowTintColor);
	static const float3 MidtoneTintColor = Oklab::RGB_to_LCh(MidtoneTintColor);
	static const float3 HighlightTintColor = Oklab::RGB_to_LCh(HighlightTintColor);
	

	//Do all color-stuff in Oklab color space
	color = (UseApproximateTransforms)
		? Oklab::Fast_DisplayFormat_to_Oklab(color)
		: Oklab::DisplayFormat_to_Oklab(color);
	

	////Processing
	//White balance calculations TRY TO MAKE IT WORK IN LAB otherwise, do in LCh and lerp to gel colours instead of this cursedness????
	if (WBTemperature != 0.0 | WBTint != 0.0)
	{
		color.g = color.g - WBTint;
		color.b = (WBTint < 0)
			? color.b + WBTemperature + WBTint
			: color.b + WBTemperature;
	}
	color = Oklab::Oklab_to_LCh(color);

	//const float luminance_norm = Oklab::Normalize(color.r);


	////Global adjustments
	color.g *= (1 + GlobalSaturation);
	color.r *= (1 + GlobalBrightness);

	////Shadows-midtones-highlights
	//Shadows
	//const float shadow_weight = get_weight(luminance_norm, ShadowThreshold, -ShadowCurveSlope);
	//if (shadow_weight != 0.0)
	//{
	//	color.r *= (1 + ShadowBrightness * shadow_weight);
	//	color.g *= (1 + ShadowSaturation * shadow_weight);
	//	color.gb = lerp(color.gb, ShadowTintColor.gb, 5.943 * ShadowTintColor.g * shadow_weight);
	//}
	//Highlights
	//const float highlight_weight = get_weight(luminance_norm, HighlightThreshold, HighlightCurveSlope);
	//if (highlight_weight != 0.0)
	//{
	//	color.r *= (1 + HighlightBrightness * highlight_weight);
	//	color.g *= (1 + HighlightSaturation * highlight_weight);
	//	color.gb = lerp(color.gb, HighlightTintColor.gb, 5.943 * HighlightTintColor.g * highlight_weight);
	//}
	//Midtones
	//const float midtone_weight = max(1 - (shadow_weight + highlight_weight), 0.0);
	//if (midtone_weight != 0.0)
	//{
	//	color.r *= (1 + MidtoneBrightness * midtone_weight);
	//	color.g *= (1 + MidtoneSaturation * midtone_weight);
	//	color.gb = lerp(color.gb, MidtoneTintColor.gb, 5.943 * MidtoneTintColor.g * midtone_weight);
	//}
	
	

	color = (UseApproximateTransforms)
		? Oklab::Fast_LCh_to_DisplayFormat(color)
		: Oklab::LCh_to_DisplayFormat(color);
	
	return color.rgb;
}

technique Colors <ui_tooltip = "Shader with tools for color correction and adjustments.";>
{
	pass
	{
		VertexShader = PostProcessVS; PixelShader = ColorsPass;
	}
}