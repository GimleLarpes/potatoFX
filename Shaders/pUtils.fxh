//A collection of useful stuff
namespace pUtils
{
static const float PI = 3.1415927;

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

}