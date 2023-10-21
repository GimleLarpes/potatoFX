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
uniform int BlurQuality < __UNIFORM_RADIO_INT1
	ui_label = "Blur quality";
	ui_tooltip = "Quality and size of gaussian blur";
	ui_items = "High quality\0Medium quality\0Fast\0";
	ui_category = "Blur";
> = 1;







//Bloom
uniform float BloomStrength < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
    ui_label = "Bloom amount";
    ui_tooltip = "Amount of blooming to apply";
	ui_category = "Bloom";
> = 0.0;
uniform float BloomThreshold < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
    ui_label = "Bloom threshold";
    ui_tooltip = "Threshold for blooming";
	ui_category = "Bloom";
> = 0.85;

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

texture pGaussianBlurTexH < pooled = true; > { Width = BUFFER_WIDTH/2; Height = BUFFER_HEIGHT/2; Format = RGBA16F; };
sampler spGaussianBlurTexH { Texture = pGaussianBlurTexH;};
texture pGaussianBlurTex < pooled = true; > { Width = BUFFER_WIDTH/2; Height = BUFFER_HEIGHT/2; Format = RGBA16F; };
sampler spGaussianBlurTex { Texture = pGaussianBlurTex;};

//DO BLOOM LIKE THIS: https://catlikecoding.com/unity/tutorials/advanced-rendering/bloom/
texture pBloomHighPassTex < pooled = true; > { Width = BUFFER_WIDTH/2; Height = BUFFER_HEIGHT/2; Format = RGBA16F; };
sampler spBloomHighPassTex { Texture = pBloomHighPassTex;};
texture pBloom1Tex < pooled = true; > { Width = BUFFER_WIDTH/4; Height = BUFFER_HEIGHT/4; Format = RGBA16F; };
sampler spBloom1Tex { Texture = pBloom1Tex;};
//This is kinda stupid look for a better way to blur/do bloom
texture pBloom2Tex < pooled = true; > { Width = BUFFER_WIDTH/8; Height = BUFFER_HEIGHT/8; Format = RGBA16F; };
sampler spBloom2Tex { Texture = pBloom2Tex;};
texture pBloomTex < pooled = true; > { Width = BUFFER_WIDTH/4; Height = BUFFER_HEIGHT/4; Format = RGBA16F; };
sampler spBloomTex { Texture = pBloomTex;};


//Functions
float3 GaussianBlur(sampler s, float4 vpos, float2 texcoord, float size, float2 direction)
{
    float2 TEXEL_SIZE = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);
    float2 step_length = TEXEL_SIZE * size;

    float3 color = tex2D(s, texcoord).rgb;

    //Weights and offsets, joinked from GaussianBlur.fx by Ioxa
    if (BlurQuality == 2) //Low quality
    {   
        static const float OFFSET[4] = { 0.0, 2.3648510476, 6.0586244616, 10.0081402754 };
	    static const float WEIGHT[4] = { 0.39894, 0.2959599993, 0.0045656525, 0.00000149278686458842 };
        
        color *= WEIGHT[0]; //For some reason these loops have to be in here and not the main function body
        [loop]
        for (int i = 1; i < 4; ++i)
        {
            color += tex2D(s, texcoord + direction * OFFSET[i] * step_length).rgb * WEIGHT[i];
            color += tex2D(s, texcoord - direction * OFFSET[i] * step_length).rgb * WEIGHT[i];
        }
    }
    if (BlurQuality == 1) //Medium quality
    {   
        static const float OFFSET[6] = { 0.0, 2.9168590336, 6.80796961356, 10.7036115602, 14.605881432, 18.516319419 };
	    static const float WEIGHT[6] = { 0.13298, 0.23227575, 0.1353261595, 0.0511557427, 0.01253922, 0.0019913644 };
        
        color *= WEIGHT[0];
        [loop]
        for (int i = 1; i < 6; ++i)
        {
            color += tex2D(s, texcoord + direction * OFFSET[i] * step_length).rgb * WEIGHT[i];
            color += tex2D(s, texcoord - direction * OFFSET[i] * step_length).rgb * WEIGHT[i];
        }
    }
    if (BlurQuality == 0) //High quality
    {   
        static const float OFFSET[11] = { 0.0, 2.9791696802, 6.9514271428, 10.9237593482, 14.8962084654, 18.8688159492, 22.841622294, 26.8146668, 30.7879873556, 34.7616202348, 38.7355999168 };
	    static const float WEIGHT[11] = { 0.06649, 0.1284697563, 0.111918249, 0.0873132676, 0.0610011113, 0.0381655709, 0.0213835661, 0.0107290241, 0.0048206869, 0.0019396469, 0.0006988718 };
        
        color *= WEIGHT[0];
        [loop]
        for (int i = 1; i < 11; ++i)
        {
            color += tex2D(s, texcoord + direction * OFFSET[i] * step_length).rgb * WEIGHT[i];
            color += tex2D(s, texcoord - direction * OFFSET[i] * step_length).rgb * WEIGHT[i];
        }
    }
    return color;
}

