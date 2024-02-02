///////////////////////////////////////////////////////////////////////////////////
// pCamera.fx by Gimle Larpes
// A high performance all-in-one shader with many common lens and camera effects.
///////////////////////////////////////////////////////////////////////////////////

#include "ReShade.fxh"
#include "ReShadeUI.fxh"
#include "Oklab.fxh"

//Version check
#if !defined(__RESHADE__) || __RESHADE__ < 50900
    #error "Outdated ReShade installation - ReShade 5.9+ is required"
#endif

uniform int FrameCount < source = "framecount"; >;
uniform float FrameTime < source = "frametime"; >;
static const float PI = pUtils::PI;
static const float EPSILON = pUtils::EPSILON;

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
> = 2;

//DOF
#ifndef DOF_SENSOR_SIZE
    #define DOF_SENSOR_SIZE 36.0
#endif
uniform bool UseDOF <
	ui_type = "bool";
	ui_label = "Enable DOF";
    ui_tooltip = "Use depth of field\n\nMake sure depth is set up correctly using DisplayDepth.fx";
	ui_category = "DOF";
> = false;
uniform float DOFAperture < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.95; ui_max = 22.0;
    ui_label = "Aperture";
    ui_tooltip = "Aperture of the simulated camera";
	ui_category = "DOF";
> = 1.4;
uniform int DOFFocalLength < __UNIFORM_SLIDER_FLOAT1
	ui_min = 12u; ui_max = 85u;
    ui_label = "Focal length";
    ui_tooltip = "Focal length of the simulated camera";
	ui_category = "DOF";
    ui_units = " mm";
> = 35u;
uniform bool UseDOFAF <
	ui_type = "bool";
	ui_label = "Autofocus";
    ui_tooltip = "Use autofocus";
	ui_category = "DOF";
> = true;
uniform float DOFFocusSpeed < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 10.0;
    ui_label = "Focus speed";
    ui_tooltip = "Focus speed in seconds";
	ui_category = "DOF";
    ui_units = " s";
> = 1.0;
uniform float DOFFocusPx < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
    ui_label = "Focus point X";
    ui_tooltip = "AF focus point position X (width)\nLeft side = 0\nRight side = 1";
	ui_category = "DOF";
> = 0.5;
uniform float DOFFocusPy < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
    ui_label = "Focus point Y";
    ui_tooltip = "AF focus point position Y (height)\nTop side = 0\nBottom side = 1";
	ui_category = "DOF";
> = 0.5;
uniform float DOFManualFocusDist < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
    ui_label = "Manual focus";
    ui_tooltip = "Manual focus distance, only used when autofocus is disabled";
	ui_category = "DOF";
> = 0.5;
uniform int BokehQuality < __UNIFORM_RADIO_INT1
	ui_label = "Blur quality";
	ui_tooltip = "Quality and size of gaussian blur";
	ui_items = "High quality\0Medium quality\0Fast\0";
	ui_category = "DOF";
> = 2;
uniform bool DOFDebug <
	ui_type = "bool";
	ui_label = "AF debug";
    ui_tooltip = "Display AF point";
	ui_category = "DOF";
> = false;

//Fish eye
uniform bool UseFE <
	ui_type = "bool";
	ui_label = "Fisheye";
    ui_tooltip = "Adds fisheye distortion";
	ui_category = "Fisheye";
> = false;
uniform int FEFoV < __UNIFORM_SLIDER_FLOAT1
	ui_min = 20u; ui_max = 160u;
    ui_label = "FOV";
    ui_tooltip = "FOV in degrees\n\n(set to in-game FOV)";
	ui_category = "Fisheye";
    ui_units = "°";
> = 90u;
uniform float FECrop < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
    ui_label = "Crop";
    ui_tooltip = "How much to crop into the image\n\n(0 = circular, 1 = full-frame)";
	ui_category = "Fisheye";
