///////////////////////////////////////////////////////////////////////////////////
// Oklab.fxh by Gimle Larpes
// My implementation of Oklab as described in:
// https://bottosson.github.io/posts/oklab/
//
// Sources for HDR transfer functions:
// ST2084:  https://ieeexplore.ieee.org/stamp/stamp.jsp?tp=&arnumber=7291452
// HLG:     https://www.itu.int/rec/R-REC-BT.2100-2-201807-I/en
// scRGB:   https://en.wikipedia.org/wiki/ScRGB
//
// Conversions are between sRGB <-> Linear RGB <-> CIE-XYZ <-> Oklab <-> LCh
///////////////////////////////////////////////////////////////////////////////////
#include "pUtils.fxh"

namespace Oklab
{
    //Conversions to and from linear
    //sRGB
    float3 sRGB_to_Linear(float3 c)
    {
        return (c < 0.04045)
            ? c / 12.92
            : pow(abs((c + 0.055) / 1.055), 2.4);
    }
    float3 Linear_to_sRGB(float3 c)
    {
        return (c < 0.0031308)
            ? c * 12.92
            : 1.055 * pow(abs(c), rcp(2.4)) - 0.055;
    }
    //Automatic conversions
    float3 DisplayFormat_to_Linear(float3 c)
    {   
        #if BUFFER_COLOR_SPACE == 2//scRGB
            c = c;

        #elif BUFFER_COLOR_SPACE == 3//HDR10 ST2084
            const float m1 = 0.15930176; // 1305/8192
            const float m2 = 78.84375;   // 2523/32
            const float c1 = 0.8359375;  // 107/128
            const float c2 = 18.8515625; // 2413/128
            const float c3 = 18.6875;    // 2392/128
            float3 p = pow(abs(c), rcp(m2));
            c = 10000 * pow(abs(max(p - c1, 0) / (c2 - c3 * p), 0.0) , rcp(m1)); 

        #elif BUFFER_COLOR_SPACE == 4 //HDR10 HLG
            const float a = 0.17883277;
            const float b = 0.28466892;
            const float c4 = 0.55991073;
            c = (c > 0.5)
                ? (exp((c + c4) / a) + b) / 12.0
                : (c * c) / 3.0;

        #else //Assume SDR, sRGB
            c = (c < 0.04045)
                ? c / 12.92
                : pow(abs((c + 0.055) / 1.055), 2.4);
        #endif
            return c;
    }
    float3 Linear_to_DisplayFormat(float3 c)
    {   
        #if BUFFER_COLOR_SPACE == 2//scRGB
            c = c;

        #elif BUFFER_COLOR_SPACE == 3 //HDR10 ST2084
            const float m1 = 0.15930176; // 1305/8192
            const float m2 = 78.84375;   // 2523/32
            const float c1 = 0.8359375;  // 107/128
            const float c2 = 18.8515625; // 2413/128
            const float c3 = 18.6875;    // 2392/128
            float y = pow(abs(c * 0.0001), m1);
            c = pow(abs((c1 + c2 * y) / (1 + c3 * y)), m2);

        #elif BUFFER_COLOR_SPACE == 4 //HDR10 HLG
            const float a = 0.17883277;
            const float b = 0.28466892;
            const float c4 = 0.55991073;
            c = (c < 0.08333333) // 1/12
                ? sqrt(3 * c)
                : a * log(12 * c - b) + c4;

        #else //Assume SDR, sRGB
            c = (c < 0.0031308)
                ? c * 12.92
                : 1.055 * pow(abs(c), rcp(2.4)) - 0.055;
        #endif
            return c;
    }
    //Utility functions for HDR
    float Normalize(float v)
    {   
        #if BUFFER_COLOR_SPACE == 2//scRGB
            v = v * 0.125;
        #elif BUFFER_COLOR_SPACE == 3//HDR10 ST2084
            v = v * 0.0001;
        #elif BUFFER_COLOR_SPACE == 4 //HDR10 HLG
            v = v;
        #else //Assume SDR
            v = v;
        #endif
            return v;
    }float3 Normalize(float3 v)
    {   
        #if BUFFER_COLOR_SPACE == 2//scRGB
            v = v * 0.125;
        #elif BUFFER_COLOR_SPACE == 3//HDR10 ST2084
            v = v * 0.0001;
        #elif BUFFER_COLOR_SPACE == 4 //HDR10 HLG
            v = v;
        #else //Assume SDR
            v = v;
        #endif
            return v;
    }
    float get_InvNorm_Factor()
    {   
        float v;
        #if BUFFER_COLOR_SPACE == 2//scRGB
            v = 8.0;
        #elif BUFFER_COLOR_SPACE == 3//HDR10 ST2084
            v = 10000.0;
        #elif BUFFER_COLOR_SPACE == 4 //HDR10 HLG
            v = 1.0;
        #else //Assume SDR
            v = 1.0;
        #endif
            return v;
    }

