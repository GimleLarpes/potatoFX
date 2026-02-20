///////////////////////////////////////////////////////////////////////////////////
// pFilmSimulation.fx by Gimle Larpes
// A high performance shader for artistic film simulations using HaldCLUTs.
//
// HaldCLUTS are assumed to be in sRGB color space.
//
// Once source of compatible HaldCLUTs is:
//   https://github.com/cedeber/hald-clut/tree/master/HaldCLUT/Film%20Simulation
///////////////////////////////////////////////////////////////////////////////////

#define P_OKLAB_VERSION_REQUIRE 105
#include "ReShade.fxh"
#include "ReShadeUI.fxh"
#include "Oklab.fxh"

//Version check
#if !defined(__RESHADE__) || __RESHADE__ < 50900
	#error "Outdated ReShade installation - ReShade 5.9+ is required"
#endif


static const float PI = pUtils::PI;
static const float EPSILON = pUtils::EPSILON;
static const float INVNORM_FACTOR = Oklab::INVNORM_FACTOR;
static const float2 TEXEL_SIZE = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);

//LUT
uniform float CLUTIntensity < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "CLUT Intensity";
	ui_tooltip = "Blends between original color and the corrected color";
	ui_category = "Hald CLUT";
> = 1.0;
#if BUFFER_COLOR_SPACE > 1
	uniform float CLUTHDRCompensation < __UNIFORM_SLIDER_FLOAT1
		ui_min = 0.1; ui_max = 1.0;
		ui_label = "HDR Compensation";//TODO: FIX TOOLTIP TEXT
		ui_tooltip = "Adjusts what range of brightness cLUT affects, useful when applying SDR LUTs to HDR\n\n(0 = apply cLUT to nothing, 1 = apply cLUT to entire image)";
		ui_category = "Hald CLUT";
	> = 0.5;
#else
	static const float CLUTHDRCompensation = 1.0;
#endif

//Grain
#if  BUFFER_COLOR_SPACE > 1
	static const float DEFAULT_GRAIN_INTENSITY = 0.4;
#else
	static const float DEFAULT_GRAIN_INTENSITY = 0.7;

	#ifndef HDR_ACES_TONEMAP
		#define HDR_ACES_TONEMAP 1
	#endif
#endif
uniform int GrainISO < __UNIFORM_SLIDER_FLOAT1
	ui_min = 12; ui_max = 3200;
	ui_label = "ISO";
	ui_tooltip = "Film speed";
	ui_category = "Grain";
> = 100;
uniform float GrainIntensity < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.1; ui_max = 1.0;
	ui_label = "Grain fineness";
	ui_tooltip = "How fine the grain is, inversely proportional\nto the sensitivity of the emulsion";
	ui_category = "Grain";
> = DEFAULT_GRAIN_INTENSITY;

//Halation
uniform float HaloStrength < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "Halation amount";
	ui_tooltip = "Amount of light bleed from bright objects";
	ui_category = "Halation";
> = 0.3;
uniform float HaloRadius < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.1; ui_max = 1.0;
	ui_label = "Halation radius";
	ui_tooltip = "Controls radius of halation";
	ui_category = "Halation";
> = 0.5;
uniform float HaloCurve < __UNIFORM_SLIDER_FLOAT1
	ui_min = 1.0; ui_max = 5.0;
	ui_label = "Halation curve";
	ui_tooltip = "What parts of the image have light bleed\n\n(1 = linear      5 = brightest parts only)";
	ui_category = "Halation";
> = 1.0;
uniform float3 HaloColor < __UNIFORM_COLOR_FLOAT3
	ui_label = "Halation tint";
	ui_tooltip = "How prone different colors are to halation";
	ui_category = "Halation";
> = float3(1.0, 0.25, 0.125);


//Performance
uniform bool UseApproximateTransforms <
	ui_type = "bool";
	ui_label = "Fast colorspace transform";
	ui_tooltip = "Use less accurate approximations instead of the full transform functions";
	ui_category = "Performance";
> = false;


#ifndef cLUT_TextureName
	#define cLUT_TextureName "Kodak Ektar 100.png"
#endif
#ifndef cLUT_Level
	#define cLUT_Level 16
#endif
#ifndef cLUT_Format
	#define cLUT_Format RGBA8
#endif

texture cLUT < source = cLUT_TextureName; > { Height = cLUT_Level*cLUT_Level*cLUT_Level; Width = cLUT_Level*cLUT_Level*cLUT_Level; Format = cLUT_Format; };
sampler scLUT { Texture = cLUT; AddressU = CLAMP; AddressV = CLAMP; AddressW = CLAMP; MagFilter = LINEAR; MinFilter = LINEAR; MipFilter = LINEAR; };

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
		samplecolor[i] = tex2Dlod(s, float4(texcoord + OFFSET[i] * texel_size, 0.0, 0.0)) * float4(HaloColor, 1.0);
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

