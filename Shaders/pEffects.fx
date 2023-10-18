///////////////////////////////////////////////////////////////////////////////////
// pEffects.fx by Gimle Larpes
// A high performance all-in-one shader with the most common effects.
///////////////////////////////////////////////////////////////////////////////////

#include "ReShade.fxh"
#include "ReShadeUI.fxh"
#include "Oklab.fxh"

//Blur
uniform float BlurStrength < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
    ui_label = "Blur amount";
    ui_tooltip = "Amount of blur to apply";
	ui_category = "Blur";
> = 0.0;
uniform int BlurType < __UNIFORM_RADIO_INT1
	ui_label = "Blur type";
	ui_tooltip = "Type of blur to use";
	ui_items = "Gaussian      (high quality)\0Box           (fast)\0";
	ui_category = "Blur";
> = 0;



//Vignette
uniform float VignetteStrength < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
    ui_label = "Vignette amount";
    ui_tooltip = "Amount of vignetting to apply";
	ui_category = "Vignette";
> = 0.0;
uniform float VignetteInnerRadius < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.25;
    ui_label = "Inner radius";
    ui_tooltip = "Inner vignette radius";
	ui_category = "Vignette";
> = 0.25;
uniform float VignetteOuterRadius < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.5;
    ui_label = "Outer radius";
    ui_tooltip = "Outer vignette radius";
	ui_category = "Vignette";
> = 0.75;
uniform float VignetteWidth < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 2.0;
    ui_label = "Width";
    ui_tooltip = "Controls the shape of vignette";
	ui_category = "Vignette";
> = 1.0;

//Noise
uniform float NoiseStrength < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
    ui_label = "Noise amount";
    ui_tooltip = "Amount of noise to apply";
	ui_category = "Noise";
> = 0.0;
uniform int NoiseType < __UNIFORM_RADIO_INT1
	ui_label = "Noise type";
	ui_tooltip = "Type of noise to use";
	ui_items = "Film grain\0Color noise\0";
	ui_category = "Noise";
> = 0;



//Performance
uniform bool UseApproximateTransforms <
	ui_type = "bool";
	ui_label = "Fast colorspace transform";
    ui_tooltip = "Use less accurate approximations instead of the full transform functions";
	ui_category = "Performance";
> = false;

uniform int FrameCount < source = "framecount"; >;

//Functions



float3 EffectsPass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
	color = (UseApproximateTransforms)
		? Oklab::Fast_DisplayFormat_to_Linear(color)
		: Oklab::DisplayFormat_to_Linear(color);
	
	static const float PI = 3.1415927;
	static const float INVNORM_FACTOR = Oklab::INVNORM_FACTOR;
	
    ////Effects
    //Blur
    //Box blur



    //Vignette
    if (VignetteStrength != 0.0)
    {
        float weight = clamp((length(float2(abs(texcoord.x - 0.5) * rcp(VignetteWidth), abs(texcoord.y - 0.5))) - VignetteInnerRadius) / (VignetteOuterRadius - VignetteInnerRadius), 0.0, 1.0);
        color.rgb *= 1 - VignetteStrength * weight;
    }


    //Noise
    if (NoiseStrength != 0.0)
    {
        static const float NOISE_CURVE = max(INVNORM_FACTOR * 0.025, 1.0);
        static const float SPEED = (NoiseType == 1) ? 60 : 1;
	
	    float t = FrameCount * 0.456035462415 * SPEED;
	    t %= 263; t += 37;
	    float luma = dot(color, float3(0.2126, 0.7152, 0.0722));

	    float seed = dot(texcoord, float2(12.9898, 78.233));
	    float uniform_noise1 = frac(sin(seed) * 413.458333333 * t);
	    float uniform_noise2 = frac(cos(seed) * 524.894736842 * t);

	    uniform_noise1 = (uniform_noise1 < 0.0001) ? 0.0001 : uniform_noise1; //fix log(0)
		
	    float r = sqrt(-log(uniform_noise1));
	    r = (uniform_noise1 < 0.0001) ? PI : r; //fix log(0) - PI happened to be the right answer for uniform_noise == ~ 0.0000517
	    float theta = 2.0 * PI * uniform_noise2;
	
	    float gauss_noise1 = r * cos(theta);
	    float weight = NoiseStrength * NOISE_CURVE / (luma * (1 + rcp(INVNORM_FACTOR)) + 2.0); //Multiply luma to simulate a wider dynamic range

	    if (NoiseType == 1)
        {   //Color noise
            float gauss_noise2 = r * sin(theta);
	        float gauss_noise3 = (gauss_noise1 + gauss_noise2) * 0.7;
            color.rgb = color.rgb * (1-weight) + float3(gauss_noise1, gauss_noise2, gauss_noise3) * weight;
        }
        else
        {   //Film grain
            color.rgb = Oklab::Saturate_RGB(color.rgb * (1-weight) + (gauss_noise1 - 0.5) * weight);
        }
    }

	
	color = (UseApproximateTransforms)
		? Oklab::Fast_Linear_to_DisplayFormat(color)
		: Oklab::Linear_to_DisplayFormat(color);
	return color.rgb;
}

technique Effects <ui_tooltip = 
"A high performance all-in-one shader with the most common effects.\n\n"
"(HDR compatible)";>
{
	pass
	{
		VertexShader = PostProcessVS; PixelShader = EffectsPass;
	}
}
