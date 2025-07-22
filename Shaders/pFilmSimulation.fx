///////////////////////////////////////////////////////////////////////////////////
// pFilmSimulation.fx by Gimle Larpes
// A high performance shader for artistic film simulations using HaldCLUTs.
//
// HaldCLUTS are assumed to be in sRGB color space.
//
// Once source of compatible HaldCLUTs is:
//   https://github.com/cedeber/hald-clut/tree/master/HaldCLUT/Film%20Simulation
///////////////////////////////////////////////////////////////////////////////////

#define P_OKLAB_VERSION_REQUIRE 104
#include "ReShade.fxh"
#include "ReShadeUI.fxh"
#include "Oklab.fxh"

//Version check
#if !defined(__RESHADE__) || __RESHADE__ < 50900
	#error "Outdated ReShade installation - ReShade 5.9+ is required"
#endif


static const float PI = pUtils::PI;
static const float EPSILON = pUtils::EPSILON;


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
	ui_min = 0.1; ui_max = 1.0;
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

//Filmic base and shoulder
#if BUFFER_COLOR_SPACE > 1
	static const float FILMIC_BASE_DEFAULT = 0.3;
	static const float FILMIC_SHOULDER_DEFAULT = 0.3;
#else
	static const float FILMIC_BASE_DEFAULT = 0.3;
	static const float FILMIC_SHOULDER_DEFAULT = 0.3;
#endif
uniform float FilmicBaseWidth < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 0.4;
	ui_label = "Base width";
	ui_tooltip = "Controls width of the base+fog region of the filmic response curve";
	ui_category = "Filmic Curve";
> = FILMIC_BASE_DEFAULT;
uniform float FilmicShoulderWidth < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 0.4;
	ui_label = "Shoulder width";
	ui_tooltip = "Controls width of the shoulder region of the filmic response curve";
	ui_category = "Filmic Curve";
> = FILMIC_SHOULDER_DEFAULT;


//Performance
uniform bool UseApproximateTransforms <
	ui_type = "bool";
	ui_label = "Fast colorspace transform";
	ui_tooltip = "Use less accurate approximations instead of the full transform functions";
	ui_category = "Performance";
> = false;


#ifndef cLUT_TextureName
	#define cLUT_TextureName "hald_clut.png"
#endif
#ifndef cLUT_Level
	#define cLUT_Level 12
#endif
#ifndef cLUT_Format
	#define cLUT_Format RGBA8
#endif
static const float LUT_WhitePoint = 1;

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
float3 SampleCLUT(float2 texcoord)
{
	float3 color = tex2D(scLUT, texcoord).rgb;
	color = (UseApproximateTransforms)
		? Oklab::Fast_sRGB_to_Linear(color)
		: Oklab::sRGB_to_Linear(color);
	return color;
}
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

float4 HQDownSample(sampler s, float2 texcoord)
{
	float2 TEXEL_SIZE = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);

	static const float2 OFFSET[13] = { float2(-1.0, 1.0), float2(1.0, 1.0), float2(-1.0, -1.0), float2(1.0, -1.0),
	                                   float2(-2.0, 2.0), float2(0.0, 2.0), float2(2.0, 2.0),
									   float2(-2.0, 0.0), float2(0.0, 0.0), float2(2.0, 0.0),
									   float2(-2.0, -2.0), float2(0.0, -2.0), float2(2.0, -1.0) };
	static const float WEIGHT[13] = { 0.125, 0.125, 0.125, 0.125,
	                                  0.03125, 0.0625, 0.03125,
									  0.0625, 0.125, 0.0625,
									  0.03125, 0.0625, 0.03125 };

	float4 color;
	[unroll]
	for (int i = 0; i < 13; ++i)
	{
		color += tex2D(s, texcoord + OFFSET[i] * TEXEL_SIZE) * WEIGHT[i];
	}
	return color;
}
float4 HQDownSampleKA(sampler s, float2 texcoord)
{
	float2 TEXEL_SIZE = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);
	
	static const float2 OFFSET[13] = { float2(-1.0, 1.0), float2(1.0, 1.0), float2(-1.0, -1.0), float2(1.0, -1.0),
	                                   float2(-2.0, 2.0), float2(0.0, 2.0), float2(2.0, 2.0),
									   float2(-2.0, 0.0), float2(0.0, 0.0), float2(2.0, 0.0),
									   float2(-2.0, -2.0), float2(0.0, -2.0), float2(2.0, -1.0) };

	float4 samplecolor[13];
	[unroll]
	for (int i = 0; i < 13; ++i)
	{
		samplecolor[i] = tex2D(s, texcoord + OFFSET[i] * TEXEL_SIZE);
	}

	//Groups
	float4 groups[5];
	groups[0] = 0.125 * (samplecolor[0] + samplecolor[1] + samplecolor[2] + samplecolor[3]);
	groups[1] = 0.03125 * (samplecolor[4] + samplecolor[5] + samplecolor[7] + samplecolor[8]);
	groups[2] = 0.03125 * (samplecolor[5] + samplecolor[6] + samplecolor[8] + samplecolor[9]);
	groups[3] = 0.03125 * (samplecolor[7] + samplecolor[8] + samplecolor[10] + samplecolor[11]);
	groups[4] = 0.03125 * (samplecolor[8] + samplecolor[9] + samplecolor[11] + samplecolor[12]);

	//Karis average
	groups[0] *= KarisAverage(groups[0]);
	groups[1] *= KarisAverage(groups[1]);
	groups[2] *= KarisAverage(groups[2]);
	groups[3] *= KarisAverage(groups[3]);
	groups[4] *= KarisAverage(groups[4]);

	return groups[0] + groups[1] + groups[2] + groups[3] + groups[4];
}

