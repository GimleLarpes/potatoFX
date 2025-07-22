///////////////////////////////////////////////////////////////////////////////////
// pFilmSimulation.fx by Gimle Larpes
// A high performance shader for artistic film simulations using HaldCLUTs.
//
// Once source of compatible CLUTs is:
//   https://github.com/cedeber/hald-clut/tree/master/HaldCLUT/Film%20Simulation
///////////////////////////////////////////////////////////////////////////////////

#define P_OKLAB_VERSION_REQUIRE 103
#include "ReShade.fxh"
#include "ReShadeUI.fxh"
#include "Oklab.fxh"

//Version check
#if !defined(__RESHADE__) || __RESHADE__ < 50900
	#error "Outdated ReShade installation - ReShade 5.9+ is required"
#endif


static const float PI = pUtils::PI;
static const float EPSILON = pUtils::EPSILON;
static const float2 TEXEL_SIZE = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);


//LUT
uniform float CLUTIntensity < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "CLUT Intensity";
	ui_tooltip = "Blends between original color and the corrected color";
	ui_category = "Hald CLUT";
> = 1.0;

//Grain
uniform int GrainISO < __UNIFORM_SLIDER_FLOAT1
	ui_min = 12; ui_max = 3200;
	ui_label = "ISO";
	ui_tooltip = "Film speed";
	ui_category = "Grain";
> = 100;
uniform float GrainIntensity < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "Grain fineness";
	ui_tooltip = "How fine the grain is, inversely proportional\nto the sensitivity of the emulsion";
	ui_category = "Grain";
> = 0.5;

//Halation
#if BUFFER_COLOR_SPACE > 1
	static const float BLOOM_CURVE_DEFAULT = 1.0;
	static const float BLOOM_GAMMA_DEFAULT = 1.0;
#else
	static const float BLOOM_CURVE_DEFAULT = 1.0;
	static const float BLOOM_GAMMA_DEFAULT = 0.8;

	#ifndef HDR_ACES_TONEMAP
		#define HDR_ACES_TONEMAP 1
	#endif
#endif
uniform float BloomStrength < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "Halation amount";
	ui_tooltip = "Amount of light bleed from bright objects";
	ui_category = "Halation";
> = 0.4;
uniform float BloomRadius < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.1; ui_max = 1.0;
	ui_label = "Halation radius";
	ui_tooltip = "Controls radius of halation";
	ui_category = "Halation";
> = 0.5;
uniform float BloomCurve < __UNIFORM_SLIDER_FLOAT1
	ui_min = 1.0; ui_max = 5.0;
	ui_label = "Halation curve";
	ui_tooltip = "What parts of the image have light bleed\n1 = linear      5 = brightest parts only";
	ui_category = "Halation";
> = BLOOM_CURVE_DEFAULT;
uniform float BloomGamma < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.1; ui_max = 2;
	ui_label = "Halation gamma";
	ui_tooltip = "Controls shape of Halation";
	ui_category = "Halation";
> = BLOOM_GAMMA_DEFAULT;


//Performance
uniform bool UseApproximateTransforms <
	ui_type = "bool";
	ui_label = "Fast colorspace transform";
	ui_tooltip = "Use less accurate approximations instead of the full transform functions";
	ui_category = "Performance";
> = false;

static const float LUT_WhitePoint = 1.0; //Apply CLUT to entire range - modify LUT function to make this var redundant
#ifndef cLUT_TextureName
	#define cLUT_TextureName "hlut.png"
#endif
#ifndef cLUT_Resolution
	#define cLUT_Resolution 32
#endif
#ifndef cLUT_Format
	#define cLUT_Format RGBA8
#endif
texture cLUT < source = cLUT_TextureName; > { Height = cLUT_Resolution; Width = cLUT_Resolution * cLUT_Resolution; Format = cLUT_Format; };
sampler scLUT { Texture = cLUT; };

