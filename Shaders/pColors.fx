///////////////////////////////////////////////////////////////////////////////////
// pColors.fx by Gimle Larpes
// Shader with tools for color correction and grading.
///////////////////////////////////////////////////////////////////////////////////

#include "ReShade.fxh"
#include "ReShadeUI.fxh"
#include "Oklab.fxh"

//White balance
uniform float WBTemperature < __UNIFORM_SLIDER_FLOAT1
	ui_min = -0.25; ui_max = 0.25;
	ui_label = "Temperature";
    ui_tooltip = "Color temperature adjustment (Blue <-> Yellow)";
	ui_category = "White balance";
> = 0.0;
uniform float WBTint < __UNIFORM_SLIDER_FLOAT1
	ui_min = -0.25; ui_max = 0.25;
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


//Advanced color correction
//This contains option to enable advanced colour correction (manipulate by hue, do this in LCh)
uniform bool EnableAdvancedColorCorrection <
	ui_type = "bool";
	ui_label = "Enable Advanced Color Correction";
    ui_tooltip = "Enable advanced color correction (manipulate by hue)";
	ui_category = "Advanced Color Correction";
> = false;


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
	ui_min = 1.0; ui_max = 5.0;
	ui_label = "Curve Slope";
	ui_tooltip = "How steep the transition to shadows is";
	ui_category = "Shadows";
> = 2.5;
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
> = float3(1.0, 0.98, 0.90);
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
	ui_min = 1.0; ui_max = 5.0;
	ui_label = "Curve Slope";
	ui_tooltip = "How steep the transition to highlights is";
	ui_category = "Highlights";
> = 2.5;


//LUT
uniform bool EnableLUT <
	ui_type = "bool";
	ui_label = "Enable LUT";
    ui_tooltip = "Apply a LUT as a final processing step";
	ui_category = "LUT";
> = false;

#if BUFFER_COLOR_SPACE > 1	//Show LUT whitepoint setting if in HDR
uniform float LUT_WhitePoint < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "LUT White point";
	ui_tooltip = "Adjusts what range of brightness LUT affects, useful when applying SDR LUTs to HDR\n\n(0= apply LUT to nothing, 1= apply LUT to entire image)";
	ui_category = "LUT";
> = 1.0;
#else
	static const float LUT_WhitePoint = 1.0;
#endif

#ifndef fLUT_TextureName //Use same name as LUT.fx and MultiLUT.fx for compatability
	#define fLUT_TextureName "lut.png"
#endif
#ifndef fLUT_Resolution
	#define fLUT_Resolution 32.0
#endif
texture LUT < source = fLUT_TextureName; > { Height = fLUT_Resolution; Width = fLUT_Resolution * fLUT_Resolution; Format = RGBA8; };//how to detect if its 8 or 16 bit?hopefully 16 works, what happens if you sample 8 bit as 16 bit?
sampler sLUT { Texture = LUT; };


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

float3 Apply_LUT(float3 c) //Adapted from LUT.fx by Martymcfly/Pascal Glitcher
{
	static const float EXPANSION_FACTOR = Oklab::InvNorm_Factor;
	float2 texel_size = 1.0/fLUT_Resolution;
	texel_size.x /= fLUT_Resolution;
	float3 LUT_coord = Oklab::Normalize(c) / LUT_WhitePoint;

	float bounds = max(LUT_coord.x, max(LUT_coord.y, LUT_coord.z));
	
	if (bounds <= 1.0) //Only apply LUT if value is in LUT range
	{
		float3 oc = LUT_coord;
		LUT_coord.xy = (LUT_coord.xy * fLUT_Resolution - LUT_coord.xy + 0.5) * texel_size;
		LUT_coord.z *= (fLUT_Resolution - 1);
	
		float lerp_factor = frac(LUT_coord.z);
		LUT_coord.x += floor(LUT_coord.z) * texel_size.y;
		c = lerp(tex2D(sLUT, LUT_coord.xy).rgb, tex2D(sLUT, float2(LUT_coord.x + texel_size.y, LUT_coord.y)).rgb, lerp_factor);

		if (bounds > 0.9 && LUT_WhitePoint != 1.0) //Fade out LUT to avoid banding
		{
			c = lerp(c, oc, 10.0 * (bounds - 0.9));
		}

		return c * LUT_WhitePoint * EXPANSION_FACTOR;
	}

	return c;
}



