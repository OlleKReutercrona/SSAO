#include "common.hlsli"
#include "DeferredCommons.hlsli"

#define NUM_SSAO_SAMPLES 32

struct SSAOOutput
{
    float4 aoTexture : SV_TARGET;
};

cbuffer SSAOData : register(b5)
{
    float4 SSAOSamples[NUM_SSAO_SAMPLES];
    float SSAORadius;
    int SSAONumOfSamples;
    float2 SSAOPADDING;
}

Texture2D NoiseTexture : register(t10);

SSAOOutput main(PixelInput aInput)
{
    SSAOOutput output;
    
    const float4 worldPos = worldPositionTex.Sample(SSAOSampler, aInput.texCoord).rgba;
    if (worldPos.a == 0.0f)
    {
        discard;
    }

    // returns the vertex normals 
    const float3 normal = normalize(2.0f * ambientOcclusionTex.Sample(SSAOSampler, aInput.texCoord).gba - 1.0f);
        
    const int nscale = 4;
    const float ar = 16 / 9;

    int2 noiseScale = clientResolution;
    noiseScale.x = int(noiseScale.x / nscale);
    noiseScale.y = float(noiseScale.y) / ar;

    float2 noiseUV = aInput.texCoord;
    noiseUV *= noiseScale;

    float3 noise = NoiseTexture.Sample(WrappingSampler, noiseUV).rgb;
    noise.z = normalize(UnpackNormalZ(noise.x, noise.y));

    const float3 tangent = normalize(noise - normal * dot(noise, normal));
    const float3 bitangent = cross(normal, tangent);

    float3x3 TBN = float3x3(
		normalize(tangent),
		normalize(-bitangent),
		normalize(normal)
    );

    const float bias = 0.0000025f;
        
    const float rad = SSAORadius;

    float occlusion = 0.0f;

    for (int i = 0; i < SSAONumOfSamples; i++)
    {
        float3 samplePos = mul(SSAOSamples[i].xyz, TBN);
        
        samplePos = worldPos.xyz + samplePos * rad;

        const float4 offset = mul(worldToClipSpaceMatrix, float4(samplePos, 1.0f));

        const float3 sampledProjectedPos = offset.xyz / offset.w;
            
        const float2 sampleUV = 0.5f + float2(0.5f, -0.5f) * sampledProjectedPos.xy;

        const float sampleDepth = depthTex.Sample(SSAOSampler, sampleUV.xy).r;

        const float3 sampledWP = worldPositionTex.Sample(SSAOSampler, sampleUV.xy).xyz;

        const float pixelDist = length(worldPos.xyz - sampledWP);
        
        const float rangeCheck = smoothstep(0.0f, 1.0f, rad / pixelDist);
     
        occlusion += (sampleDepth < sampledProjectedPos.z - bias ? 1.0f : 0.0f) * rangeCheck;
    }
    occlusion = 1.0f - (occlusion / SSAONumOfSamples);
    
    output.aoTexture = float4(occlusion, occlusion, occlusion, 1);
    
    return output;
}