texture pBloomTex0 < pooled = true; > { Width = BUFFER_WIDTH/2; Height = BUFFER_HEIGHT/2; Format = RGBA16F; };
sampler spBloomTex0 { Texture = pBloomTex0; AddressU = MIRROR; AddressV = MIRROR; };
texture pBloomTex1 < pooled = true; > { Width = BUFFER_WIDTH/4; Height = BUFFER_HEIGHT/4; Format = RGBA16F; };
sampler spBloomTex1 { Texture = pBloomTex1; AddressU = MIRROR; AddressV = MIRROR; };
#if BUFFER_HEIGHT > 1024
texture pBloomTex2 < pooled = true; > { Width = BUFFER_WIDTH/8; Height = BUFFER_HEIGHT/8; Format = RGBA16F; };
sampler spBloomTex2 { Texture = pBloomTex2; AddressU = MIRROR; AddressV = MIRROR; };
#if BUFFER_HEIGHT > 2048
texture pBloomTex3 < pooled = true; > { Width = BUFFER_WIDTH/16; Height = BUFFER_HEIGHT/16; Format = RGBA16F; };
sampler spBloomTex3 { Texture = pBloomTex3; AddressU = MIRROR; AddressV = MIRROR; };
#if BUFFER_HEIGHT > 4096
texture pBloomTex4 < pooled = true; > { Width = BUFFER_WIDTH/32; Height = BUFFER_HEIGHT/32; Format = RGBA16F; };
sampler spBloomTex4 { Texture = pBloomTex3; AddressU = MIRROR; AddressV = MIRROR; };
#endif
#endif
#endif


////Functions
float3 SampleLinear(float2 texcoord)
{
	float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
	color = (UseApproximateTransforms)
		? Oklab::Fast_DisplayFormat_to_Linear(color)
		: Oklab::DisplayFormat_to_Linear(color);
	return color;
}
float3 SampleLinear(float2 texcoord, bool use_tonemap)
{
	float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
	color = (UseApproximateTransforms)
		? Oklab::Fast_DisplayFormat_to_Linear(color)
		: Oklab::DisplayFormat_to_Linear(color);

	if (use_tonemap && !Oklab::IS_HDR)
	{
		color = Oklab::TonemapInv(color);
	}
    
	return color;
}

float3 RedoTonemap(float3 c)
{
	return (Oklab::IS_HDR) ? c : Oklab::Tonemap(c);
}

float3 ClipBlacks(float3 c)
{
    return float3(max(c.r, 0.0), max(c.g, 0.0), max(c.b, 0.0));
}

float4 KarisAverage(float4 c)
{
	return 1.0 / (1.0 + Oklab::get_Luminance_RGB(c.rgb) * 0.25);
}

