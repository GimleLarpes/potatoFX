///////////////////////////////////////////////////////////////////////////////////
// pEffects.fx by Gimle Larpes
// A high performance all-in-one shader with many common lens and camera effects.
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
//Other settings, aperture and focal length?
uniform bool UseDOF <
	ui_type = "bool";
	ui_label = "Enable DOF";
    ui_tooltip = "Use depth of field";
	ui_category = "LUT";
> = false;
uniform int BokehQuality < __UNIFORM_RADIO_INT1
	ui_label = "Blur quality";
	ui_tooltip = "Quality and size of gaussian blur";
	ui_items = "High quality\0Medium quality\0Fast\0";
	ui_category = "DOF";
> = 1;

//Glass imperfections
uniform float GeoIStrength < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 4.0;
    ui_label = "Glass quality";
    ui_tooltip = "Amount of surface lens imperfections";
	ui_category = "Lens Imperfections";
> = 0.0;

//Lens flare
uniform float FlareStrength < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
    ui_label = "Lens flare amount";
    ui_tooltip = "Amount of lens flaring";
	ui_category = "Lens Imperfections";
> = 0.0;

//Chromatic aberration
uniform float CAStrength < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
    ui_label = "CA amount";
    ui_tooltip = "Amount of chromatic aberration";
	ui_category = "Lens Imperfections";
> = 0.0;

//Dirt
uniform float DirtStrength < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
    ui_label = "Dirt amount";
    ui_tooltip = "Amount of dirt on the lens";
	ui_category = "Lens Imperfections";
> = 0.0;
uniform float DirtScale < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.5; ui_max = 2.5;
    ui_label = "Dirt scale";
    ui_tooltip = "Scaling of dirt texture";
	ui_category = "Lens Imperfections";
> = 1.3;

//Bloom
#if BUFFER_COLOR_SPACE > 1
    static const float BLOOM_CURVE_DEFAULT = 1.0;
    static const float BLOOM_GAMMA_DEFAULT = 1.0;
#else
    static const float BLOOM_CURVE_DEFAULT = 1.0;
    static const float BLOOM_GAMMA_DEFAULT = 0.8;
#endif
uniform float BloomStrength < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
    ui_label = "Bloom amount";
    ui_tooltip = "Amount of blooming to apply";
	ui_category = "Bloom";
> = 0.0;
uniform float BloomCurve < __UNIFORM_SLIDER_FLOAT1
	ui_min = 1.0; ui_max = 5.0;
    ui_label = "Bloom curve";
    ui_tooltip = "What parts of the image to apply bloom to\n1 = linear      5 = brightest parts only";
	ui_category = "Bloom";
> = BLOOM_CURVE_DEFAULT;
uniform float BloomGamma < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.1; ui_max = 2;
    ui_label = "Bloom gamma";
    ui_tooltip = "Controls shape of bloom";
	ui_category = "Bloom";
> = BLOOM_GAMMA_DEFAULT;

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

#undef BUMP_MAP_RESOLUTION
#define BUMP_MAP_RESOLUTION 32
#undef BUMP_MAP_SCALE
#define BUMP_MAP_SCALE 4
#undef BUMP_MAP_SOURCE
#define BUMP_MAP_SOURCE "pBumpTex.png"

#undef DIRT_MAP_RESOLUTION
#define DIRT_MAP_RESOLUTION 1024
#undef DIRT_MAP_SOURCE
#define DIRT_MAP_SOURCE "pDirtTex.png"

texture pBumpTex < source = BUMP_MAP_SOURCE; pooled = true; > { Width = BUMP_MAP_RESOLUTION; Height = BUMP_MAP_RESOLUTION; Format = RG8; };
sampler spBumpTex { Texture = pBumpTex; AddressU = REPEAT; AddressV = REPEAT;}; //GA channels are unused (remember to switch to RGBA8)!!!

texture pDirtTex < source = DIRT_MAP_SOURCE; pooled = true; > { Width = DIRT_MAP_RESOLUTION; Height = DIRT_MAP_RESOLUTION; Format = RGBA8; };
sampler spDirtTex { Texture = pDirtTex; AddressU = REPEAT; AddressV = REPEAT;};

