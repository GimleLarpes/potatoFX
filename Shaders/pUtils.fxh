//A collection of useful stuff
uniform int FrameCount < source = "framecount"; >;


namespace pUtils
{
//Constants
static const float PI = 3.1415927;
static const float EPSILON = 1e-10;
static const float2 ASPECT_RATIO = float2(1.0, 1.0/BUFFER_ASPECT_RATIO);


//--fastatan2
float fastatan2(float y, float x)//error < 0.2 degrees, saves about 40% vs atan2 developed by Lord of Lunacy and Marty McFly
{
    bool a = abs(y) < abs(x);    
    float i = (a) ? (y * rcp(x)) : (x * rcp(y));    
    i = i * (1.0584 + abs(i) * -0.273);
    float piadd = y > 0 ? PI : -PI;     
    i = a ? (x < 0 ? piadd : 0) + i : 0.5 * piadd - i;
    return i;
}

//--cbrt
float cbrt(float v)
{
    return sign(v) * pow(abs(v), 0.33333333);
}
float3 cbrt(float3 v)
{
    return sign(v) * pow(abs(v), 0.33333333);
}

//--clerp, lerps the shortest way between two angles
float clerp(float v, float t, float w)
{   
    const float d = v - t;
    t = (abs(d) > PI)
        ? d - sign(d) * PI
        : t;
    return (t - v) * w + v;
}

//--cdistance, returns the shortest distance between two angles
float cdistance(float v, float t)
{   
    float d = v - t;
    d = (abs(d) > PI)
        ? d - sign(d) * PI
        : d;
    return abs(d);
}

//--wnoise, returns time variable white noise
float wnoise(float2 uv, float2 d)
{
    float t = float(FrameCount % 1000 + 1);
    return frac(sin(dot(uv - 0.5, d) * t) * 143758.5453);
}

}