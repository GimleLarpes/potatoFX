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
	ui_tooltip = "Quality of gaussian blur";
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
texture pBloomHighPassTex < pooled = true; > { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler spBloomHighPassTex { Texture = pBloomHighPassTex;};
texture pBloom1Tex < pooled = true; > { Width = BUFFER_WIDTH/2; Height = BUFFER_HEIGHT/2; Format = RGBA16F; };
sampler spBloom1Tex { Texture = pBloom1Tex;};
//This is kinda stupid look for a better way to blur/do bloom
texture pBloom2Tex < pooled = true; > { Width = BUFFER_WIDTH/6; Height = BUFFER_HEIGHT/6; Format = RGBA16F; };
sampler spBloom2Tex { Texture = pBloom2Tex;};
texture pBloomTex < pooled = true; > { Width = BUFFER_WIDTH/4; Height = BUFFER_HEIGHT/4; Format = RGBA16F; };
sampler spBloomTex { Texture = pBloomTex;};


//Functions
float3 GaussianBlur(sampler s, float4 vpos, float2 texcoord, float size, float2 direction)
{
    float2 TEXEL_SIZE = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);
    float2 step_length = TEXEL_SIZE * size * 2.0; //Blur is acceptable with 2x extended step length

    float3 color = tex2D(s, texcoord).rgb;

    //Weights and offsets
    if (BlurQuality == 2) //Low quality
    {   
        static const float OFFSET[4] = { 0.0, 1.1824255238, 3.0293122308, 5.0040701377 };
	    static const float WEIGHT[4] = { 0.39894, 0.2959599993, 0.0045656525, 0.00000149278686458842 };
        
        color *= WEIGHT[0];
        [loop]
        for (int i = 1; i < 4; ++i)
        {
            color += tex2D(s, texcoord + direction * OFFSET[i] * step_length).rgb * WEIGHT[i];
            color += tex2D(s, texcoord - direction * OFFSET[i] * step_length).rgb * WEIGHT[i];
        }
    }
    if (BlurQuality == 1) //Medium quality
    {   
        static const float OFFSET[6] = { 0.0, 1.4584295168, 3.40398480678, 5.3518057801, 7.302940716, 9.2581597095 };
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
        static const float OFFSET[11] = { 0.0, 1.4895848401, 3.4757135714, 5.4618796741, 7.4481042327, 9.4344079746, 11.420811147, 13.4073334, 15.3939936778, 17.3808101174, 19.3677999584 };
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

    //Sample points
    //Fast (low quality)
    //Inner ring
    float3 color = tex2D(s, texcoord).rgb;
    color += tex2D(s, texcoord + step_length * float2(0.0, 10.6667)).rgb;
    color += tex2D(s, texcoord + step_length * float2(10.1446, 3.2962)).rgb;
    color += tex2D(s, texcoord + step_length * float2(6.2697, -8.6295)).rgb;
    color += tex2D(s, texcoord + step_length * float2(-6.2697, -8.6295)).rgb;
    color += tex2D(s, texcoord + step_length * float2(-10.1446, 3.2962)).rgb;

    //Preparing for own (hardcoded)distribution
    if (BlurQuality == 0) //High quality (3 rings)
    {
        //Third outermost ring
        color += tex2D(s, texcoord + step_length * float2(0.0, 32)).rgb;
        color += tex2D(s, texcoord + step_length * float2(13.0156, 29.2335)).rgb;
        color += tex2D(s, texcoord + step_length * float2(23.7806, 21.4122)).rgb;
        color += tex2D(s, texcoord + step_length * float2(30.4338, 9.8885)).rgb;
        color += tex2D(s, texcoord + step_length * float2(31.8247, -3.3449)).rgb;
        color += tex2D(s, texcoord + step_length * float2(27.7128, -16)).rgb;
        color += tex2D(s, texcoord + step_length * float2(18.8091, -25.8885)).rgb;
        color += tex2D(s, texcoord + step_length * float2(6.6532, -31.3007)).rgb;
        color += tex2D(s, texcoord + step_length * float2(-6.6532, -31.3007)).rgb;
        color += tex2D(s, texcoord + step_length * float2(-18.8091, -25.8885)).rgb;
        color += tex2D(s, texcoord + step_length * float2(-27.7128, -16)).rgb;
        color += tex2D(s, texcoord + step_length * float2(-31.8247, -3.3449)).rgb;
        color += tex2D(s, texcoord + step_length * float2(-30.4338, 9.8885)).rgb;
        color += tex2D(s, texcoord + step_length * float2(-23.7806, 21.4122)).rgb;
        color += tex2D(s, texcoord + step_length * float2(-13.0156, 29.2335)).rgb;
    }
    if (BlurQuality < 2) //Medium quality (2 rings)
    {
        //Second ring
        color += tex2D(s, texcoord + step_length * float2(0.0, 21.3333)).rgb;
        color += tex2D(s, texcoord + step_length * float2(12.5394, 17.259)).rgb;
        color += tex2D(s, texcoord + step_length * float2(20.2892, 6.5924)).rgb;
        color += tex2D(s, texcoord + step_length * float2(20.2892, -6.5924)).rgb;
        color += tex2D(s, texcoord + step_length * float2(12.5394, -17.259)).rgb;
        color += tex2D(s, texcoord + step_length * float2(0.0, -21.3333)).rgb;
        color += tex2D(s, texcoord + step_length * float2(-12.5394, -17.259)).rgb;
        color += tex2D(s, texcoord + step_length * float2(-20.2892, -6.5924)).rgb;
        color += tex2D(s, texcoord + step_length * float2(-20.2892, 6.5924)).rgb;
        color += tex2D(s, texcoord + step_length * float2(-12.5394, 17.259)).rgb;
    }

    float brightness_compensation;
    switch (BlurQuality)
    {
        case 0:
        {
            brightness_compensation = 1.0;
        } break;
        case 1:
        {
            brightness_compensation = 1.9375;
        } break;
        case 2:
        {
            brightness_compensation = 5.1667;
        } break;
    }

    return color * brightness_compensation / 31.0;
}


//Passes, replace bokehblurpasses with gaussianblur passes
float3 GaussianBlurPass1(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR //REMEMBER TO CONVERT TO LINEAR BEFORE PROCESSING! (might have to do a ToLinear pass that is then sampled from?)
{
    float3 color = GaussianBlur(ReShade::BackBuffer, vpos, texcoord, BlurStrength, float2(1.0, 0.0));
    return color;
}
float3 GaussianBlurPass2(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    float3 color = GaussianBlur(spBokehBlurTexH, vpos, texcoord, BlurStrength, float2(0.0, 1.0));
    return color;
}

float3 HighPassFilter(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR //Bloom can be optimized a lot, use first gaussian pass as base?
{
    float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;

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
	float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
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
    #if BlurStrength >= 0
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
