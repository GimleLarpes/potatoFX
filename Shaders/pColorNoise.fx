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
> = 0.05;

uniform int FrameCount < source = "framecount"; >; //Use to vary noise

float3 ColorNoisePass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
	static const float PI = 3.1415927;
	static const float noise_curve = Oklab::get_InvNorm_Factor()*0.002;
	
	float t = FrameCount * 0.2783;
	t %= 10000; //Protect against very large numbers
	float luma = dot(color, float3(0.2126, 0.7152, 0.0722));

	//PRNG 2D - create two uniform noise values and save one DP2ADD
	float seed = dot(texcoord, float2(12.9898, 78.233));
	float uniform_noise1 = frac(sin(seed) * 43758.5453 + t);
	float uniform_noise2 = frac(cos(seed) * 53758.5453 - t);

	//Box-Muller transform
	uniform_noise1 = (uniform_noise1 < 0.0001) ? 0.0001 : uniform_noise1; //fix log(0)
		
	float r = sqrt(-log(uniform_noise1));
	r = (uniform_noise1 < 0.0001) ? PI : r; //fix log(0) - PI happened to be the right answer for uniform_noise == ~ 0.0000517
	float theta = (2.0 * PI) * uniform_noise2;
	
	float gauss_noise1 = r * cos(theta);
	float gauss_noise2 = r * sin(theta);
	float gauss_noise3 = (gauss_noise1 + gauss_noise2) * 0.7;
	float weight = Strength * max(noise_curve, 1.0) / (luma * 2 + 2.0); //Multiply luma by 2 to simulate a wider dynamic range
	                                                                    //divide Strength by 2 to reduce sensitivity and set maximum SNR to 50%.
	color.rgb = color.rgb * (1-weight) + float3(gauss_noise1, gauss_noise2, gauss_noise3) * weight;
	
	return color.rgb;
}

technique ColorNoise <ui_tooltip = "Generates gaussian chroma noise to simulate amplifier noise in digital cameras.";>
{
	pass
	{
		VertexShader = PostProcessVS; PixelShader = ColorNoisePass;
	}
}
