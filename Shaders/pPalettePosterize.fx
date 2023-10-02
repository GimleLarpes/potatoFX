///////////////////////////////////////////////////////////////////////////////////
// pPalettePosterize.fx by Gimle Larpes
// Posterizes an image to a custom color palette.
///////////////////////////////////////////////////////////////////////////////////

#include "ReShade.fxh"
#include "ReShadeUI.fxh"
uniform int NumColors < __UNIFORM_SLIDER_INT
	ui_min = 2; ui_max = 32;
    ui_tooltip = "Number of colours";
> = 8;

uniform int FrameCount < source = "framecount"; >; //use to vary dithering every frame

float3 PosterizeDitherPass(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float3 color = tex2D(ReShade::BackBuffer, texcoord).rgb;
	const float PI = 3.1415927;
	
	float t = FrameCount * 0.2783;
	t %= 10000; //protect against large numbers
	

	
	color.rgb = color.rgb;
	
	return color.rgb;
}

technique PalettePosterize <ui_tooltip = "Posterizes an image to a custom color palette.";>
{
	pass
	{
		VertexShader = PostProcessVS; PixelShader = PosterizeDitherPass;
	}
}
