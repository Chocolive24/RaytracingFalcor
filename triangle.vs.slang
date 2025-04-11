//VSInput struct is not necessary in modern HLSL language.
// They are directly passed as parameters to the main function

struct VSOutput {
    float4 position : SV_POSITION; // Name is important
    float3 color : COLOR;
};

VSOutput main(float3 pos : POSITION, float3 color : COLOR)
{
    VSOutput output;
    output.position = float4(pos, 1.0);
    output.color = color;
    return output;
}
