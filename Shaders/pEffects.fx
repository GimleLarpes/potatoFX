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
uniform int GaussianQuality < __UNIFORM_RADIO_INT1
	ui_label = "Blur quality";
	ui_tooltip = "Quality and size of gaussian blur";
	ui_items = "High quality\0Medium quality\0Fast\0";
	ui_category = "Blur";
> = 1;
//DOF
//Other settings
uniform int BokehQuality < __UNIFORM_RADIO_INT1
	ui_label = "Blur quality";
	ui_tooltip = "Quality and size of gaussian blur";
	ui_items = "High quality\0Medium quality\0Fast\0";
	ui_category = "DOF";
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
uniform float BloomCurve < __UNIFORM_SLIDER_FLOAT1
	ui_min = 1.0; ui_max = 5.0;
    ui_label = "Bloom curve";
    ui_tooltip = "Gamma applied to bloom";
	ui_category = "Bloom";
> = 1.25;

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
#undef PI
#define PI 3.1415927

texture pGaussianBlurTexH < pooled = true; > { Width = BUFFER_WIDTH/2; Height = BUFFER_HEIGHT/2; Format = RGBA16F; };
sampler spGaussianBlurTexH { Texture = pGaussianBlurTexH;};
texture pGaussianBlurTex < pooled = true; > { Width = BUFFER_WIDTH/2; Height = BUFFER_HEIGHT/2; Format = RGBA16F; };
sampler spGaussianBlurTex { Texture = pGaussianBlurTex;};

//DO BLOOM LIKE THIS: https://catlikecoding.com/unity/tutorials/advanced-rendering/bloom/ (or not actually, passes are more expensive than blur techniques)
texture pBloomHighPassTex < pooled = true; > { Width = BUFFER_WIDTH/2; Height = BUFFER_HEIGHT/2; Format = RGBA16F; };
sampler spBloomHighPassTex { Texture = pBloomHighPassTex;};
texture pBloomTex1 < pooled = true; > { Width = BUFFER_WIDTH/4; Height = BUFFER_HEIGHT/4; Format = RGBA16F; };
sampler spBloomTex1 { Texture = pBloomTex1;};
texture pBloomTex2 < pooled = true; > { Width = BUFFER_WIDTH/8; Height = BUFFER_HEIGHT/8; Format = RGBA16F; };
sampler spBloomTex2 { Texture = pBloomTex2;};
texture pBloomTex3 < pooled = true; > { Width = BUFFER_WIDTH/16; Height = BUFFER_HEIGHT/16; Format = RGBA16F; };
sampler spBloomTex3 { Texture = pBloomTex3;};
texture pBloomTex4 < pooled = true; > { Width = BUFFER_WIDTH/32; Height = BUFFER_HEIGHT/32; Format = RGBA16F; };
sampler spBloomTex4 { Texture = pBloomTex4;};
texture pBloomTex5 < pooled = true; > { Width = BUFFER_WIDTH/64; Height = BUFFER_HEIGHT/64; Format = RGBA16F; };
sampler spBloomTex5 { Texture = pBloomTex5;};
texture pBloomTex6 < pooled = true; > { Width = BUFFER_WIDTH/128; Height = BUFFER_HEIGHT/128; Format = RGBA16F; };
sampler spBloomTex6 { Texture = pBloomTex6;};

texture pBloomTex0 < pooled = true; > { Width = BUFFER_WIDTH/2; Height = BUFFER_HEIGHT/2; Format = RGBA16F; };
sampler spBloomTex0 { Texture = pBloomTex0;};


