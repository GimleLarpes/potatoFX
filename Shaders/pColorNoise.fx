///////////////////////////////////////////////////////////////////////////////////
// pColorNoise.fx by Gimle Larpes
// Generates gaussian chroma noise to simulate amplifier noise in digital cameras.
//
// Gaussian code is from FilmGrain.fx by Christian Cann Schuldt Jensen ~ CeeJay.dk
///////////////////////////////////////////////////////////////////////////////////

#include "ReShade.fxh"
#include "ReShadeUI.fxh"
#include "Oklab.fxh"

uniform float Strength < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
    ui_tooltip = "Noise strength";
	ui_category = "Settings";
> = 0.05;
uniform bool UseApproximateTransforms <
	ui_type = "bool";
	ui_label = "Fast colorspace transform";
    ui_tooltip = "Use less accurate approximations instead of the full transform functions";
	ui_category = "Performance";
> = false;

uniform int FrameCount < source = "framecount"; >; //Use to vary noise

float3 ColorNoisePass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
	color = (UseApproximateTransforms)
		? Oklab::Fast_DisplayFormat_to_Linear(color)
		: Oklab::DisplayFormat_to_Linear(color);
	
	static const float PI = 3.1415927;
	static const float INVNORM_FACTOR = Oklab::INVNORM_FACTOR;
	static const float NOISE_CURVE = max(INVNORM_FACTOR * 0.025, 1.0);
	
	float t = FrameCount * 0.456035462415;
	t %= 263; t += 37;
	float luma = dot(color, float3(0.2126, 0.7152, 0.0722));

	float seed = dot(texcoord, float2(12.9898, 78.233));
	float uniform_noise1 = frac(sin(seed) * 413.458333333 * t);
	float uniform_noise2 = frac(cos(seed) * 524.894736842 * t);

	//Box-Muller transform
	uniform_noise1 = (uniform_noise1 < 0.0001) ? 0.0001 : uniform_noise1; //fix log(0)
		
	float r = sqrt(-log(uniform_noise1));
	r = (uniform_noise1 < 0.0001) ? PI : r; //fix log(0) - PI happened to be the right answer for uniform_noise == ~ 0.0000517
	float theta = (2.0 * PI) * uniform_noise2;
	
	float gauss_noise1 = r * cos(theta);
	float gauss_noise2 = r * sin(theta);
	float gauss_noise3 = (gauss_noise1 + gauss_noise2) * 0.7;
	float weight = Strength * NOISE_CURVE / (luma * (1 + rcp(INVNORM_FACTOR)) + 2.0); //Multiply luma to simulate a wider dynamic range

	color.rgb = color.rgb * (1-weight) + float3(gauss_noise1, gauss_noise2, gauss_noise3) * weight;
	
	color = (UseApproximateTransforms)
		? Oklab::Fast_Linear_to_DisplayFormat(color)
		: Oklab::Linear_to_DisplayFormat(color);
	return color.rgb;
}

technique ColorNoise <ui_tooltip = 
"Generates gaussian chroma noise to simulate amplifier noise in digital cameras.\n\n"
"(HDR compatible)";>
{
	pass
	{
		VertexShader = PostProcessVS; PixelShader = ColorNoisePass;
	}
}