float4 HQUpSample(sampler s, float2 texcoord, float radius)
{
	float2 TEXEL_SIZE = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);

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
		color += tex2D(s, texcoord + OFFSET[i] * TEXEL_SIZE * radius) * WEIGHT[i];
	}
	return color;
}

float3 Apply_HaldCLUT(float3 c) //Adapted from LUT.fx by Marty McFly
{
	// TODO: FIX FUNCTION TO WORK WITH CLUTS FROM https://github.com/cedeber/hald-clut/tree/master/HaldCLUT/Film%20Simulation
	static const float EXPANSION_FACTOR =  Oklab::INVNORM_FACTOR;
	float3 LUT_coord = c / EXPANSION_FACTOR / LUT_WhitePoint;

	float bounds = max(LUT_coord.x, max(LUT_coord.y, LUT_coord.z));
	
	if (bounds <= 1.0) //Only apply LUT if value is in LUT range -- MAYBE CHANGE THIS LOGIC, SINCE THE SAMPLING PRETTY MUCH JUST CLAMPS IT
	{
		const float3 oc = LUT_coord;
		float2 texel_size = 1.0 / cLUT_Level;
		texel_size.y /= cLUT_Level;
									 //x is segmented in 16 parts, each red segment is 0-1 (also everything is shifted by one pixel to the left for some reason, 
									 // so that first pixel is actually second, and last pixel is first)
									 //y is segmented in 16*16, each green segment is slightly different so that the lowest value is 0=0,n=n, is dependent on both x&y
									 //y is segmented in 16*16, each segment has constant blue color so that nx0=0, nx1=1
		
		//Mostly works, has issues in green channel
		//Rewrite this to affect lutcoord
		float x = texel_size.x * (LUT_coord.r + floor(LUT_coord.g * (cLUT_Level - 1))); //Check that this way of segmenting green is correct
    	float y = texel_size.y * (LUT_coord.g + floor(LUT_coord.b * (cLUT_Level*cLUT_Level - 1)));
		x += 0.5 * texel_size.x*texel_size.y;
		y += 0.5 * texel_size.x*texel_size.y;

		//Original code for cLUT_Level^3 x cLUT_Level^3
		//float cube_resolution = cLUT_Level * cLUT_Level;
    	//float cube_size = rcp(cube_resolution);

		// float cube_size = cLUT_Level*cLUT_Level;
		// float r = LUT_coord.r * (cube_size - 1);
    	// float g =  LUT_coord.g * (cube_size - 1);
    	// float b =  LUT_coord.b * (cube_size - 1);

    	// float x = (r % cube_size) + (g % cLUT_Level) * cube_size;
    	// float y = (b * cLUT_Level) + (g / cLUT_Level);

		c = SampleCLUT(float2(x,y));
		//c = tex2D(scLUT, float2(x,y)).rgb;

		//OWN ATTEMPT - later use bilinear filtering!
		// Calculate n'th square in x: Red is fractional in that square FRACTIONAL X = texel_size.x * LUT_coord.r
		// Blue: Each texel_size.y*texel_size.y is it's own value, lerp between two:  BASE Y = texel_size.y*texel_size.y * floor(LUT_coord.b * (cLUT_Level*cLUT_Level - 1))
		// Green: 0 in 0,0, 1 in 1,1 BASE X = texel_size.x * floor(LUT_coord.g * (cLUT_Level - 1)) // It's prob more complex, since it has a gradient - use fraction
		//     Y FRACTION = texel_size.y*texel_size.y * LUT_coord.g // NOT COMPLETE, AS it seems to step along X in increments of 1 (scale of 0-255), at the end lowest value is 15, at first highest value is 240


		//c = lerp(SampleCLUT(LOWER COORDINATE), SampleCLUT(HIGHER COORDINATE), lerp_factor);

		if (bounds > 0.9 && LUT_WhitePoint != 1.0) //Fade out LUT to avoid banding
		{
			c = lerp(c, oc, 10.0 * (bounds - 0.9));
		}
		c = lerp(oc, c, CLUTIntensity);

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
	return float4(color, adapted_luminance);
}
//Downsample
float4 BloomDownS1(vs2ps o) : COLOR
{
	return HQDownSampleKA(spBloomTex0, o.texcoord.xy);
}
#if BUFFER_HEIGHT > 1024
float4 BloomDownS2(vs2ps o) : COLOR
{
	return HQDownSample(spBloomTex1, o.texcoord.xy);
}
#if BUFFER_HEIGHT > 2048
float4 BloomDownS3(vs2ps o) : COLOR
{
	return HQDownSample(spBloomTex2, o.texcoord.xy);
}
#if BUFFER_HEIGHT > 4096
float4 BloomDownS4(vs2ps o) : COLOR
{
	return HQDownSample(spBloomTex3, o.texcoord.xy);
}
//Upsample
float4 BloomUpS3(vs2ps o) : COLOR
{
	return BloomRadius * HQUpSample(spBloomTex4, o.texcoord.xy, BloomRadius);
}
#endif
float4 BloomUpS2(vs2ps o) : COLOR
{
	return BloomRadius * HQUpSample(spBloomTex3, o.texcoord.xy, BloomRadius);
}
#endif
float4 BloomUpS1(vs2ps o) : COLOR
{
	return BloomRadius * HQUpSample(spBloomTex2, o.texcoord.xy, BloomRadius);
}
#endif
float4 BloomUpS0(vs2ps o) : COLOR
{
	float4 color = BloomRadius * HQUpSample(spBloomTex1, o.texcoord.xy, BloomRadius);
	//color.rgb = RedoTonemap(color.rgb); //Note: This is disabled because the whole workflow is in expanded linear now

	if (BloomGamma != 1.0)
	{
		color.rgb *= pow(abs(Oklab::get_Luminance_RGB(color.rgb / Oklab::INVNORM_FACTOR)), BloomGamma); //Does this work in expanded?
	}
	return color;
}


float3 FilmSimulationPass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	static const float INVNORM_FACTOR = (Oklab::IS_HDR) ? Oklab::INVNORM_FACTOR : Oklab::HDR_TONEMAP_RANGE;
	static const float2 TEXEL_SIZE = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);
	float3 color = SampleLinear(texcoord, true).rgb;
	
	////Effects
	//Bloom
	if (BloomStrength != 0.0)
	{
		color += (BloomStrength*BloomStrength) * tex2D(spBloomTex0, texcoord).rgb;
	}

	//Noise
	float optical_density = sqrt(GrainISO / 100);
	[branch]
	if (GrainIntensity != 0.0)
	{
		static const float NOISE_CURVE = max(INVNORM_FACTOR * 0.025, 1.0);
		static const float3 CHANNEL_NOISE = float3(1.0, 1.0, 1.0);
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
		
		float weight = (optical_density * GrainIntensity * 0.01) * NOISE_CURVE / (luminance * (1.0 + rcp(INVNORM_FACTOR)) + 1.0); //Multiply luminance to simulate a wider dynamic range
		color.rgb = ClipBlacks(color.rgb + gauss_noise * weight);
	}

	//Filmic curve
	// log-behaviour here, somehow? - or just tonemap from expanded range, since thats a filmic curve anyway
	// Y = dD / d(log(H)), Y=response, H=exposure, D=optical density, controls contrast
	// https://www.researchgate.net/figure/The-characteristic-curve-of-a-photographic-film_fig2_264811359


	//DEBUG STUFF
	color.r = texcoord.x;
	color.g = texcoord.y;
	color.b = texcoord.x*texcoord.y;
	color = Apply_HaldCLUT(Oklab::Saturate_RGB(color)); //Debug, get LUT working

	//if (!Oklab::IS_HDR) { color = Oklab::Saturate_RGB(Oklab::Tonemap(color)); } //TEMPORARILY DISABLED TO GET LUT WORKING
	//LUT
	//color = Apply_HaldCLUT(Oklab::Saturate_RGB(color)); //Linearize when sampling LUT
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