//Functions
float3 GaussianBlur(sampler s, float2 texcoord, float size, float2 direction)
{
    float2 TEXEL_SIZE = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);
    float2 step_length = TEXEL_SIZE * size;

    float3 color = tex2D(s, texcoord).rgb;

    //Weights and offsets, joinked from GaussianBlur.fx by Ioxa
    if (GaussianQuality == 2) //Low quality
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
    if (GaussianQuality == 1) //Medium quality
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
    if (GaussianQuality == 0) //High quality
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

    static const float MAX_VARIANCE = 0.1;
    float2 variance = FrameCount * float2(sin(2000*PI*texcoord.x), cos(2000*PI*texcoord.y)) * 1000.0;
    variance %= MAX_VARIANCE;
    variance = 1 + variance - MAX_VARIANCE / 2.0;
    

    //Sample points (61 points, 4 rings)
    //Fast (low quality)
    float3 color = tex2D(s, texcoord).rgb;
    color += tex2D(s, texcoord + step_length * float2(0, 8) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(6.9282, 4) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(6.9282, -4) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(0.0, -8) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(-6.9282, -4) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(-6.9282, 4) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(0, 16) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(8, 13.8564) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(13.8564, 8) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(16, 0.0) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(13.8564, -8) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(8, -13.8564) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(0.0, -16) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(-8, -13.8564) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(-13.8564, -8) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(-16, 0.0) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(-13.8564, 8) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(-8, 13.8564) * variance).rgb;

    if (BokehQuality == 0) //High quality (4 rings)
    {
        color += tex2D(s, texcoord + step_length * float2(0, 32) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(8.2822, 30.9096) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(16, 27.7128) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(22.6274, 22.6274) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(27.7128, 16) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(30.9096, 8.2822) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(32, 0.0) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(30.9096, -8.2822) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(27.7128, -16) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(22.6274, -22.6274) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(16, -27.7128) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(8.2822, -30.9096) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(0.0, -32) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-8.2822, -30.9096) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-16, -27.7128) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-22.6274, -22.6274) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-27.7128, -16) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-30.9096, -8.2822) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-32, 0.0) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-30.9096, 8.2822) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-27.7128, 16) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-22.6274, 22.6274) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-16, 27.7128) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-8.2822, 30.9096) * variance).rgb;
    }
    if (BokehQuality < 2) //Medium quality (3 rings)
    {
        //Second ring
        color += tex2D(s, texcoord + step_length * float2(0, 24) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(8.2085, 22.5526) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(15.4269, 18.3851) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(20.7846, 12) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(23.6354, 4.1676) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(23.6354, -4.1676) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(20.7846, -12) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(15.4269, -18.3851) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(8.2085, -22.5526) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(0.0, -24) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-8.2085, -22.5526) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-15.4269, -18.3851) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-20.7846, -12) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-23.6354, -4.1676) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-23.6354, 4.1676) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-20.7846, 12) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-15.4269, 18.3851) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-8.2085, 22.5526) * variance).rgb;
    }

    float brightness_compensation;
    switch (BokehQuality)
    {
        case 0:
        {
            brightness_compensation = rcp(37);
        } break;
        case 1:
        {
            brightness_compensation = 0.0515202702703;
        } break;
        case 2:
        {
            brightness_compensation = 0.100328947368;
        } break;
    }

    return color * brightness_compensation;
}

float3 DownSample(sampler s, float2 texcoord)
{
    //Code, box sampling?
    return float3(1.0, 1.0, 1.0);
}
float3 UpSample(sampler s, float2 texcoord)
{
    //Code, box sampling?
    return float3(1.0, 1.0, 1.0);
}