texture pLinearTex < pooled = true; > { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler spLinearTex { Texture = pLinearTex;};

texture pGaussianBlurTexH < pooled = true; > { Width = BUFFER_WIDTH/2; Height = BUFFER_HEIGHT/2; Format = RGBA16F; };
sampler spGaussianBlurTexH { Texture = pGaussianBlurTexH;};
texture pGaussianBlurTex < pooled = true; > { Width = BUFFER_WIDTH/2; Height = BUFFER_HEIGHT/2; Format = RGBA16F; };
sampler spGaussianBlurTex { Texture = pGaussianBlurTex;};

#undef BLOOM_MIP
#define BLOOM_MIP 1 //doesn't like using functions
texture pBloomTex0 < pooled = true; > { Width = BUFFER_WIDTH/2; Height = BUFFER_HEIGHT/2; Format = RGBA16F; MipLevels = BLOOM_MIP; };
sampler spBloomTex0 { Texture = pBloomTex0;};
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
texture pBloomTex7 < pooled = true; > { Width = BUFFER_WIDTH/256; Height = BUFFER_HEIGHT/256; Format = RGBA16F; };
sampler spBloomTex7 { Texture = pBloomTex7;};
texture pBloomTex8 < pooled = true; > { Width = BUFFER_WIDTH/512; Height = BUFFER_HEIGHT/512; Format = RGBA16F; };
sampler spBloomTex8 { Texture = pBloomTex8;};


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
    

    //Sample points (91 points, 5 rings)
    //Fast (low quality, 19 points, 2 rings)
    float3 color = tex2D(s, texcoord).rgb;
    color += tex2D(s, texcoord + step_length * float2(0, 4) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(3.4641, 2) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(3.4641, -2) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(0, -4) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(-3.4641, -2) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(-3.4641, 2) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(0, 8) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(4, 6.9282) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(6.9282, 4) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(8, 0) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(6.9282, -4) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(4, -6.9282) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(0, -8) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(-4, -6.9282) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(-6.9282, -4) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(-8, 0) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(-6.9282, 4) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(-4, 6.9282) * variance).rgb;

    if (BokehQuality == 0) //High quality (5 rings)
    {
        color += tex2D(s, texcoord + step_length * float2(0, 16) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(4.1411, 15.4548) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(8, 13.8564) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(11.3137, 11.3137) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(13.8564, 8) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(15.4548, 4.1411) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(16, 0) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(15.4548, -4.1411) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(13.8564, -8) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(11.3137, -11.3137) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(8, -13.8564) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(4.1411, -15.4548) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(0, -16) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-4.1411, -15.4548) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-8, -13.8564) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-11.3137, -11.3137) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-13.8564, -8) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-15.4548, -4.1411) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-16, 0) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-15.4548, 4.1411) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-13.8564, 8) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-11.3137, 11.3137) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-8, 13.8564) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-4.1411, 15.4548) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(0, 20) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(4.1582, 19.563) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(8.1347, 18.2709) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(11.7557, 16.1803) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(14.8629, 13.3826) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(17.3205, 10) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(19.0211, 6.1803) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(19.8904, 2.0906) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(19.8904, -2.0906) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(19.0211, -6.1803) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(17.3205, -10) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(14.8629, -13.3826) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(11.7557, -16.1803) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(8.1347, -18.2709) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(4.1582, -19.563) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(0, -20) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-4.1582, -19.563) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-8.1347, -18.2709) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-11.7557, -16.1803) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-14.8629, -13.3826) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-17.3205, -10) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-19.0211, -6.1803) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-19.8904, -2.0906) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-19.8904, 2.0906) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-19.0211, 6.1803) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-17.3205, 10) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-14.8629, 13.3826) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-11.7557, 16.1803) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-8.1347, 18.2709) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-4.1582, 19.563) * variance).rgb;
    }
    if (BokehQuality < 2) //Medium quality (37 points, 3 rings)
    {
        //Third ring
        color += tex2D(s, texcoord + step_length * float2(0, 12) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(4.1042, 11.2763) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(7.7135, 9.1925) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(10.3923, 6) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(11.8177, 2.0838) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(11.8177, -2.0838) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(10.3923, -6) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(7.7135, -9.1925) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(4.1042, -11.2763) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(0, -12) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-4.1042, -11.2763) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-7.7135, -9.1925) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-10.3923, -6) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-11.8177, -2.0838) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-11.8177, 2.0838) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-10.3923, 6) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-7.7135, 9.1925) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-4.1042, 11.2763) * variance).rgb;
    }

    float brightness_compensation;
    switch (BokehQuality)
    {
        case 0:
        {
            brightness_compensation = 0.010989010989;
        } break;
        case 1:
        {
            brightness_compensation = 0.027027027027;
        } break;
        case 2:
        {
            brightness_compensation = 0.0526315789474;
        } break;
    }

    return color * brightness_compensation;
}

