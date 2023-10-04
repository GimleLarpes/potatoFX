///////////////////////////////////////////////////////////////////////////////////
// Oklab.fxh by Gimle Larpes
// My implementation of Oklab as described in:
// https://bottosson.github.io/posts/oklab/
//
// Conversions are between sRGB <-> Linear RGB <-> CIE-XYZ <-> Oklab <-> Lch
///////////////////////////////////////////////////////////////////////////////////
#include "pUtils.fxh"

namespace Oklab
{
    //sRGB-Linear conversions
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

    //Transformations
    static const float3x3 RGB_to_XYZ = float3x3(
        0.4124564, 0.3575761, 0.1804375,
        0.2126729, 0.7151522, 0.0721750,
        0.0193339, 0.1191920, 0.9503041
    );
    static const float3x3 XYZ_to_RGB = float3x3(
        3.2404542, -1.5371385, -0.4985314,
        -0.9692660, 1.8760108, 0.0415560,
        0.0556434, -0.2040259, 1.0572252
    );

    float3 XYZ_to_Oklab(float3 c)
    {
        c = c * float3x3(//M_1
            0.8189330, 0.3618667, -0.1288597,
            0.0329845, 0.9293119, 0.0361456,
            0.0482003, 0.2643663, 0.6338517
        );

        c = pow(c, rcp(3));

        c = c * float3x3(//M_2
            0.2104543, 0.7936178, -0.0040720,
            1.9779985, -2.4285922, 0.4505937,
            0.0259040, 0.7827718, -0.8086758
        );
        return c;
    }
    float3 Oklab_to_XYZ(float3 c)
    {
        c = c * float3x3(//M_2^-1
            1.0, 0.3963378, 0.2158038,
            1.0, -0.1055613, -0.0638542,
            1.0, -0.0894842, -1.2914855
        );

        c = pow(c, 3);

        c = c * float3x3(//M_1^-1
            1.2270139, -0.5578000, 0.2812561,
            -0.0405802, 1.1122569, -0.0716767,
            -0.0763813, -0.4214820, 1.5861632
        );
        return c;
    }
    float3 RGB_to_Oklab(float3 c)
    {
        c = c * float3x3(
            0.4122215, 0.5363325, 0.0514460,
            0.2119035, 0.6806995, 0.1073970,
            0.0883025, 0.2817188, 0.6299787
        );

        c = pow(c, rcp(3));

        c = c * float3x3(
            0.2104543, 0.7936178, -0.0040720,
            1.9779985, -2.4285922, 0.4505937,
            0.0259040, 0.7827718, -0.8086758
        );
        return c;
    }
    float3 Oklab_to_RGB(float3 c)
    {
        c = c * float3x3(
            1.0, 0.3963378, 0.2158038,
            1.0, -0.1055613, -0.0638542,
            1.0, -0.0894842, -1.2914855
        );

        c = pow(c, 3);

        c = c * float3x3(
            4.0767417, -3.3077116, 0.2309699,
            -1.2684380, 2.6097574, -0.3413194,
            -0.0041961, -0.7034186, 1.7076147
        );
        return c;
    }
    float3 Oklab_to_LCh(float3 c.xyz)
    {
        float a = c.y;

        c.y = length(c.yz);
        c.z = pUtils::fastatan2(c.z, a);
        return c.xyz;
    }
    float3 LCh_to_Oklab(float3 c.xyz)
    {
        float h = c.z;

        c.z = c.y * sin(h);
        c.y = c.y * cos(h);
        return c.xyz;
    }

    //Shortcut functions -- MAYBE IMPLEMENT DIRECT COVERSIONS BETWEEN RGB AND OKLAB?
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
}