> = 0.0;
uniform bool FEVFOV <
	ui_type = "bool";
	ui_label = "Use vertical FOV";
    ui_tooltip = "Assume FOV is vertical\n\n(enable if FOV is given as vertical FOV)";
	ui_category = "Fisheye";
> = false;

//Glass imperfections
uniform float GeoIStrength < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 4.0;
    ui_label = "Glass quality";
    ui_tooltip = "Amount of surface lens imperfections";
	ui_category = "Lens Imperfections";
> = 0.25;

//Chromatic aberration
uniform float CAStrength < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
    ui_label = "CA amount";
    ui_tooltip = "Amount of chromatic aberration";
	ui_category = "Lens Imperfections";
> = 0.04;

//Dirt
uniform float DirtStrength < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 1.0;
    ui_label = "Dirt amount";
    ui_tooltip = "Amount of dirt on the lens";
	ui_category = "Lens Imperfections";
> = 0.12;
uniform float DirtScale < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.5; ui_max = 2.5;
    ui_label = "Dirt scale";
    ui_tooltip = "Scaling of dirt texture";
	ui_category = "Lens Imperfections";
> = 1.35;

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
> = 0.225;
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
> = 0.18;
uniform int NoiseType < __UNIFORM_RADIO_INT1
	ui_label = "Noise type";
	ui_tooltip = "Type of noise to use";
	ui_items = "Film grain\0Color noise\0";
	ui_category = "Noise";
> = 0;

//Auto exposure
#ifndef AE_RANGE
    #define AE_RANGE 1.0
#endif
#ifndef AE_MIN_BRIGHTNESS
    #define AE_MIN_BRIGHTNESS 0.05
#endif
uniform bool UseAE <
	ui_type = "bool";
	ui_label = "Auto exposure";
    ui_tooltip = "Enable auto exposure";
	ui_category = "Auto Exposure";
> = false;
uniform float AESpeed < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.0; ui_max = 10.0;
    ui_label = "Speed";
    ui_tooltip = "Auto exposure adaption speed in seconds";
	ui_category = "Auto Exposure";
    ui_units = " s";
> = 1.0;
uniform float AEGain < __UNIFORM_SLIDER_FLOAT1
	ui_min = 0.1; ui_max = 1.0;
    ui_label = "Gain";
    ui_tooltip = "Auto exposure gain";
	ui_category = "Auto Exposure";
> = 0.5;
uniform float AETarget < __UNIFORM_SLIDER_FLOAT1
	ui_min = AE_MIN_BRIGHTNESS; ui_max = 1.0;
    ui_label = "Target";
    ui_tooltip = "Exposure target";
	ui_category = "Auto Exposure";
> = 0.5;


//Performance
uniform bool UseApproximateTransforms <
	ui_type = "bool";
	ui_label = "Fast colorspace transform";
    ui_tooltip = "Use less accurate approximations instead of the full transform functions";
	ui_category = "Performance";
> = false;


#ifndef _BUMP_MAP_RESOLUTION
    #define _BUMP_MAP_RESOLUTION 32
#endif
#ifndef _BUMP_MAP_SCALE
    #define _BUMP_MAP_SCALE 4
#endif
#ifndef _BUMP_MAP_SOURCE
    #define _BUMP_MAP_SOURCE "pBumpTex.png"
#endif

#ifndef _DIRT_MAP_RESOLUTION
    #define _DIRT_MAP_RESOLUTION 1024
#endif
#ifndef _DIRT_MAP_SOURCE
    #define _DIRT_MAP_SOURCE "pDirtTex.png"
#endif

static const int BUFFER_MIP_LEVELS = 1; //calculate log2 of buffer width and height and select lowest one

texture pStorageTex < pooled = true; > { Width = 1; Height = 1; Format = RG16F; };
sampler spStorageTex { Texture = pStorageTex; };
texture pStorageTexC < pooled = true; > { Width = 1; Height = 1; Format = RG16F; };
sampler spStorageTexC { Texture = pStorageTexC; };