////Passes
//Blur
float3 GaussianBlurPass1(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR //REMEMBER TO CONVERT TO LINEAR BEFORE PROCESSING! (might have to do a ToLinear pass that is then sampled from?)
{
    float3 color = GaussianBlur(ReShade::BackBuffer, texcoord, BlurStrength, float2(1.0, 0.0));
    return color;
}
float3 GaussianBlurPass2(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    float3 color = GaussianBlur(spGaussianBlurTexH, texcoord, BlurStrength, float2(0.0, 1.0));
    return color;
}

//Bloom, based on: https://catlikecoding.com/unity/tutorials/advanced-rendering/bloom/
float3 HighPassFilter(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR //Bloom can be optimized a lot
{
    float3 color = tex2D(spGaussianBlurTex, texcoord).rgb;

    color *= Oklab::Normalize(Oklab::Luma_RGB(color)) * (1 - BloomThreshold) * 10.0;
    return color;
}
//Downsample
float3 BloomDownS1(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR //Just do blur by downsampling (if it doesn't work, maybe spam gaussians?)
{
    float3 color = DownSample(spBloomHighPassTex, texcoord);
    return color;
}
float3 BloomDownS2(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    float3 color = DownSample(spBloomTex1, texcoord);
    return color;
}
float3 BloomDownS3(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    float3 color = DownSample(spBloomTex2, texcoord);
    return color;
}
float3 BloomDownS4(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    float3 color = DownSample(spBloomTex3, texcoord);
    return color;
}
float3 BloomDownS5(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    float3 color = DownSample(spBloomTex4, texcoord);
    return color;
}
float3 BloomDownS6(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    float3 color = DownSample(spBloomTex5, texcoord);
    return color;
}
//Some adaption stuff?
//Upsample
float3 BloomUpS5(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    float3 color = UpSample(spBloomTex6, texcoord);
    return color;
}
float3 BloomUpS4(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    float3 color = UpSample(spBloomTex5, texcoord);
    return color;
}
float3 BloomUpS3(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    float3 color = UpSample(spBloomTex4, texcoord);
    return color;
}
float3 BloomUpS2(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    float3 color = UpSample(spBloomTex3, texcoord);
    return color;
}
float3 BloomUpS1(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    float3 color = UpSample(spBloomTex2, texcoord);
    return color;
}
float3 BloomUpS0(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    float3 color = UpSample(spBloomTex1, texcoord);
    return color;
}



float3 EffectsPass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb; //Only use it here if any passes that output to svtarget haven't already done it
	color = (UseApproximateTransforms)  //This needs to be moved to the first pass, preferably not a new pass though as that alone adds 0.800ms
		? Oklab::Fast_DisplayFormat_to_Linear(color)
		: Oklab::DisplayFormat_to_Linear(color);
	
	static const float INVNORM_FACTOR = Oklab::INVNORM_FACTOR;
	
    ////Effects
    //Blur
    if (BlurStrength != 0.0)
    {
        color = lerp(color, tex2D(spGaussianBlurTex, texcoord).rgb, min(4.0*BlurStrength, 1.0));//Try to find a way to reuse this texture? (for DOF)
    }



    //Bloom
    if (BloomStrength != 0.0)
    {
        //Somehow select bright pixels and blur them look at other shaders for insight. Do calculations on Downsampled texture
        color += BloomStrength * tex2D(spBloomTex0, texcoord).rgb;
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
            color.rgb = Oklab::Saturate_RGB(color.rgb * (1-weight) + (gauss_noise1 - 0.225) * weight);
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
    
    //Bloom downsample and upsample passes
    #define BLOOM_DOWN_PASS(i) pass { VertexShader = PostProcessVS; PixelShader = BloomDownS##i; RenderTarget = pBloomTex##i; }
    #define BLOOM_UP_PASS(i) pass { VertexShader = PostProcessVS; PixelShader = BloomUpS##i; RenderTarget = pBloomTex##i; }
    
    BLOOM_DOWN_PASS(1)
    BLOOM_DOWN_PASS(2)
    BLOOM_DOWN_PASS(3)
    BLOOM_DOWN_PASS(4)
    BLOOM_DOWN_PASS(5)
    BLOOM_DOWN_PASS(6)

    BLOOM_UP_PASS(5)
    BLOOM_UP_PASS(4)
    BLOOM_UP_PASS(3)
    BLOOM_UP_PASS(2)
    BLOOM_UP_PASS(1)
    BLOOM_UP_PASS(0)
    #endif
    
    pass
	{
		VertexShader = PostProcessVS; PixelShader = EffectsPass;
	}
}