float3 ColorsPass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
	static const float PI = 3.1415927;

	//Do all color-stuff in Oklab color space
	color = (UseApproximateTransforms)
		? Oklab::Fast_DisplayFormat_to_Linear(color)
		: Oklab::DisplayFormat_to_Linear(color);
	float luminance = Oklab::Luminance_RGB(color);
	
	
	////Processing
	color = Oklab::RGB_to_Oklab(color);
	//White balance calculations
	if (WBTemperature != 0.0 | WBTint != 0.0)
	{
		color.g = color.g - WBTint;
		color.b = (WBTint < 0)
			? color.b + WBTemperature + WBTint
			: color.b + WBTemperature;
	}
	static const float PAPER_WHITE = Oklab::HDR_PAPER_WHITE;
	float adapted_luminance = min(4.0 * luminance / (2.0*PAPER_WHITE), 1.0);


	//Global adjustments
	color.r *= (1 + GlobalBrightness);
	color.gb *= (1 + GlobalSaturation);


	////Advanced color correction
	if (EnableAdvancedColorCorrection)
	{
		color = Oklab::Oklab_to_LCh(color);

		//Adjustments by hue
		//Adjustable hue range(width)?
		//Pre-selected hues you can change or a number of colour inputs you can use to select hue?

		//Convert to Oklab
		color = Oklab::LCh_to_Oklab(Oklab::Saturate_LCh(color));
	}


	//Shadows-midtones-highlights colors
	static const float3 ShadowTintColor = Oklab::RGB_to_Oklab(ShadowTintColor) * (1 + GlobalSaturation);
	static const float ShadowTintColorC = Oklab::get_Oklab_Chromacity(ShadowTintColor);
	static const float3 MidtoneTintColor = Oklab::RGB_to_Oklab(MidtoneTintColor) * (1 + GlobalSaturation);
	static const float MidtoneTintColorC = Oklab::get_Oklab_Chromacity(MidtoneTintColor);
	static const float3 HighlightTintColor = Oklab::RGB_to_Oklab(HighlightTintColor) * (1 + GlobalSaturation);
	static const float HighlightTintColorC = Oklab::get_Oklab_Chromacity(HighlightTintColor);

	////Shadows-midtones-highlights
	//Shadows
	float shadow_weight = get_weight(adapted_luminance, ShadowThreshold, -ShadowCurveSlope);
	if (shadow_weight != 0.0)
	{
		color.r *= (1 + ShadowBrightness * shadow_weight);
		color.g = lerp(color.g, ShadowTintColor.g + (1 - ShadowTintColorC) * color.g, shadow_weight) * (1 + ShadowSaturation * shadow_weight);
		color.b = lerp(color.b, ShadowTintColor.b + (1 - ShadowTintColorC) * color.b, shadow_weight) * (1 + ShadowSaturation * shadow_weight);
	}
	//Highlights
	float highlight_weight = get_weight(adapted_luminance, HighlightThreshold, HighlightCurveSlope);
	if (highlight_weight != 0.0)
	{
		color.r *= (1 + HighlightBrightness * highlight_weight);
		color.g = lerp(color.g, HighlightTintColor.g + (1 - HighlightTintColorC) * color.g, highlight_weight) * (1 + HighlightSaturation * highlight_weight);
		color.b = lerp(color.b, HighlightTintColor.b + (1 - HighlightTintColorC) * color.b, highlight_weight) * (1 + HighlightSaturation * highlight_weight);
	}
	//Midtones
	float midtone_weight = max(1 - (shadow_weight + highlight_weight), 0.0);
	if (midtone_weight != 0.0)
	{
		color.r *= (1 + MidtoneBrightness * midtone_weight);
		color.g = lerp(color.g, MidtoneTintColor.g + (1 - MidtoneTintColorC) * color.g, midtone_weight) * (1 + MidtoneSaturation * midtone_weight);
		color.b = lerp(color.b, MidtoneTintColor.b + (1 - MidtoneTintColorC) * color.b, midtone_weight) * (1 + MidtoneSaturation * midtone_weight);
	}
	//Convert to linear
	color = Oklab::Saturate_RGB(Oklab::Oklab_to_RGB(color));


	////LUT
	if (EnableLUT)
	{
		color = Apply_LUT(color);
	}

	color = (UseApproximateTransforms)
		? Oklab::Fast_Linear_to_DisplayFormat(color)
		: Oklab::Linear_to_DisplayFormat(color);
	
	return color.rgb;
}



technique Colors <ui_tooltip = 
"Shader with tools for advanced color correction and grading.\n\n"
"(HDR compatible)";>
{
	pass
	{
		VertexShader = PostProcessVS; PixelShader = ColorsPass;
	}
}