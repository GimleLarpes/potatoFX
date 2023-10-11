///////////////////////////////////////////////////////////////////////////////////
// pColors.fx by Gimle Larpes
// Shader with tools for color correction and adjustments.
///////////////////////////////////////////////////////////////////////////////////

#include "ReShade.fxh"
#include "ReShadeUI.fxh"
#include "Oklab.fxh"

//White balance
uniform float color_temperature < __UNIFORM_SLIDER_FLOAT1
	ui_min = -1.0; ui_max = 1.0;
	ui_label = "Temperature";
    ui_tooltip = "Color temperature adjustment (Blue <-> Yellow)";
	ui_category = "White balance";
> = 0.0;
uniform float color_tint < __UNIFORM_SLIDER_FLOAT1
	ui_min = -1.0; ui_max = 1.0;
	ui_label = "Tint";
    ui_tooltip = "Color tint adjustment (Magenta <-> Green)";
	ui_category = "White balance";
> = 0.0;
//Global adjustments
uniform float saturation < __UNIFORM_SLIDER_FLOAT1
	ui_min = -1.0; ui_max = 1.0;
	ui_label = "Saturation";
    ui_tooltip = "Saturation adjustment";
	ui_category = "Global adjustments";
> = 0.0;
uniform float brightness < __UNIFORM_SLIDER_FLOAT1
	ui_min = -1.0; ui_max = 2.0;
	ui_label = "Brightness";
	ui_tooltip = "Brightness adjustment";
	ui_category = "Global adjustments";
> = 0.0;

//Shadows midtones highlights
//Shadows
uniform float3 shadow_tint < __UNIFORM_COLOR_FLOAT3 //Use this to control shadow color
	ui_label = "Tint";
	ui_tooltip = "Color to which shadows are tinted";
	ui_category = "Shadows";
> = float3(0.0, 0.4, 1.0);
uniform float shadow_saturation < __UNIFORM_SLIDER_FLOAT1
	ui_min = -1.0; ui_max = 1.0;
	ui_label = "Saturation";
	ui_tooltip = "Saturation adjustment for shadows";
	ui_category = "Shadows";
> = 0.0;
uniform float shadow_brightness < __UNIFORM_SLIDER_FLOAT1
	ui_min = -1.0; ui_max = 1.0;
	ui_label = "Brightness";
	ui_tooltip = "Brightness adjustment for shadows";
	ui_category = "Shadows";
> = 0.0;
uniform float shadow_threshold < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "Threshold";
	ui_tooltip = "Threshold for what is considered shadows";
	ui_category = "Shadows";
> = 0.25;
uniform float shadow_curve_slope < __UNIFORM_SLIDER_FLOAT1
	ui_min = 5.0; ui_max = 10.0;
	ui_label = "Curve Slope";
	ui_tooltip = "How steep the transition to shadows is";
	ui_category = "Shadows";
> = 7.5;
//Midtones
uniform float3 midtone_tint < __UNIFORM_COLOR_FLOAT3
	ui_label = "Tint";
	ui_tooltip = "Color to which midtones are tinted";
	ui_category = "Midtones";
> = float3(1.0, 1.0, 1.0);
uniform float midtone_saturation < __UNIFORM_SLIDER_FLOAT1
	ui_min = -1.0; ui_max = 1.0;
	ui_label = "Saturation";
	ui_tooltip = "Saturation adjustment for midtones";
	ui_category = "Midtones";
> = 0.0;
uniform float midtone_brightness < __UNIFORM_SLIDER_FLOAT1
	ui_min = -1.0; ui_max = 1.0;
	ui_label = "Brightness";
	ui_tooltip = "Brightness adjustment for midtones";
	ui_category = "Midtones";
> = 0.0;
//Highlights
uniform float3 highlight_tint < __UNIFORM_COLOR_FLOAT3
	ui_label = "Tint";
	ui_tooltip = "Color to which highlights are tinted";
	ui_category = "Highlights";
> = float3(1.0, 0.9, 0.5);
uniform float highlight_saturation < __UNIFORM_SLIDER_FLOAT1
	ui_min = -1.0; ui_max = 1.0;
	ui_label = "Saturation";
	ui_tooltip = "Saturation adjustment for highlights";
	ui_category = "Highlights";
> = 0.0;
uniform float highlight_brightness < __UNIFORM_SLIDER_FLOAT1
	ui_min = -1.0; ui_max = 1.0;
	ui_label = "Brightness";
	ui_tooltip = "Brightness adjustment for highlights";
	ui_category = "Highlights";
> = 0.0;
uniform float highlight_threshold < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "Threshold";
	ui_tooltip = "Threshold for what is considered highlights";
	ui_category = "Highlights";
> = 0.75;
uniform float highlight_curve_slope < __UNIFORM_SLIDER_FLOAT1
	ui_min = 5.0; ui_max = 10.0;
	ui_label = "Curve Slope";
	ui_tooltip = "How steep the transition to highlights is";
	ui_category = "Highlights";
> = 7.5;



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
	static const float3 shadow_tint = Oklab::RGB_to_LCh(shadow_tint);
	static const float3 midtone_tint = Oklab::RGB_to_LCh(midtone_tint);
	static const float3 highlight_tint = Oklab::RGB_to_LCh(highlight_tint);
	

	//Do all color-stuff in Oklab color space
	color = (UseApproximateTransforms)
		? Oklab::Fast_DisplayFormat_to_Oklab(color)
		: Oklab::DisplayFormat_to_Oklab(color);
	

	////Processing
	//White balance calculations
	if (color_temperature != 0.0 | color_tint != 0.0)
	{
		color.b = lerp(color.b, sign(color_temperature + color_tint) * 0.25, abs(color_temperature + min(color_tint, 0.0)) * 0.35); // 0.7/2
	}
	if (color_tint != 0.0)
	{
		color.g = lerp(color.b, sign(-color_tint)*0.25, abs(color_tint * 0.7));
	}
	color = Oklab::Oklab_to_LCh(color);

	const float relative_luminance = Oklab::Normalize(color.r);

	////Global adjustments
	color.g *= (1 + saturation);
	color.r *= (1 + brightness);

	////Shadows-midtones-highlights
	//Shadows
	const float shadow_weight = get_weight(relative_luminance, shadow_threshold, -shadow_curve_slope);
	if (shadow_weight != 0.0)
	{
		color.r *= (1 + shadow_brightness * shadow_weight);
		color.g *= (1 + (shadow_saturation + shadow_tint.g) * shadow_weight);
		color.b = pUtils::clerp(color.b, shadow_tint.b, shadow_tint.g * shadow_weight);
	}

	//Highlights
	const float highlight_weight = get_weight(relative_luminance, highlight_threshold, highlight_curve_slope);
	if (highlight_weight != 0.0)
	{
		color.r *= (1 + highlight_brightness * highlight_weight);
		color.g *= (1 + (highlight_saturation + highlight_tint.g) * highlight_weight);
		color.b = pUtils::clerp(color.b, highlight_tint.b, highlight_tint.g * highlight_weight);
	}

	//Midtones
	const float midtone_weight = max(1 - (shadow_weight + highlight_weight), 0.0);
	if (midtone_weight != 0.0)
	{
		color.r *= (1 + midtone_brightness * midtone_weight);
		color.g *= (1 + (midtone_saturation + highlight_tint.g) * midtone_weight);
		color.b = pUtils::clerp(color.b, midtone_tint.b, midtone_tint.g * midtone_weight);
	}
	
	

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