float3 BokehBlur(sampler s, float4 vpos, float2 texcoord, float size)
{
    float2 TEXEL_SIZE = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);
    float2 step_length = TEXEL_SIZE * size;

    //Sample points (37 points, 3 rings)
    //Fast (low quality)
    //Inner ring
    float3 color = tex2D(s, texcoord).rgb;
    color += tex2D(s, texcoord + step_length * float2(0, 10.6667)).rgb;
    color += tex2D(s, texcoord + step_length * float2(9.2376, 5.3333)).rgb;
    color += tex2D(s, texcoord + step_length * float2(9.2376, -5.3333)).rgb;
    color += tex2D(s, texcoord + step_length * float2(0.0, -10.6667)).rgb;
    color += tex2D(s, texcoord + step_length * float2(-9.2376, -5.3333)).rgb;
    color += tex2D(s, texcoord + step_length * float2(-9.2376, 5.3333)).rgb;

    if (BlurQuality == 0) //High quality (3 rings)
    {
        //Third outermost ring
        color += tex2D(s, texcoord + step_length * float2(0, 32)).rgb;
        color += tex2D(s, texcoord + step_length * float2(10.9446, 30.0702)).rgb;
        color += tex2D(s, texcoord + step_length * float2(20.5692, 24.5134)).rgb;
        color += tex2D(s, texcoord + step_length * float2(27.7128, 16)).rgb;
        color += tex2D(s, texcoord + step_length * float2(31.5138, 5.5567)).rgb;
        color += tex2D(s, texcoord + step_length * float2(31.5138, -5.5567)).rgb;
        color += tex2D(s, texcoord + step_length * float2(27.7128, -16)).rgb;
        color += tex2D(s, texcoord + step_length * float2(20.5692, -24.5134)).rgb;
        color += tex2D(s, texcoord + step_length * float2(10.9446, -30.0702)).rgb;
        color += tex2D(s, texcoord + step_length * float2(0.0, -32)).rgb;
        color += tex2D(s, texcoord + step_length * float2(-10.9446, -30.0702)).rgb;
        color += tex2D(s, texcoord + step_length * float2(-20.5692, -24.5134)).rgb;
        color += tex2D(s, texcoord + step_length * float2(-27.7128, -16)).rgb;
        color += tex2D(s, texcoord + step_length * float2(-31.5138, -5.5567)).rgb;
        color += tex2D(s, texcoord + step_length * float2(-31.5138, 5.5567)).rgb;
        color += tex2D(s, texcoord + step_length * float2(-27.7128, 16)).rgb;
        color += tex2D(s, texcoord + step_length * float2(-20.5692, 24.5134)).rgb;
        color += tex2D(s, texcoord + step_length * float2(-10.9446, 30.0702)).rgb;
    }
    if (BlurQuality < 2) //Medium quality (2 rings)
    {
        //Second ring
        color += tex2D(s, texcoord + step_length * float2(0, 21.3333)).rgb;
        color += tex2D(s, texcoord + step_length * float2(10.6667, 18.4752)).rgb;
        color += tex2D(s, texcoord + step_length * float2(18.4752, 10.6667)).rgb;
        color += tex2D(s, texcoord + step_length * float2(21.3333, 0.0)).rgb;
        color += tex2D(s, texcoord + step_length * float2(18.4752, -10.6667)).rgb;
        color += tex2D(s, texcoord + step_length * float2(10.6667, -18.4752)).rgb;
        color += tex2D(s, texcoord + step_length * float2(0.0, -21.3333)).rgb;
        color += tex2D(s, texcoord + step_length * float2(-10.6667, -18.4752)).rgb;
        color += tex2D(s, texcoord + step_length * float2(-18.4752, -10.6667)).rgb;
        color += tex2D(s, texcoord + step_length * float2(-21.3333, 0.0)).rgb;
        color += tex2D(s, texcoord + step_length * float2(-18.4752, 10.6667)).rgb;
        color += tex2D(s, texcoord + step_length * float2(-10.6667, 18.4752)).rgb;
    }

    float brightness_compensation;
    switch (BlurQuality)
    {
        case 0:
        {
            brightness_compensation = rcp(37);
        } break;
        case 1:
        {
            brightness_compensation = 0.0526315789473;
        } break;
        case 2:
        {
            brightness_compensation = 0.142857142857;
        } break;
    }

    return color * brightness_compensation;
}


