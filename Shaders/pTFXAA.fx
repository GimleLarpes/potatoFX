///////////////////////////////////////////////////////////////////////////////////
// pTFXAA.fx by Gimle Larpes
// NOTICE: This software is based on and implements NVIDIA FXAA 3.11 by Timothy Lottes. This software contains source code provided by NVIDIA Corporation.
//
// An anti-aliasing shader using sharpened FXAA and one frame depth TAA. Intended to replace bad TAA and FXAA implementations.
///////////////////////////////////////////////////////////////////////////////////

#define P_OKLAB_VERSION_REQUIRE 103
#include "ReShade.fxh"
#include "ReShadeUI.fxh"
#include "Oklab.fxh"

//Version check - NOT NEEDED NOW
//#if !defined(__RESHADE__) || __RESHADE__ < 50900
//	#error "Outdated ReShade installation - ReShade 5.9+ is required"
//#endif


static const float PI = pUtils::PI;
static const float EPSILON = pUtils::EPSILON;

//Anti-aliasting controls
uniform float FXAA_EDGE_THRESHOLD_MAX < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "Edge detect threshold";
	ui_tooltip = "Contrast threshold for applying AA";
	ui_category = "FXAA";
> = 0.125;
uniform float FXAA_EDGE_THRESHOLD_MIN < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "Darkness threshold";
	ui_tooltip = "Skips AA on darker pixels for better performance";
	ui_category = "FXAA";
> = 0.16;
uniform float FXAA_SUBPIXEL_QUALITY < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "Subpixel quality";
	ui_tooltip = "FXAA maximum edge threshold to use";
	ui_category = "FXAA";
> = 0.75;
uniform float FXAA_SHARPEN_AMOUNT < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
	ui_label = "FXAA sharpening";
	ui_tooltip = "Amount of sharpening applied to FXAA";
	ui_category = "FXAA";
> = 0.7;
uniform bool AADebug <
	ui_type = "bool";
	ui_label = "Debug";
	ui_tooltip = "Displays what areas have anti-aliasing applied to them.\n\nEdge orientation:\nHorizontal - Gold\nVertical   - Blue";
	ui_category = "FXAA";
> = false;


//Performance
uniform bool UseApproximateTransforms <
	ui_type = "bool";
	ui_label = "Fast colorspace transform";
	ui_tooltip = "Use less accurate approximations instead of the full transform functions";
	ui_category = "Performance";
> = false;


texture pTFXAATex < pooled = true; > { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16; };
sampler spTFXAATex { Texture = pTFXAATex; };
texture pTFXAATexC < pooled = true; > { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16; };
sampler spTFXAATexC { Texture = pTFXAATexC; };


//Functions
float3 SampleLinear(float2 texcoord)
{
	float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
	color = (UseApproximateTransforms)
		? Oklab::Fast_DisplayFormat_to_Linear(color)
		: Oklab::DisplayFormat_to_Linear(color);
	return color;
}
float SampleLuminance(float2 texcoord)
{
	return Oklab::get_Luminance_RGB(SampleLinear(texcoord));
}
float3 LinearizeColor(float3 color)
{
	color = (UseApproximateTransforms)
		? Oklab::Fast_DisplayFormat_to_Linear(color)
		: Oklab::DisplayFormat_to_Linear(color);
	return color;
}
float AdaptedLuminance(float v)
{
	return min(2.0 * v / Oklab::HDR_PAPER_WHITE, 1.0);
}


//Vertex shaders
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
vs2ps VS_AA(uint id : SV_VertexID)
{
	vs2ps o = vs_basic(id);
	//if (BlurStrength == 0.0)
	//{
	//	o.vpos.xy = 0.0;
	//}
	return o;
}


////Passes
float4 DisplayPass(vs2ps o) : COLOR
{
	float4 color = tex2D(spTFXAATexC, o.texcoord.xy);
	float4 backbuffer = tex2D(ReShade::BackBuffer, o.texcoord.xy);
	backbuffer.rgb = LinearizeColor(backbuffer.rgb);
	color.rgb = lerp(backbuffer.rgb, color.rgb, color.a);
	//color.rgb = color.a;//DEBUG
	color.a = backbuffer.a;

	color.rgb = (UseApproximateTransforms)
		? Oklab::Fast_Linear_to_DisplayFormat(color.rgb)
		: Oklab::Linear_to_DisplayFormat(color.rgb);
	return color;
}
float4 StoragePass(vs2ps o) : COLOR
{
	float4 color = tex2D(spTFXAATex, o.texcoord.xy); //Input from FXAA, a=1 where drawn
	//Remove old data, somehow
	//color.a = lerp(color.a, 0.0, 0.5); //TEST TAA
	//color.rgb = color.a*color.a;//DEBUG
	//color.rgb = tex2D(spTFXAATexC, o.texcoord.xy).a;
	return color;
}


