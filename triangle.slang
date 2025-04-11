struct VSOutput {
    float4 position : SV_POSITION;
};

VSOutput vsMain(float3 pos : POSITION)
{
    VSOutput output;
    output.position = float4(pos, 1.0);
    return output;
}

float4 psMain(VSOutput input) : SV_TARGET
{
    return float4(1.0, 0.0, 0.0, 1.0);
}