float3 BoxSample(sampler s, float2 texcoord, float d)
{
    float2 TEXEL_SIZE = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);
    float4 o = TEXEL_SIZE.xyxy * float2(-d, d).xxyy;

    float3 color = tex2D(s, texcoord + o.xy).rgb + tex2D(s, texcoord + o.zy).rgb + tex2D(s, texcoord + o.xw).rgb + tex2D(s, texcoord + o.zw).rgb;
    return color * 0.25;
}


//Vertex shaders
struct vs2ps
{
    float4 vpos : SV_Position;
    float4 uv : TEXCOORD0;
};

vs2ps vs_basic(const uint id)
{
    vs2ps o;
    o.uv.x = (id == 2) ? 2.0 : 0.0;
    o.uv.y = (id == 1) ? 2.0 : 0.0;
    o.vpos = float4(o.uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    return o;
}

vs2ps VS_Blur(uint id : SV_VertexID)
{
    vs2ps o = vs_basic(id);
    if (BlurStrength == 0.0)
    {
        o.vpos.xy = 0.0;
    }
    return o;
}

vs2ps VS_DOF(uint id : SV_VertexID)
{
    vs2ps o = vs_basic(id);
    if (!UseDOF)
    {
        o.vpos.xy = 0.0;
    }
    return o;
}

vs2ps VS_Bloom(uint id : SV_VertexID)
{   
    vs2ps o = vs_basic(id);
    if (BloomStrength == 0.0 && DirtStrength == 0.0)
    {
        o.vpos.xy = 0.0;
    }
    return o;
}


////Passes
float3 LinearizePass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    float3 color = tex2D(ReShade::BackBuffer, texcoord);
    color = (UseApproximateTransforms)
		? Oklab::Fast_DisplayFormat_to_Linear(color)
		: Oklab::DisplayFormat_to_Linear(color);
    return color;
}

//Blur
float3 GaussianBlurPass1(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    float3 color = GaussianBlur(spLinearTex, texcoord, BlurStrength, float2(1.0, 0.0));
    return color;
}
float3 GaussianBlurPass2(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    float3 color = GaussianBlur(spGaussianBlurTexH, texcoord, BlurStrength, float2(0.0, 1.0));
    return color;
}

//DOF
float3 BokehBlurPass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    float size = 1;//calculations
    float3 color = BokehBlur(spGaussianBlurTex, vpos, texcoord, size); //Some better way of picking between gaussian and linear tex
    return color;
}