float4 AAPass(vs2ps o) : SV_Target
{
	static const float2 TEXEL_SIZE = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);
	float4 color = tex2D(ReShade::BackBuffer, o.texcoord.xy);

	static const float JITTER_SCALE = 20.5;
	float2 jitter = frac(pUtils::FrameCount * float2(6.4949, 39.116)); //for actual jitter: (pUtils::FrameCount * 0.01) % 1000
	jitter = (jitter - 0.5) * JITTER_SCALE * TEXEL_SIZE;

	float2 texcoord_clean = o.texcoord.xy;
	o.texcoord.xy += jitter;

	////FXAA - based on https://blog.simonrodriguez.fr/articles/2016/07/implementing_fxaa.html
	//Contrast detect    --    OPTIMIZE THIS STUFF
	static const float3 OFFSET = float3(TEXEL_SIZE.x, TEXEL_SIZE.y, 0.0);
	float lumaC = Oklab::get_Luminance_RGB(LinearizeColor(color.rgb));
	float lumaU = SampleLuminance(o.texcoord.xy + OFFSET.zy);
	float lumaD = SampleLuminance(o.texcoord.xy - OFFSET.zy);
	float lumaL = SampleLuminance(o.texcoord.xy - OFFSET.xz);
	float lumaR = SampleLuminance(o.texcoord.xy + OFFSET.xz);

	float lumaMin = min(lumaC, min(min(lumaD, lumaU), min(lumaL, lumaR)));
	float lumaMax = max(lumaC, max(max(lumaD, lumaU), max(lumaL, lumaR)));

	//Discard if not edge
	float lumaRange = lumaMax - lumaMin;
	[branch]
	if (AdaptedLuminance(lumaRange) < max(FXAA_EDGE_THRESHOLD_MIN*FXAA_EDGE_THRESHOLD_MIN, AdaptedLuminance(lumaMax) * FXAA_EDGE_THRESHOLD_MAX))
	{
		return 0.0;
		//discard;
	}

	//Continue with AA
	float lumaDL = SampleLuminance(o.texcoord.xy - OFFSET.xy);
	float lumaUR = SampleLuminance(o.texcoord.xy + OFFSET.xy);
	float lumaUL = SampleLuminance(o.texcoord.xy - OFFSET.xz + OFFSET.zy);
	float lumaDR = SampleLuminance(o.texcoord.xy + OFFSET.xz - OFFSET.zy);

	//Combine the edge and corner lumas
	float lumaDU = lumaD + lumaU;
	float lumaLR = lumaL + lumaR;

	float lumaLC = lumaDL + lumaUL;
	float lumaDC = lumaDL + lumaDR;
	float lumaRC = lumaDR + lumaUR;
	float lumaUC = lumaUR + lumaUL;

	//Gradient estimation
	float edgeH = abs(-2.0 * lumaL + lumaLC) + abs(-2.0 * lumaC + lumaDU) * 2.0 + abs(-2.0 * lumaR + lumaRC);
	float edgeV = abs(-2.0 * lumaU + lumaUC) + abs(-2.0 * lumaC + lumaLR) * 2.0 + abs(-2.0 * lumaD + lumaDC);
	bool isHorizontal = (edgeH >= edgeV);


	//Edge orientation, step direction
	float luma1;
	float luma2;
	float2 offset;
	float2 step;
	if (isHorizontal)
	{
		luma1 = lumaD;
		luma2 = lumaU;
		step = OFFSET.xz;
		offset = OFFSET.zy;
	}
	else
	{
		luma1 = lumaL;
		luma2 = lumaR;
		step = OFFSET.zy;
		offset = OFFSET.xz;
	}
	float gradient1 = luma1 - lumaC;
	float gradient2 = luma2 - lumaC;
	bool is1Steepest = abs(gradient1) >= abs(gradient2);

	// Gradient in the corresponding direction, normalized. -- DOES THIS STILL WORK IN HDR?
	float gradientScaled = 0.25 * max(abs(gradient1), abs(gradient2));

	//Average luma in the correct direction
	//Select direction, add offset
	float lumaA;
	if (is1Steepest)
	{
    	offset = -offset;
    	lumaA = 0.5 * (luma1 + lumaC);
	}
	else
	{
    	lumaA = 0.5 * (luma2 + lumaC);
	}
	o.texcoord.xy += 0.5 * offset;


	//FIRST ITERATION EXPLORATION
	// Compute UVs to explore on each side of the edge, orthogonally. The QUALITY allows us to step faster.
	float2 uv1 = o.texcoord.xy - step;
	float2 uv2 = o.texcoord.xy + step;

	// Read the lumas at both current extremities of the exploration segment, and compute the delta wrt to the local average luma.
	float lumaEnd1 = SampleLuminance(uv1);
	float lumaEnd2 = SampleLuminance(uv2);
	lumaEnd1 -= lumaA;
	lumaEnd2 -= lumaA;

	//Detect if reached sides of the edge.
	bool reached1 = abs(lumaEnd1) >= gradientScaled;
	bool reached2 = abs(lumaEnd2) >= gradientScaled;
	bool reachedBoth = reached1 && reached2;

	//Continue exploring
	if (!reached1)
	{
    	uv1 -= step;
	}
	if (!reached2)
	{
    	uv2 += step;
	}


	//EXPLORATION
	static const float QUALITY[7] = { 1.5, 2.0, 2.0, 2.0, 2.0, 4.0, 8.0 };
	static const int ITERATIONS = 12;
	// If both sides have not been reached, continue to explore.
	if (!reachedBoth)
	{
		for (int i = 2; i < ITERATIONS && !reachedBoth; i++)
		{
			// If needed, read luma in 1st direction, compute delta.
			if (!reached1)
			{
				lumaEnd1 = SampleLuminance(uv1);
				lumaEnd1 = lumaEnd1 - lumaA;
			}
			// If needed, read luma in opposite direction, compute delta.
			if(!reached2) 
			{
				lumaEnd2 = SampleLuminance(uv2);
				lumaEnd2 = lumaEnd2 - lumaA;
			}
			// If the luma deltas at the current extremities is larger than the local gradient, we have reached the side of the edge.
			reached1 = abs(lumaEnd1) >= gradientScaled;
			reached2 = abs(lumaEnd2) >= gradientScaled;
			reachedBoth = reached1 && reached2;

			// If the side is not reached, we continue to explore in this direction, with a variable quality.
			if (!reached1)
			{
				uv1 -= step * QUALITY[i];
			}
			if (!reached2)
			{
				uv2 += step * QUALITY[i];
			}
		}
	}


	//ESTIMATING OFFSET
	// Compute the distances to each extremity of the edge.
	float distance1;
	float distance2;
	if (isHorizontal)
	{
		distance1 = texcoord_clean.x - uv1.x;
		distance2 = uv2.x - texcoord_clean.x;
	}
	else
	{
		distance1 = texcoord_clean.y - uv1.y;
		distance2 = uv2.y - texcoord_clean.y;
	}

	// In which direction is the extremity of the edge closer ?
	bool isDirection1 = distance1 < distance2;
	float distanceFinal = min(distance1, distance2);

	// Length of the edge.
	float edgeThickness = (distance1 + distance2);

	//Calculate pixelOffset
	float pixelOffset = - distanceFinal / edgeThickness + 0.5;
	
	// Is the luma at center smaller than the local average ?
	bool isLumaCenterSmaller = lumaC < lumaA;

	//Check if the luma at center is smaller than at its neighbour, the delta luma at each end should be positive
	bool correctVariation = ((isDirection1 ? lumaEnd1 : lumaEnd2) < 0.0) != isLumaCenterSmaller;
	float finalOffset = correctVariation ? pixelOffset : 0.0;



	//SUBPIXEL AA
	// Sub-pixel shifting
	// Full weighted average of the luma over the 3x3 neighborhood.
	lumaA = (1.0/12.0) * (2.0 * (lumaDU + lumaLR) + lumaLC + lumaRC);
	// Ratio of the delta between the global average and the center luma, over the luma range in the 3x3 neighborhood.
	float subPixelOffset1 = clamp(abs(lumaA - lumaC) / lumaRange, 0.0, 1.0);
	float subPixelOffset2 = (-2.0 * subPixelOffset1 + 3.0) * subPixelOffset1 * subPixelOffset1;
	// Compute a sub-pixel offset based on this delta.
	float subPixelOffsetFinal = subPixelOffset2 * subPixelOffset2 * FXAA_SUBPIXEL_QUALITY;

	// Pick the biggest of the two offsets.
	finalOffset = max(finalOffset, subPixelOffsetFinal);


	//Sample AA
	float4 pastframe = tex2D(spTFXAATexC, texcoord_clean);
	texcoord_clean += finalOffset * offset;
	color.rgb = SampleLinear(texcoord_clean);
	color.a = 1.0; //Use alpha to denote pixel was written to
	color.rgba = lerp(color.rgba, pastframe, 0.5); //TEST TAA





	//DEBUG stuff
	if (AADebug)
	{
		if (isHorizontal)
		{
			color.rgb = float3(1.0, 0.9, 0.2) * Oklab::INVNORM_FACTOR;
		}
		else
		{
			color.rgb = float3(0.2, 0.9, 1.0) * Oklab::INVNORM_FACTOR;
		}
	}
	
	return color;
}

technique TFXAA <ui_tooltip = 
"An anti-aliasing shader intended to replace bad TAA and FXAA implementations.\n\n"
"(HDR compatible)";>
{
	pass //Output weight texture instead that gets temporally combined? How to integrate TAA?
	{
		VertexShader = VS_AA; PixelShader = AAPass; RenderTarget = pTFXAATex;
	}
	pass
	{
		VertexShader = VS_AA; PixelShader = StoragePass; RenderTarget = pTFXAATexC;
	}
	pass //DISPLAY
	{
		VertexShader = VS_AA; PixelShader = DisplayPass;
	}
}