//Passes
float3 GaussianBlurPass1(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR //REMEMBER TO CONVERT TO LINEAR BEFORE PROCESSING! (might have to do a ToLinear pass that is then sampled from?)
{
    float3 color = GaussianBlur(ReShade::BackBuffer, vpos, texcoord, BlurStrength, float2(1.0, 0.0));
    return color;
}
float3 GaussianBlurPass2(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    float3 color = GaussianBlur(spGaussianBlurTexH, vpos, texcoord, BlurStrength, float2(0.0, 1.0));
    return color;
}

float3 HighPassFilter(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR //Bloom can be optimized a lot
{
    float3 color = tex2D(spGaussianBlurTex, texcoord).rgb;

    color *= Oklab::Normalize(Oklab::Luma_RGB(color)) * (1 - BloomThreshold) * 10.0;
    return color;
}
float3 BloomPass1(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR //I need a lot more blur, blur by downsampling?
{
    float3 color = BokehBlur(spBloomHighPassTex, vpos, texcoord, 1.0 * BloomStrength);
    return color * 4 * BloomStrength;
}
float3 BloomPass2(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    float3 color = BokehBlur(spBloom1Tex, vpos, texcoord, 1.5 * BloomStrength);
    return color * 2 * BloomStrength;
}
float3 BloomPass3(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    float3 color = BokehBlur(spBloom2Tex, vpos, texcoord, 2.0 * BloomStrength);
    return color * BloomStrength;
}


float3 EffectsPass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb; //Only use it here if any passes that output to svtarget haven't already done it
	color = (UseApproximateTransforms)  //This needs to be moved to the first pass, preferably not a new pass though as that alone adds 0.800ms
		? Oklab::Fast_DisplayFormat_to_Linear(color)
		: Oklab::DisplayFormat_to_Linear(color);
	
	static const float PI = 3.1415927;
	static const float INVNORM_FACTOR = Oklab::INVNORM_FACTOR;
	
    ////Effects
    //Blur
    if (BlurStrength != 0.0)
    {
        color = lerp(color, tex2D(spGaussianBlurTex, texcoord).rgb, min(4.0*BlurStrength, 1.0));//Try to find a way to reuse this texture? (for DOF)
    }



    //Bloom, this is extremely unoptimized (uses 3 passes)
    if (BloomStrength != 0.0)
    {
        //Somehow select bright pixels and blur them look at other shaders for insight. Do calculations on Downsampled texture
        color += BloomStrength * tex2D(spBloomTex, texcoord).rgb;
    }

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
    #if BlurStrength + BloomStrength >= 0
	pass
    {//This is also used in DOF and bloom
        VertexShader = PostProcessVS; PixelShader = GaussianBlurPass1; RenderTarget = pGaussianBlurTexH;
    }
    pass
    {
        VertexShader = PostProcessVS; PixelShader = GaussianBlurPass2; RenderTarget = pGaussianBlurTex;
    }
    #endif

    #if BloomStrength >= 0
	pass
    {
        VertexShader = PostProcessVS; PixelShader = HighPassFilter; RenderTarget = pBloomHighPassTex;
    }
    pass
    {
        VertexShader = PostProcessVS; PixelShader = BloomPass1; RenderTarget = pBloom1Tex;
    }
    pass
    {
        VertexShader = PostProcessVS; PixelShader = BloomPass2; RenderTarget = pBloom2Tex;
    }
    pass
    {
        VertexShader = PostProcessVS; PixelShader = BloomPass3; RenderTarget = pBloomTex;
    }
    #endif
    
    pass
	{
		VertexShader = PostProcessVS; PixelShader = EffectsPass;
	}
}