    //Transformations
    float3 RGB_to_XYZ(float3 c)
    {
        return mul(float3x3(
            0.4124564, 0.3575761, 0.1804375,
            0.2126729, 0.7151522, 0.0721750,
            0.0193339, 0.1191920, 0.9503041
        ), c);
    }
    float3 XYZ_to_RGB(float3 c)
    {
        return mul(float3x3(
            3.2404542, -1.5371385, -0.4985314,
            -0.9692660, 1.8760108, 0.0415560,
            0.0556434, -0.2040259, 1.0572252
        ), c);
    }

    float3 XYZ_to_Oklab(float3 c)
    {
        c = mul(float3x3(//M_1
            0.8189330101, 0.3618667424, -0.1288597137,
            0.0329845436, 0.9293118715, 0.0361456387,
            0.0482003018, 0.2643662691, 0.6338517070
        ), c);

        c = pow(abs(c), rcp(3));

        c = mul(float3x3(//M_2
            0.2104542553, 0.7936177850, -0.0040720468,
            1.9779984951, -2.4285922050, 0.4505937099,
            0.0259040371, 0.7827717662, -0.8086757660
        ), c);
        return c;
    }
    float3 Oklab_to_XYZ(float3 c)
    {
        c = mul(float3x3(//M_2^-1
            0.9999999985, 0.3963377922, 0.2158037581,
            1.0000000089, -0.1055613423, -0.0638541748,
            1.0000000547, -0.0894841821, -1.2914855379
        ), c);

        c = c * c * c;

        c = mul(float3x3(//M_1^-1
            1.2270138511, -0.5577999807, 0.2812561490,
            -0.0405801784, 1.1122568696, -0.0716766787,
            -0.0763812845, -0.4214819784, 1.5861632204
        ), c);
        return c;
    }
    float3 RGB_to_Oklab(float3 c)
    {
        c = mul(float3x3(
            0.4122214708, 0.5363325363, 0.0514459929,
            0.2119034982, 0.6806995451, 0.1073969566,
            0.0883024619, 0.2817188376, 0.6299787005
        ), c);

        c = pow(abs(c), rcp(3));

        c = mul(float3x3(
            0.2104542553, 0.7936177850, -0.0040720468,
            1.9779984951, -2.4285922050, 0.4505937099,
            0.0259040371, 0.7827717662, -0.8086757660
        ), c);
        return c;
    }
    float3 Oklab_to_RGB(float3 c)
    {
        c = mul(float3x3(
            1.0, 0.3963377774, 0.2158037573,
            1.0, -0.1055613458, -0.0638541728,
            1.0, -0.0894841775, -1.2914855480
        ), c);

        c = c * c * c;

        c = mul(float3x3(
            4.0767416621, -3.3077115913, 0.2309699292,
            -1.2684380046, 2.6097574011, -0.3413193965,
            -0.0041960863, -0.7034186147, 1.7076147010
        ), c);
        return c;
    }
    float3 Oklab_to_LCh(float3 c)
    {
        float a = c.y;

        c.y = length(c.yz);
        c.z = pUtils::fastatan2(c.z, a);
        return c;
    }
    float3 LCh_to_Oklab(float3 c)
    {
        float h = c.z;

        c.z = c.y * sin(h);
        c.y = c.y * cos(h);
        return c;
    }


    //Shortcut functions
    float3 sRGB_to_Oklab(float3 c)
    {
        return RGB_to_Oklab(sRGB_to_Linear(c));
    }
    float3 Oklab_to_sRGB(float3 c)
    {
        return Linear_to_sRGB(Oklab_to_RGB(c));
    }
    float3 sRGB_to_LCh(float3 c)
    {
        return Oklab_to_LCh(RGB_to_Oklab(sRGB_to_Linear(c)));
    }
    float3 LCh_to_sRGB(float3 c)
    {
        return Linear_to_sRGB(Oklab_to_RGB(LCh_to_Oklab(c)));
    }
    float3 RGB_to_LCh(float3 c)
    {
        return Oklab_to_LCh(RGB_to_Oklab(c));
    }
    float3 LCh_to_RGB(float3 c)
    {
        return Oklab_to_RGB(LCh_to_Oklab(c));
    }
    float3 DisplayFormat_to_Oklab(float3 c)
    {
        return RGB_to_Oklab(DisplayFormat_to_Linear(c));
    }
    float3 Oklab_to_DisplayFormat(float3 c)
    {
        return Linear_to_DisplayFormat(Oklab_to_RGB(c));
    }
    float3 DisplayFormat_to_LCh(float3 c)
    {
        return Oklab_to_LCh(RGB_to_Oklab(DisplayFormat_to_Linear(c)));
    }
    float3 LCh_to_DisplayFormat(float3 c)
    {
        return Linear_to_DisplayFormat(Oklab_to_RGB(LCh_to_Oklab(c)));
    }
}