float4 HQDownSample(sampler s, float2 texcoord, float2 texel_size)
{
	static const float2 OFFSET[16] = { float2(-0.5, 0.5), float2(0.5, 0.5), float2(-0.5, -0.5), float2(0.5, -0.5),
	                                   float2(-1.5, 1.5), float2(-0.5, 1.5), float2(-1.5, 0.5),
									   float2(1.5, 1.5), float2(0.5, 1.5), float2(1.5, 0.5),
									   float2(-1.5, -1.5), float2(-0.5, -1.5), float2(-1.5, -0.5),
									   float2(1.5, -1.5), float2(0.5, -1.5), float2(1.5, -0.5) };
	static const float WEIGHT[16] = { 0.125, 0.125, 0.125, 0.125,
									  0.041, 0.042, 0.042,
									  0.041, 0.042, 0.042,
									  0.041, 0.042, 0.042,
									  0.041, 0.042, 0.042 };

	float4 color;
	[unroll]
	for (int i = 0; i < 16; ++i)
	{
		color += tex2Dlod(s, float4(texcoord + OFFSET[i] * texel_size, 0.0, 0.0)) * WEIGHT[i];
	}

	return color;
}
float4 HQDownSampleKA(sampler s, float2 texcoord, float2 texel_size)
{
	static const float2 OFFSET[16] = { float2(-0.5, 0.5), float2(0.5, 0.5), float2(-0.5, -0.5), float2(0.5, -0.5),
	                                   float2(-1.5, 1.5), float2(-0.5, 1.5), float2(-1.5, 0.5),
									   float2(1.5, 1.5), float2(0.5, 1.5), float2(1.5, 0.5),
									   float2(-1.5, -1.5), float2(-0.5, -1.5), float2(-1.5, -0.5),
									   float2(1.5, -1.5), float2(0.5, -1.5), float2(1.5, -0.5) };

	float4 samplecolor[16];
	[unroll]
	for (int i = 0; i < 16; ++i)
	{
		samplecolor[i] = tex2Dlod(s, float4(texcoord + OFFSET[i] * texel_size, 0.0, 0.0));
	}

	//Groups
	float4 groups[9];
	groups[0] = 0.125 * (samplecolor[0] + samplecolor[1] + samplecolor[2] + samplecolor[3]);
	groups[1] = 0.015625 * (samplecolor[4] + samplecolor[5] + samplecolor[6] + samplecolor[0]);
	groups[2] = 0.015625 * (samplecolor[5] + samplecolor[8] + samplecolor[0] + samplecolor[1]);
	groups[3] = 0.015625 * (samplecolor[7] + samplecolor[8] + samplecolor[9] + samplecolor[1]);
	groups[4] = 0.015625 * (samplecolor[6] + samplecolor[0] + samplecolor[12] + samplecolor[2]);
	groups[5] = 0.015625 * (samplecolor[10] + samplecolor[11] + samplecolor[12] + samplecolor[2]);
	groups[6] = 0.015625 * (samplecolor[1] + samplecolor[9] + samplecolor[3] + samplecolor[15]);
	groups[7] = 0.015625 * (samplecolor[13] + samplecolor[14] + samplecolor[15] + samplecolor[3]);
	groups[8] = 0.015625 * (samplecolor[2] + samplecolor[3] + samplecolor[11] + samplecolor[14]);

	//Karis average
	[unroll]
	for (int i = 0; i < 9; ++i)
	{
		groups[i] *= KarisAverage(groups[i]);
	}

	return groups[0] + groups[1] + groups[2] + groups[3] + groups[4] + groups[5] + groups[6] + groups[7] + groups[8];
}

float4 HQUpSample(sampler s, float2 texcoord, float2 texel_size, float radius, float weight)
{
	static const float2 OFFSET[9] = { float2(-1.0, 1.0), float2(0.0, 1.0), float2(1.0, 1.0),
	                                  float2(-1.0, 0.0), float2(0.0, 0.0), float2(1.0, 0.0),
									  float2(-1.0, -1.0), float2(0.0, -1.0), float2(1.0, -1.0) };
	static const float WEIGHT[9] = { 0.0625, 0.125, 0.0625,
	                                 0.125, 0.25, 0.125,
									 0.0625, 0.125, 0.0625 };

	float4 color;
	[unroll]
	for (int i = 0; i < 9; ++i)
	{
		color += tex2Dlod(s, float4(texcoord + OFFSET[i] * texel_size * radius, 0.0, 0.0)) * WEIGHT[i];
	}
	color *= weight;

	return color;
}

float3 Apply_LUT(float3 c) //Adapted from LUT.fx by Marty McFly
{
	// TODO: FIX FUNCTION TO WORK WITH CLUTS FROM https://github.com/cedeber/hald-clut/tree/master/HaldCLUT/Film%20Simulation
	static const float EXPANSION_FACTOR = Oklab::INVNORM_FACTOR;
	float3 LUT_coord = c / EXPANSION_FACTOR / LUT_WhitePoint;

	float bounds = max(LUT_coord.x, max(LUT_coord.y, LUT_coord.z));
	
	if (bounds <= 1.0) //Only apply LUT if value is in LUT range
	{
		float2 texel_size = rcp(cLUT_Resolution);
		texel_size.x /= cLUT_Resolution;

		const float3 oc = LUT_coord;
		LUT_coord.xy = (LUT_coord.xy * cLUT_Resolution - LUT_coord.xy + 0.5) * texel_size;
		LUT_coord.z *= (cLUT_Resolution - 1.0);
	
		float lerp_factor = frac(LUT_coord.z);
		LUT_coord.x += floor(LUT_coord.z) * texel_size.y;
		c = lerp(tex2D(scLUT, LUT_coord.xy).rgb, tex2D(scLUT, float2(LUT_coord.x + texel_size.y, LUT_coord.y)).rgb, lerp_factor);

		if (bounds > 0.9 && LUT_WhitePoint != 1.0) //Fade out LUT to avoid banding
		{
			c = lerp(c, oc, 10.0 * (bounds - 0.9));
		}

		return c * LUT_WhitePoint * EXPANSION_FACTOR;
	}

	return c;
}


