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

//Shadows midtones highlights
//Shadows
uniform float3 shadow_color < __UNIFORM_COLOR_FLOAT3 //Use this to control shadow color
	ui_label = "Shadow Color";
	ui_tooltip = "Color to which shadows are tinted";
	ui_category = "Shadows";
> = float3(1.0, 1.0, 1.0);
uniform float shadow_saturation < __UNIFORM_SLIDER_FLOAT1
	ui_min = -1.0; ui_max = 1.0;
	ui_label = "Shadow Saturation";
	ui_tooltip = "Saturation adjustment for shadows";
	ui_category = "Shadows";
> = 0.0;
uniform float shadow_brightness < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "Shadow Brightness";
	ui_tooltip = "Brightness adjustment for shadows";
	ui_category = "Shadows";
> = 0.0;
uniform float shadow_threshold < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "Shadow Threshold";
	ui_tooltip = "Threshold for what is considered shadows";
	ui_category = "Shadows";
> = 0.15;
uniform float shadow_curve_slope < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.1; ui_max = 1.0;
	ui_label = "Shadow Curve Slope";
	ui_tooltip = "How steep the transition to shadows is";
	ui_category = "Shadows";
> = 0.5;
//Midtones
uniform float3 midtone_color < __UNIFORM_COLOR_FLOAT3
	ui_label = "Midtone Color";
	ui_tooltip = "Color to which midtones are tinted";
	ui_category = "Midtones";
> = float3(1.0, 1.0, 1.0);
uniform float midtone_saturation < __UNIFORM_SLIDER_FLOAT1
	ui_min = -1.0; ui_max = 1.0;
	ui_label = "Midtone Saturation";
	ui_tooltip = "Saturation adjustment for midtones";
	ui_category = "Midtones";
> = 0.0;
uniform float midtone_brightness < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "Midtone Brightness";
	ui_tooltip = "Brightness adjustment for midtones";
	ui_category = "Midtones";
> = 0.5;
uniform float midtone_point < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "Midtone Point";
	ui_tooltip = "The center point of midtones";
	ui_category = "Midtones";
> = 0.15;
uniform float midtone_width < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "Midtone Width";
	ui_tooltip = "Width of midtones (0 = point, 1 = whole image)";
	ui_category = "Midtones";
> = 0.25;
uniform float midtone_curve_slope < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.1; ui_max = 1.0;
	ui_label = "Midtone Curve Slope";
	ui_tooltip = "How steep the transition to midtones is";
	ui_category = "Midtones";
> = 0.5;
//Highlights
uniform float3 highlight_color < __UNIFORM_COLOR_FLOAT3
	ui_label = "Highlight Color";
	ui_tooltip = "Color to which highlights are tinted";
	ui_category = "Highlights";
> = float3(1.0, 1.0, 1.0);
uniform float highlight_saturation < __UNIFORM_SLIDER_FLOAT1
	ui_min = -1.0; ui_max = 1.0;
	ui_label = "Highlight Saturation";
	ui_tooltip = "Saturation adjustment for highlights";
	ui_category = "Highlights";
> = 0.0;
uniform float highlight_brightness < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "Highlight Brightness";
	ui_tooltip = "Brightness adjustment for highlights";
	ui_category = "Highlights";
> = 1.0;
uniform float highlight_threshold < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "Highlight Threshold";
	ui_tooltip = "Threshold for what is considered highlights";
	ui_category = "Highlights";
> = 0.85;
uniform float highlight_curve_slope < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.1; ui_max = 1.0;
	ui_label = "Highlight Curve Slope";
	ui_tooltip = "How steep the transition to highlights is";
	ui_category = "Highlights";
> = 0.5;



//Performance
uniform bool UseApproximateTransforms <
	ui_type = "bool";
	ui_label = "Fast colorspace transform";
    ui_tooltip = "Use less accurate approximations instead of the full transform functions";
	ui_category = "Performance";
> = false;


float3 ColorsPass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
	static const float PI = 3.1415927;

	//Shadows-midtones-highlighs colors, use polar coordinates because it makes tinting easier
	static const float3 shadow_color = Oklab::RGB_to_LCh(shadow_color);
	static const float3 midtone_color = Oklab::RGB_to_LCh(midtone_color);
	static const float3 highlight_color = Oklab::RGB_to_LCh(highlight_color);
	

	//Do all color-stuff in Oklab color space
	color = (UseApproximateTransforms)
		? Oklab::Fast_DisplayFormat_to_Oklab(color)
		: Oklab::DisplayFormat_to_Oklab(color);
	
	//White balance calculations
	if (color_temperature != 0.0)
	{
		//Color temperature adjustments, how are these calculated?
	}
	if (color_tint != 0.0)
	{
		//Color tint adjustments
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