texture pBumpTex < source = _BUMP_MAP_SOURCE; pooled = true; > { Width = _BUMP_MAP_RESOLUTION; Height = _BUMP_MAP_RESOLUTION; Format = RG8; };
sampler spBumpTex { Texture = pBumpTex; AddressU = REPEAT; AddressV = REPEAT;};

texture pDirtTex < source = _DIRT_MAP_SOURCE; pooled = true; > { Width = _DIRT_MAP_RESOLUTION; Height = _DIRT_MAP_RESOLUTION; Format = RGBA8; };
sampler spDirtTex { Texture = pDirtTex; AddressU = REPEAT; AddressV = REPEAT;};

texture pLinearTex < pooled = true; > { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; MipLevels = BUFFER_MIP_LEVELS; };
sampler spLinearTex { Texture = pLinearTex;};

texture pBokehBlurTex < pooled = true; > { Width = BUFFER_WIDTH/2; Height = BUFFER_HEIGHT/2; Format = RGBA16F; };
sampler spBokehBlurTex { Texture = pBokehBlurTex;};
texture pGaussianBlurTex < pooled = true; > { Width = BUFFER_WIDTH/2; Height = BUFFER_HEIGHT/2; Format = RGBA16F; };
sampler spGaussianBlurTex { Texture = pGaussianBlurTex;};

texture pBloomTex0 < pooled = true; > { Width = BUFFER_WIDTH/2; Height = BUFFER_HEIGHT/2; Format = RGBA16F; }; //LOD STUFF???------------------------------------------------------
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

    //Weights and offsets, yoinked from GaussianBlur.fx by Ioxa
    [branch]
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
    [branch]
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
    [branch]
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

float3 BokehBlur(sampler s, float2 texcoord, float size)
{
    float brightness_compensation;
    float size_compensation;

    switch (BokehQuality)
    {
        case 0:
        {
            brightness_compensation = 0.010989010989;
            size_compensation = 1.0;
        } break;
        case 1:
        {
            brightness_compensation = 0.027027027027;
            size_compensation = 1.666666666667;
        } break;
        case 2:
        {
            brightness_compensation = 0.0769230769231;
            size_compensation = 2.5;
        } break;
    }
    
    float2 TEXEL_SIZE = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);
    float2 step_length = TEXEL_SIZE * size * size_compensation;

    static const float MAX_VARIANCE = 0.1;
    float2 variance = FrameCount * float2(sin(2000 * PI * texcoord.x), cos(2000 * PI * texcoord.y)) * 1000.0;
    variance %= MAX_VARIANCE;
    variance = 1 + variance - MAX_VARIANCE / 2.0;
    

    //Sample points (91 points, 5 rings)
    //Fast (low quality, 13 points, 2 rings)
    float3 color = tex2D(s, texcoord).rgb;
    color += tex2D(s, texcoord + step_length * float2(0, 4) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(3.4641, 2) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(3.4641, -2) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(0, -4) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(-3.4641, -2) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(-3.4641, 2) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(0, 8) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(6.9282, 4) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(6.9282, -4) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(0, -8) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(-6.9282, -4) * variance).rgb;
    color += tex2D(s, texcoord + step_length * float2(-6.9282, 4) * variance).rgb;

    [branch]
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
    [branch]
    if (BokehQuality < 2) //Medium quality (37 points, 3 rings)
    {
        //Second ring
        color += tex2D(s, texcoord + step_length * float2(4, 6.9282) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(8, 0) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(4, -6.9282) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-4, -6.9282) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-8, 0) * variance).rgb;
        color += tex2D(s, texcoord + step_length * float2(-4, 6.9282) * variance).rgb;
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
    if (UseDOF)
    {
        float depth = 1;//tex2Dfetch(spStorageTex, 0).x; //Why doesn't this work? - "Cannot map to vs_5_0 instruction set", but reshade get linearized depth works
        //(UseDOFAF) ? tex2Dfetch(spStorageTex, 0).x : DOFManualFocusDist; //sample af depth fromaf texture, af texture samples from af texture and depthtex
        float scale = ((float(DOFFocalLength*DOFFocalLength) / 10000) * DOF_SENSOR_SIZE / 18) / ((1 + depth*depth) * DOFAperture) * length(float2(BUFFER_WIDTH, BUFFER_HEIGHT))/2048;
        o.uv.z = depth;
        o.uv.w = scale;
    }
    else
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