////Vertex shaders
struct vs2ps
{
	float4 vpos : SV_Position;
	float4 texcoord : TexCoord;
};

vs2ps vs_basic(const uint id)
{
	vs2ps o;
	o.texcoord.x = (id == 2) ? 2.0 : 0.0;
	o.texcoord.y = (id == 1) ? 2.0 : 0.0;
	o.vpos = float4(o.texcoord.xy * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
	return o;
}

vs2ps VS_Bloom(uint id : SV_VertexID)
{   
	vs2ps o = vs_basic(id);
	if (BloomStrength == 0.0)
	{
		o.vpos.xy = 0.0;
	}
	return o;
}


////Passes
//Bloom
float4 HighPassFilter(vs2ps o) : COLOR
{
	float3 color = SampleLinear(o.texcoord.xy, true).rgb;
	float adapted_luminance = Oklab::get_Adapted_Luminance_RGB(RedoTonemap(color), 1.0);

	color *= pow(abs(adapted_luminance), BloomCurve*BloomCurve);
	return float4(color, 1.0); //Scuffed
}
//Downsample
float4 BloomDownS1(vs2ps o) : COLOR
{
	return HQDownSampleKA(spBloomTex0, o.texcoord.xy, 2*TEXEL_SIZE);
}
#if BUFFER_HEIGHT > 1024
float4 BloomDownS2(vs2ps o) : COLOR
{
	return HQDownSample(spBloomTex1, o.texcoord.xy, 4*TEXEL_SIZE);
}
#if BUFFER_HEIGHT > 2048
float4 BloomDownS3(vs2ps o) : COLOR
{
	return HQDownSample(spBloomTex2, o.texcoord.xy, 8*TEXEL_SIZE);
}
#if BUFFER_HEIGHT > 4096
float4 BloomDownS4(vs2ps o) : COLOR
{
	return HQDownSample(spBloomTex3, o.texcoord.xy, 16*TEXEL_SIZE);
}
//Upsample
float4 BloomUpS3(vs2ps o) : COLOR
{
	return HQUpSample(spBloomTex4, o.texcoord.xy, 32*TEXEL_SIZE, BloomRadius, BloomRadius);
}
#endif
float4 BloomUpS2(vs2ps o) : COLOR
{
	return HQUpSample(spBloomTex3, o.texcoord.xy, 16*TEXEL_SIZE, BloomRadius, BloomRadius);
}
#endif
float4 BloomUpS1(vs2ps o) : COLOR
{
	return HQUpSample(spBloomTex2, o.texcoord.xy, 8*TEXEL_SIZE, BloomRadius, BloomRadius);
}
#endif
float4 BloomUpS0(vs2ps o) : COLOR
{
	float4 color = HQUpSample(spBloomTex1, o.texcoord.xy, 4*TEXEL_SIZE, BloomRadius, BloomRadius);
	color.rgb = RedoTonemap(color.rgb);

	if (BloomGamma != 1.0)
	{
		color.rgb *= pow(abs(Oklab::get_Luminance_RGB(color.rgb / Oklab::INVNORM_FACTOR)), BloomGamma);
	}
	return color;
}


float3 FilmSimulationPass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	static const float INVNORM_FACTOR = Oklab::INVNORM_FACTOR;
	float3 color = SampleLinear(texcoord).rgb;
	
	////Effects - TODO: IMPLEMENT FILM RESPONSE CURVE
	//Bloom
	if (BloomStrength != 0.0)
	{
		color += (BloomStrength*BloomStrength) * tex2D(spBloomTex0, texcoord).rgb;
	}

	//Noise
	[branch]
	if (GrainIntensity != 0.0)
	{
		static const float NOISE_CURVE = max(INVNORM_FACTOR * 0.025, 1.0);
		static const float3 CHANNEL_NOISE = float3(1.0, 1.0, 1.0);
		//Film sensitivity to color channels, try reading from LUT? - If feeling cursed, store in texcoord.zw and vpos.z (this would break DX9)
		float luminance = Oklab::get_Luminance_RGB(color);

		//White noise
		float noise1 = pUtils::wnoise(texcoord, float2(6.4949, 39.116));
		float noise2 = pUtils::wnoise(texcoord, float2(19.673, 5.5675));
		float noise3 = pUtils::wnoise(texcoord, float2(36.578, 26.118));

		//Box-Muller transform
		float r = sqrt(-2.0 * log(noise1 + EPSILON));
		float theta1 = 2.0 * PI * noise2;
		float theta2 = 2.0 * PI * noise3;

		float3 gauss_noise = float3(r*cos(theta1) * CHANNEL_NOISE[0], r*sin(theta1) * CHANNEL_NOISE[1], r*cos(theta2) * CHANNEL_NOISE[2]);
		
		float weight = (sqrt(GrainISO / 100) * GrainIntensity * 0.01) * NOISE_CURVE / (luminance * (1.0 + rcp(INVNORM_FACTOR)) + 1.0); //Multiply luminance to simulate a wider dynamic range
		color.rgb = ClipBlacks(color.rgb + gauss_noise * weight);
	}

	//LUT
	// is the saturate requred? - Is log-behaviour baked into the cluts (yes) or how will it be one?
	//color = lerp(color, Apply_LUT(Oklab::Saturate_RGB(color)), CLUTIntensity);

	if (!Oklab::IS_HDR) { color = Oklab::Saturate_RGB(color); }
	color = (UseApproximateTransforms)
		? Oklab::Fast_Linear_to_DisplayFormat(color)
		: Oklab::Linear_to_DisplayFormat(color);
	return color.rgb;
}