//Bloom, based on: https://catlikecoding.com/unity/tutorials/advanced-rendering/bloom/
float3 HighPassFilter(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{   //CHANGE THIS WHEN DOF ADDED? (or is it more realistic to not?)
    float3 color = (BlurStrength == 0.0) ? tex2D(spLinearTex, texcoord).rgb : tex2D(spGaussianBlurTex, texcoord).rgb;

    static const float PAPER_WHITE = Oklab::HDR_PAPER_WHITE;
	float adapted_luma = min(2.0 * Oklab::Luma_RGB(color) / PAPER_WHITE, 1.0);

    if (!Oklab::IS_HDR)
    {
        color = Oklab::LottesInv(color);
    }

    color *= pow(abs(adapted_luma), BloomCurve * BloomCurve);
    return color;
}
//Downsample
float3 BloomDownS1(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    float3 color = BoxSample(spBloomTex0, texcoord, 1.0);
    return color;
}
float3 BloomDownS2(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    float3 color = BoxSample(spBloomTex1, texcoord, 1.0);
    return color;
}
float3 BloomDownS3(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    float3 color = BoxSample(spBloomTex2, texcoord, 1.0);
    return color;
}
float3 BloomDownS4(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    float3 color = BoxSample(spBloomTex3, texcoord, 1.0);
    return color;
}
float3 BloomDownS5(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    float3 color = BoxSample(spBloomTex4, texcoord, 1.0);
    return color;
}
float3 BloomDownS6(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    float3 color = BoxSample(spBloomTex5, texcoord, 1.0);
    return color;
}
float3 BloomDownS7(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    float3 color = BoxSample(spBloomTex6, texcoord, 1.0);
    return color;
}
float3 BloomDownS8(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    float3 color = BoxSample(spBloomTex7, texcoord, 1.0);
    return color;
}
//Upsample
float3 BloomUpS7(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    float3 color = BoxSample(spBloomTex8, texcoord, 0.5);
    return color * 0.25;
}
float3 BloomUpS6(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    float3 color = BoxSample(spBloomTex7, texcoord, 0.5);
    return color;
}
float3 BloomUpS5(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    float3 color = BoxSample(spBloomTex6, texcoord, 0.5);
    return color;
}
float3 BloomUpS4(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    float3 color = BoxSample(spBloomTex5, texcoord, 0.5);
    return color;
}
float3 BloomUpS3(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    float3 color = BoxSample(spBloomTex4, texcoord, 0.5);
    return color;
}
float3 BloomUpS2(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    float3 color = BoxSample(spBloomTex3, texcoord, 0.5);
    return color;
}
float3 BloomUpS1(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    float3 color = BoxSample(spBloomTex2, texcoord, 0.5) + tex2D(spBloomTex1, texcoord).rgb;
    return color;
}
float3 BloomUpS0(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    float3 color = BoxSample(spBloomTex1, texcoord, 0.5);

    if (!Oklab::IS_HDR)
    {
        color = Oklab::Lottes(color);
    }

    if (BloomGamma != 1.0)
    {
        color *= pow(abs(Oklab::Luma_RGB(color / Oklab::INVNORM_FACTOR)), BloomGamma);
    }
    return color;
}



float3 EffectsPass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	static const float INVNORM_FACTOR = Oklab::INVNORM_FACTOR;
    static const float2 TEXEL_SIZE = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);
	
    ////Effects
    //Glass imperfections
    if (GeoIStrength != 0.0)
    {
        float2 bump = 0.666666666 * tex2D(spBumpTex, texcoord * BUMP_MAP_SCALE).xy + 0.333333333 * tex2D(spBumpTex, texcoord * BUMP_MAP_SCALE * 3).xy;
    
	    bump = bump * 2.0 - 1.0;
        texcoord += bump * TEXEL_SIZE * (GeoIStrength * GeoIStrength);
    }
    float3 color = tex2D(spLinearTex, texcoord).rgb;
    
    //Blur
    float blur_mix = min((4 - GaussianQuality) * BlurStrength, 1.0);
    if (BlurStrength != 0.0)
    {
        color = lerp(color, tex2D(spGaussianBlurTex, texcoord).rgb, blur_mix);
    }

    //DOF
    if (UseDOF)
    {
        //CODE
    }

    //Lens flare
    //probably use radiant vector in some way

    //Chromatic aberration,  THIS WILL (maybe) NEED TWEAKS WHEN DOF IS IMPLEMENTED
    float2 radiant_vector = texcoord.xy - 0.5;
    if (CAStrength != 0.0)
    {
        float3 influence = float3(-0.04, 0.0, 0.03);

        float2 step_length = CAStrength * radiant_vector;
        color.r = lerp(tex2D(spLinearTex, texcoord + step_length * influence.r).r, tex2D(spGaussianBlurTex, texcoord + step_length * influence.r).r, blur_mix);
        color.b = lerp(tex2D(spLinearTex, texcoord + step_length * influence.b).b, tex2D(spGaussianBlurTex, texcoord + step_length * influence.b).b, blur_mix);
    }

    //Dirt
    if (DirtStrength != 0.0)
    {
        float3 weight = 0.33 * tex2D(spBloomTex6, -radiant_vector + 0.5).rgb;
        color += tex2D(spDirtTex, texcoord * float2(1.0, TEXEL_SIZE.x / TEXEL_SIZE.y) * DirtScale).rgb * weight * DirtStrength;
    }

    //Bloom
    if (BloomStrength != 0.0)
    {
        color += (BloomStrength * BloomStrength) * tex2D(spBloomTex0, texcoord).rgb;
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
	    float weight = (NoiseStrength * NoiseStrength) * NOISE_CURVE / (luma * (1 + rcp(INVNORM_FACTOR)) + 2.0); //Multiply luma to simulate a wider dynamic range

	    if (NoiseType == 1)
        {   //Color noise
            float gauss_noise2 = r * sin(theta);
	        float gauss_noise3 = (gauss_noise1 + gauss_noise2) * 0.7;
            color.rgb = color.rgb * (1-weight) + Oklab::Saturate_RGB(float3(gauss_noise1, gauss_noise2, gauss_noise3)) * weight;
        }
        else
        {   //Film grain
            color.rgb = color.rgb * (1-weight) + (gauss_noise1 - 0.225) * weight;
        }
    }

    if (!Oklab::IS_HDR) { color = Oklab::Saturate_RGB(color); }
	color = (UseApproximateTransforms)
		? Oklab::Fast_Linear_to_DisplayFormat(color)
		: Oklab::Linear_to_DisplayFormat(color);
	return color.rgb;
}