float2 StoragePass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    [branch] //TEST TO SEE IF THIS IMPROVES OR HAMPERS PERFORMANCE
    if (!((UseDOFAF && UseDOF) || UseAE))
    {
        discard;
    }

    float2 data = tex2Dfetch(spStorageTexC, 0).xy;
    //Sample DOF
    data.x = lerp(data.x, ReShade::GetLinearizedDepth(float2(DOFFocusPx, DOFFocusPy)), min(FrameTime / (DOFFocusSpeed * 1000 + EPSILON), 1.0));

    //Sample AE
    data.y = lerp(data.y, max(min(2.0 * Oklab::Luma_RGB(tex2Dlod(spLinearTex, float4(0.5, 0.5, 0, BUFFER_MIP_LEVELS - 1)).rgb) / Oklab::HDR_PAPER_WHITE, AE_RANGE), AE_MIN_BRIGHTNESS), min(FrameTime / (AESpeed * 1000 + EPSILON), 1.0));
    return data.xy;
}
float2 StoragePassC(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    return tex2Dfetch(spStorageTex, 0).xy;
}

//Blur
float3 GaussianBlurPass1(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    return GaussianBlur(spLinearTex, texcoord, BlurStrength, float2(1.0, 0.0));
}
float3 GaussianBlurPass2(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    return GaussianBlur(spBokehBlurTex, texcoord, BlurStrength, float2(0.0, 1.0));
}

//DOF
float4 BokehBlurPass(float4 vpos : SV_Position, float4 texcoord : TexCoord) : COLOR
{
    float size = abs(ReShade::GetLinearizedDepth(texcoord.xy) - texcoord.z) * texcoord.w;
    float4 color;
    color.rgb = (BlurStrength != 0.0) ? BokehBlur(spGaussianBlurTex, texcoord.xy, size) : BokehBlur(spLinearTex, texcoord.xy, size);
    color.a = size;
    
    return color;
}