technique FilmSimulation <ui_tooltip = 
"A high performance shader for artistic film simulations using Hald CLUTs.\n\n"
"(HDR compatible)";>
{
	pass
	{
		VertexShader = VS_Bloom; PixelShader = HighPassFilter; RenderTarget = pBloomTex0;
	}
    
	//Bloom downsample and upsample passes
	#define BLOOM_DOWN_PASS(i) pass { VertexShader = VS_Bloom; PixelShader = BloomDownS##i; RenderTarget = pBloomTex##i; }
	#define BLOOM_UP_PASS(i) pass { VertexShader = VS_Bloom; PixelShader = BloomUpS##i; RenderTarget = pBloomTex##i; ClearRenderTargets = FALSE; BlendEnable = TRUE; BlendOp = 1; SrcBlend = 1; DestBlend = 9; }

	pass
	{
		VertexShader = VS_Bloom; PixelShader = BloomDownS1; RenderTarget = pBloomTex1; 
	}

	#if BUFFER_HEIGHT > 1024
	BLOOM_DOWN_PASS(2)
	#if BUFFER_HEIGHT > 2048
	BLOOM_DOWN_PASS(3)
	#if BUFFER_HEIGHT > 4096
	BLOOM_DOWN_PASS(4)
	
	BLOOM_UP_PASS(3)
	#endif
	BLOOM_UP_PASS(2)
	#endif
	BLOOM_UP_PASS(1)
	#endif
	BLOOM_UP_PASS(0)

    
	pass
	{
		VertexShader = PostProcessVS; PixelShader = FilmSimulationPass;
	}
}