float3 Apply_HaldCLUT(float3 c)
{
	float3 oc = c;
	float lut_HDR_adaption = (Oklab::IS_HDR) ? CLUTHDRCompensation * Oklab::get_Adapted_Luminance_RGB(c, INVNORM_FACTOR) : 1.0;
    float3 LUT_coord = c / INVNORM_FACTOR / lut_HDR_adaption;

	static const float2 LUT_OFFSETS[4] = { float2(0.0, 0.0), float2(1.0 , 0.0), float2(0.0, 1.0), float2(1.0, 1.0) };

	float bounds = max(LUT_coord.r, max(LUT_coord.g, LUT_coord.b));
	if (bounds <= 1.0) {
		float cube_resolution = cLUT_Level * cLUT_Level;
		float cube_size = cLUT_Level * cLUT_Level * cLUT_Level;

		float3 scaled = LUT_coord * (cube_resolution - 1);
		float3 floored = floor(scaled);
		float3 fracted = frac(scaled);

		//Sample LUT points to lerp
		float3 lut_samples[4];
		for (int i = 0; i < 4; ++i)//TODO - USE GATHER TO SAVE 1 TEXTURE READ?: float4 tex2DgatherR(scLUT s, uv, int2 offset)
		{
			float red = floored.r + fracted.r;
			float green = floored.g + LUT_OFFSETS[i].x;
			float blue = floored.b + LUT_OFFSETS[i].y;

			// Compute 1D index
			float index = blue * cube_resolution * cube_resolution + green * cube_resolution + red;

			float2 texel_coord = float2(frac(index / cube_size) * cube_size, floor(index / cube_size));
			float2 texel_size = 1.0 / cube_size;
			float2 uv = (texel_coord + 0.5) * texel_size;

			lut_samples[i] = tex2D(scLUT, uv).rgb;
		}

		//Combine samples
		//Blend greens
        scaled = lerp(lut_samples[0], lut_samples[1], fracted.g);
        floored = lerp(lut_samples[2], lut_samples[3], fracted.g);
        //Blend blue
        float3 c = lerp(scaled, floored, fracted.b);

		//Final blending
		if (bounds > 0.9 && lut_HDR_adaption != 1.0)
		{
			c = lerp(c, LUT_coord, 10.0 * (bounds - 0.9));
		}
		return lerp(oc, c * lut_HDR_adaption * INVNORM_FACTOR, CLUTIntensity);
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
	if (HaloStrength == 0.0)
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

	color *= pow(abs(adapted_luminance), HaloCurve*HaloCurve);
	return float4(color, adapted_luminance);
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
	return HQUpSample(spBloomTex4, o.texcoord.xy, 32*TEXEL_SIZE, HaloRadius, HaloRadius);
}
#endif
float4 BloomUpS2(vs2ps o) : COLOR
{
	return HQUpSample(spBloomTex3, o.texcoord.xy, 16*TEXEL_SIZE, HaloRadius, HaloRadius);
}
#endif
float4 BloomUpS1(vs2ps o) : COLOR
{
	return HQUpSample(spBloomTex2, o.texcoord.xy, 8*TEXEL_SIZE, HaloRadius, HaloRadius);
}
#endif
float4 BloomUpS0(vs2ps o) : COLOR
{
	return HQUpSample(spBloomTex1, o.texcoord.xy, 4*TEXEL_SIZE, HaloRadius, HaloRadius);
}


float3 FilmSimulationPass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	static const float TONEMAP_RANGE = (Oklab::IS_HDR) ? INVNORM_FACTOR : Oklab::HDR_TONEMAP_RANGE;
	float3 color = SampleLinear(texcoord, true).rgb;
	
	////Effects
	//HaloBloom
	if (HaloStrength != 0.0)
	{
		color += (HaloStrength*HaloStrength) * tex2D(spBloomTex0, texcoord).rgb;
	}

	//Noise
	float optical_density = sqrt(GrainISO / 100);
	[branch]
	if (GrainIntensity != 0.0)
	{
		static const float NOISE_CURVE = max(TONEMAP_RANGE * 0.025, 1.0);
		float luminance = Oklab::get_Luminance_RGB(color);

		//White noise
		float noise1 = pUtils::wnoise(texcoord, float2(6.4949, 39.116));
		float noise2 = pUtils::wnoise(texcoord, float2(19.673, 5.5675));
		float noise3 = pUtils::wnoise(texcoord, float2(36.578, 26.118));

		//Box-Muller transform
		float r = sqrt(-2.0 * log(noise1 + EPSILON));
		float theta1 = 2.0 * PI * noise2;
		float theta2 = 2.0 * PI * noise3;

		float3 gauss_noise = float3(r*cos(theta1), r*sin(theta1), r*cos(theta2));
		
		float weight = (optical_density * GrainIntensity*GrainIntensity * 0.01) * NOISE_CURVE / (luminance * (1.0 + rcp(TONEMAP_RANGE)) + 1.0); //Multiply luminance to simulate a wider dynamic range
		color.rgb = ClipBlacks(color.rgb + gauss_noise * weight);
	}
	color = RedoTonemap(color);

	//DEBUG LUT STUFF
	/*color.r = texcoord.x;
	color.g = texcoord.y;
	color.b = texcoord.x*texcoord.y;*/

	//LUT
	color = Apply_HaldCLUT(Oklab::Saturate_RGB(color));
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