//Bloom, based on: https://catlikecoding.com/unity/tutorials/advanced-rendering/bloom/
float3 HighPassFilter(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    float3 color = (UseDOF) ? tex2D(spBokehBlurTex, texcoord).rgb : (BlurStrength == 0.0) ? tex2D(spLinearTex, texcoord).rgb : tex2D(spGaussianBlurTex, texcoord).rgb;

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
    return BoxSample(spBloomTex0, texcoord, 1.0);
}
float3 BloomDownS2(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    return BoxSample(spBloomTex1, texcoord, 1.0);
}
float3 BloomDownS3(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    return BoxSample(spBloomTex2, texcoord, 1.0);
}
float3 BloomDownS4(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    return BoxSample(spBloomTex3, texcoord, 1.0);
}
float3 BloomDownS5(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    return BoxSample(spBloomTex4, texcoord, 1.0);
}
float3 BloomDownS6(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    return BoxSample(spBloomTex5, texcoord, 1.0);
}
float3 BloomDownS7(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    return BoxSample(spBloomTex6, texcoord, 1.0);
}
float3 BloomDownS8(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    return BoxSample(spBloomTex7, texcoord, 1.0);
}
//Upsample
float3 BloomUpS7(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    return BoxSample(spBloomTex8, texcoord, 0.5) * 0.25;
}
float3 BloomUpS6(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    return BoxSample(spBloomTex7, texcoord, 0.5);
}
float3 BloomUpS5(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    return BoxSample(spBloomTex6, texcoord, 0.5);
}
float3 BloomUpS4(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    return BoxSample(spBloomTex5, texcoord, 0.5);
}
float3 BloomUpS3(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    return BoxSample(spBloomTex4, texcoord, 0.5);
}
float3 BloomUpS2(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    return BoxSample(spBloomTex3, texcoord, 0.5);
}
float3 BloomUpS1(float4 vpos : SV_Position, float2 texcoord : TexCoord) : COLOR
{
    return BoxSample(spBloomTex2, texcoord, 0.5) + tex2D(spBloomTex1, texcoord).rgb;
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



float3 CameraPass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
    static const float INVNORM_FACTOR = Oklab::INVNORM_FACTOR;
    static const float2 TEXEL_SIZE = float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT);
    float2 radiant_vector = texcoord.xy - 0.5;
    float2 texcoord_clean = texcoord.xy;
	
    ////Effects
    //Fisheye
    if (UseFE)
    {
        float diagonal_length = length(pUtils::ASPECT_RATIO);

        float fov_factor = PI * FEFoV/360;
        if (FEVFOV)
        {
            fov_factor = atan(tan(fov_factor) * BUFFER_ASPECT_RATIO);
        }
        float fit_fov = sin(atan(tan(fov_factor) * diagonal_length));
        float crop_value = lerp(1.0 + (diagonal_length - 1.0) * cos(fov_factor), diagonal_length, FECrop * pow(sin(fov_factor), 6.0));//This is stupid and there is a better way.

        //Circularize radiant vector and apply cropping
        float2 cn_radiant_vector = 2 * radiant_vector * pUtils::ASPECT_RATIO / crop_value * fit_fov;

        if (length(cn_radiant_vector) < 1.0)
        {
            //Calculate z-coordinate and angle
            float z = sqrt(1.0 - cn_radiant_vector.x*cn_radiant_vector.x - cn_radiant_vector.y*cn_radiant_vector.y);
            float theta = acos(z) / fov_factor;

            float2 d = normalize(cn_radiant_vector);
            texcoord = (theta * d) / (2 * pUtils::ASPECT_RATIO) + 0.5;
        } 
    }

    //Glass imperfections
    [branch]
    if (GeoIStrength != 0.0)
    {
        float2 bump = 0.6666667 * tex2D(spBumpTex, texcoord * _BUMP_MAP_SCALE).xy + 0.33333334 * tex2D(spBumpTex, texcoord * _BUMP_MAP_SCALE * 3).xy;
    
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
        float4 dof_data = tex2D(spBokehBlurTex, texcoord);
        float dof_mix = min(10 * dof_data.a, 1.0);
        color = lerp(color, dof_data.rgb, dof_mix);
    }

    //Chromatic aberration
    [branch]
    if (CAStrength != 0.0)
    {
        float3 influence = float3(-0.04, 0.0, 0.03);

        float2 step_length = CAStrength * radiant_vector;
        color.r = (UseDOF) ? tex2D(spBokehBlurTex, texcoord + step_length * influence.r).r : lerp(tex2D(spLinearTex, texcoord + step_length * influence.r).r, tex2D(spGaussianBlurTex, texcoord + step_length * influence.r).r, blur_mix);
        color.b = (UseDOF) ? tex2D(spBokehBlurTex, texcoord + step_length * influence.b).b : lerp(tex2D(spLinearTex, texcoord + step_length * influence.b).b, tex2D(spGaussianBlurTex, texcoord + step_length * influence.b).b, blur_mix);
    }

    //Dirt
    [branch]
    if (DirtStrength != 0.0)
    {
        float3 weight = 0.15 * length(radiant_vector) * tex2D(spBloomTex6, -radiant_vector + 0.5).rgb + 0.25 * tex2D(spBloomTex3, texcoord.xy).rgb;
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
        float weight = clamp((length(float2(abs(texcoord_clean.x - 0.5) * rcp(VignetteWidth), abs(texcoord_clean.y - 0.5))) - VignetteInnerRadius) / (VignetteOuterRadius - VignetteInnerRadius), 0.0, 1.0);
        color.rgb *= 1 - VignetteStrength * weight;
    }

    //Noise
    [branch]
    if (NoiseStrength != 0.0)
    {
        static const float NOISE_CURVE = max(INVNORM_FACTOR * 0.025, 1.0);

        float noise_speed = 1;
        float noise_coord = texcoord_clean;
        if (NoiseType == 1)
        {
           noise_coord /= PI;
           noise_speed = 60;
        }

        //REDO NOISE

        float t = FrameCount * 0.456035462415 * noise_speed;
	    t %= 10000;
	    float luma = Oklab::Luma_RGB(color);


	    float seed = dot(texcoord_clean, float2(12.9898 * t, 78.233)); //12.9898, 78.233
	    float uniform_noise1 = frac((sin(seed * t) * 0.5 + 0.5) * t);// * 413.458333333 * t
	    float uniform_noise2 = frac((cos(seed * t) * 0.5 + 0.5) * t);// * 524.894736842 * t

	    uniform_noise1 = (uniform_noise1 < EPSILON) ? EPSILON : uniform_noise1; //fix log(0)
		
	    float r = sqrt(-log(uniform_noise1));
	    r = (uniform_noise1 < EPSILON) ? PI : r; //fix log(0) - PI happened to be the right answer for uniform_noise == ~ 0.0000517
	    float theta = 2.0 * PI * uniform_noise2;
	
	    float gauss_noise1 = r * cos(theta);
	    float weight = (NoiseStrength * NoiseStrength) * NOISE_CURVE / (luma * (1 + rcp(INVNORM_FACTOR)) + 2.0); //Multiply luma to simulate a wider dynamic range

	    if (NoiseType == 1)
        {   //Color noise
            float gauss_noise2 = r * sin(theta);
	        float gauss_noise3 = (gauss_noise1 + gauss_noise2) * 0.7;
            color.rgb = color.rgb * (1-weight) + Oklab::Saturate_RGB(float3(gauss_noise1, gauss_noise2, gauss_noise3)) * weight; //Change this to be color * (1-weight + noise * weight)
        }
        else
        {   //Film grain
            color.rgb = color.rgb * (1-weight) + (gauss_noise1 - 0.225) * weight;
        }
        //color.rgb = uniform_noise1; //DEBUG
    }

    //Auto exposure
    if (UseAE)
    {
        color *= lerp(1.0, AETarget / tex2Dfetch(spStorageTex, 0).y, AEGain);
    }
    
    //DEBUG stuff
    if (DOFDebug)
    {
        if (pow((texcoord_clean.x - DOFFocusPx) * BUFFER_ASPECT_RATIO, 2.0) + pow(texcoord_clean.y - DOFFocusPy, 2.0) < 0.0001)
        {
            color.rgb = float3(1.0, 0, 0) * INVNORM_FACTOR;
        }
    }

    if (!Oklab::IS_HDR) { color = Oklab::Saturate_RGB(color); }
	color = (UseApproximateTransforms)
		? Oklab::Fast_Linear_to_DisplayFormat(color)
		: Oklab::Linear_to_DisplayFormat(color);
	return color.rgb;
}

technique Camera <ui_tooltip = 
"A high performance all-in-one shader with many common camera and lens effects.\n\n"
"(HDR compatible)";>
{
    pass
    {
        VertexShader = PostProcessVS; PixelShader = LinearizePass; RenderTarget = pLinearTex;
    }
    pass
    {
        VertexShader = PostProcessVS; PixelShader = StoragePass; RenderTarget = pStorageTex;
    }
    pass
    {
        VertexShader = PostProcessVS; PixelShader = StoragePassC; RenderTarget = pStorageTexC;
    }


	pass
    {
        VertexShader = VS_Blur; PixelShader = GaussianBlurPass1; RenderTarget = pBokehBlurTex;
    }
    pass
    {
        VertexShader = VS_Blur; PixelShader = GaussianBlurPass2; RenderTarget = pGaussianBlurTex;
    }


    pass
    {
        VertexShader = VS_DOF; PixelShader = BokehBlurPass; RenderTarget = pBokehBlurTex;
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
		VertexShader = PostProcessVS; PixelShader = CameraPass;
	}
}