technique Effects <ui_tooltip = 
"A high performance all-in-one shader with many common lens and camera effects.\n\n"
"(HDR compatible)";>
{
    pass
    {
        VertexShader = PostProcessVS; PixelShader = LinearizePass; RenderTarget = pLinearTex;
    }


	pass
    {//This is also used in DOF(?) or just use gaussian for both near and far field (1 quality step lower than far field blur?)
        VertexShader = VS_Blur; PixelShader = GaussianBlurPass1; RenderTarget = pGaussianBlurTexH;
    }
    pass
    {
        VertexShader = VS_Blur; PixelShader = GaussianBlurPass2; RenderTarget = pGaussianBlurTex;
    }


	pass
    {
        VertexShader = VS_Bloom; PixelShader = HighPassFilter; RenderTarget = pBloomTex0;
    }
    
    //Bloom downsample and upsample passes
    #define BLOOM_DOWN_PASS(i) pass { VertexShader = VS_Bloom; PixelShader = BloomDownS##i; RenderTarget = pBloomTex##i; }
    #define BLOOM_UP_PASS(i) pass { VertexShader = VS_Bloom; PixelShader = BloomUpS##i; RenderTarget = pBloomTex##i; ClearRenderTargets = FALSE; BlendEnable = TRUE; BlendOp = 1; SrcBlend = 1; DestBlend = 9; }
    
    BLOOM_DOWN_PASS(1)
    BLOOM_DOWN_PASS(2)
    BLOOM_DOWN_PASS(3)
    BLOOM_DOWN_PASS(4)
    BLOOM_DOWN_PASS(5)
    BLOOM_DOWN_PASS(6)
    BLOOM_DOWN_PASS(7)
    BLOOM_DOWN_PASS(8)

    BLOOM_UP_PASS(7)
    BLOOM_UP_PASS(6)
    BLOOM_UP_PASS(5)
    BLOOM_UP_PASS(4)
    BLOOM_UP_PASS(3)
    BLOOM_UP_PASS(2)
    BLOOM_UP_PASS(1)
    BLOOM_UP_PASS(0)

    
    pass
	{
		VertexShader = PostProcessVS; PixelShader = EffectsPass;
	}
}
