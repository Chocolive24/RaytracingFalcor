/***************************************************************************
 # Copyright (c) 2015-24, NVIDIA CORPORATION. All rights reserved.
 #
 # Redistribution and use in source and binary forms, with or without
 # modification, are permitted provided that the following conditions
 # are met:
 #  * Redistributions of source code must retain the above copyright
 #    notice, this list of conditions and the following disclaimer.
 #  * Redistributions in binary form must reproduce the above copyright
 #    notice, this list of conditions and the following disclaimer in the
 #    documentation and/or other materials provided with the distribution.
 #  * Neither the name of NVIDIA CORPORATION nor the names of its
 #    contributors may be used to endorse or promote products derived
 #    from this software without specific prior written permission.
 #
 # THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS "AS IS" AND ANY
 # EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 # IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 # PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 # CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 # EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 # PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 # PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 # OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 # (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 # OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 **************************************************************************/
import Scene.Raytracing;
import Utils.Sampling.TinyUniformSampleGenerator;
import Rendering.Materials.Fresnel;
import Rendering.Materials.TexLODHelpers;
import Rendering.Lights.LightHelpers;

RWTexture2D<float4> gOutput;

cbuffer PerFrameCB
{
    float4x4 invView;
    float2 viewportDims;
    float tanHalfFovY;
    uint sampleIndex;
    bool useDOF;
    float3 backgroundColor;
    float3 absorptionCoeff;
    uint maxRayBounce;
    float time;
};

struct PrimaryRayData
{
    float4 color = float4(0, 0, 0, 0);
    uint depth = 0;
    float hitT = -1.f;
    float absorptionDistance = 0.f;
};

/**
 * Returns the shading normal flipped for backfacing hits on double-sided materials.
 * This reproduces the legacy behavior before the conventions were updated.
 */
float3 getFlippedShadingNormal(const ShadingData sd)
{
    return !sd.frontFacing && sd.mtl.isDoubleSided() ? -sd.frame.N : sd.frame.N;
}

/**
 * Helper for computing relatice index of refraction (eta) at a hit.
 * This is computed based on the IoRs of the media outside and inside the material.
 */
float computeEta(const ShadingData sd)
{
    float insideIoR = gScene.materials.evalIoR(sd.materialID);
    float eta = sd.frontFacing ? (sd.IoR / insideIoR) : (insideIoR / sd.IoR);
    return eta;
}

float sdSphere(float3 p, float3 sphereCenter, float sphereRadius)
{
    return length(p - sphereCenter) - sphereRadius;
}

float sdSphere(float3 p, float sphereRadius)
{
    return length(p) - sphereRadius;
}

float sdBox(float3 p, float3 b)
{
    float3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

// Define mix function in Slang (similar to GLSL mix or HLSL lerp)
float mix(float x, float y, float a) {
    return x * (1.0 - a) + y * a;
}

float opSmoothUnion(float d1, float d2, float k)
{
    float h = clamp(0.5 + 0.5 * (d2 - d1) / k, 0.0, 1.0);
    return mix(d2, d1, h) - k * h * (1.0 - h);
}

float map(float3 p)
{
    float3 c = float3(sin(time * 3) * 3, 10, 0);
    float sphere = sdSphere(p - c, 1);

    c = float3(0, 10, 0);
    float box = sdBox(p - c, float3(0.75, 0.75, 0.75)); 

    return opSmoothUnion(sphere, box, 2); // Distance to a sphere of radius 1.
}

float mapDebug(float3 p)
{
    float3 c = float3(sin(time * 3) * 3, 15, 0);
    float sphere = sdSphere(p - c, 1);

    c = float3(0, 15, 0);
    float box = sdBox(p - c, float3(0.75, 0.75, 0.75));

    return opSmoothUnion(sphere, box, 2); // Distance to a sphere of radius 1.
}

float BeerLambert(float absorptionCoefficient, float distanceTraveled)
{
    return exp(-absorptionCoefficient * distanceTraveled);
}

// Miss shader
[shader("miss")]
void miss(inout PrimaryRayData hitData)
{
    float3 rayDir = WorldRayDirection();
    float3 rayOrigin = WorldRayOrigin();

    float3 finalColor = float3(0, 0, 0);

    float t = 0.f; // total distance travelled

    // Raymarching.
    for (int i = 0; i < 80; i++)
    {
        float3 p = rayOrigin + rayDir * t; // Position along the ray.

        float d = mapDebug(p); // Current distance to the scene.

        t += d; // March the ray.

        // Early stop if close enough or if too far.
        if (d < 0.001f)
        {
            break;
        }

        if (t > 100.f) 
        {
            break;
        }
    }

    if (t < 100.f)
    {
        t *= 0.2;
        finalColor = float3(t, t, t);
        finalColor *= float3(0.1, 0.3, 1);
    }
    else
    {
        finalColor = gScene.envMap.eval(rayDir);
    }


    hitData.color = float4(finalColor, 1);

    return;

    // Use the ray direction to sample the environment map
    float3 envColor = gScene.envMap.eval(WorldRayDirection());
    hitData.color = float4(envColor, 1.f);
    hitData.hitT = -1.f;
    hitData.absorptionDistance = 0;
}

[shader("closesthit")]
void closestHit(inout PrimaryRayData hitData, BuiltInTriangleIntersectionAttributes attribs)
{
    // Get the hit-point data.
    float3 rayDir = WorldRayDirection();
    float currentRayDistance = RayTCurrent();
    uint triangleIndex = PrimitiveIndex();

    if (hitData.depth >= maxRayBounce)
    {
        hitData.color = float4(1.f, 1.f, 0.f, 1);
        hitData.hitT = 0;
        hitData.absorptionDistance = 0;
        return;
    }

    // Retrieve hit information
    const GeometryInstanceID instanceID = getGeometryInstanceID();
    VertexData v = getVertexData(instanceID, triangleIndex, attribs);
    float3 world_pos = v.posW;
    float3 normal = v.normalW;

    uint materialID = gScene.getMaterialID(instanceID);
    ShadingData sd = gScene.materials.prepareShadingData(v, materialID, -rayDir);
    float3 orientedFaceNormal = getFlippedShadingNormal(sd);

    // Create material instance and query its properties.
    let lod = ExplicitLodTextureSampler(0.f);
    let mi = gScene.materials.getMaterialInstance(sd, lod);
    let bsdfProperties = mi.getProperties(sd);

    if (gScene.materials.evalIoR(sd.materialID) < 1.f)
    {
        hitData.color = float4(backgroundColor, 1.f);
        // hitData.color = float4(bsdfProperties.diffuseReflectionAlbedo, 1.f);
        hitData.hitT = RayTCurrent();
        hitData.absorptionDistance = 0;
        return;
    }

    // 1. Compute Fresnel reflectance
    float etaI = sd.IoR; // Incident IoR (Air by default).
    float etaT = gScene.materials.evalIoR(sd.materialID); // Tranmission IoR (the one from the medium).
    float eta = sd.frontFacing ? etaI / etaT : etaT / etaI;

    float F0 = pow((etaI - etaT) / (etaI + etaT), 2.0);
    float F90 = 1.f;
    float cosTheta = max(0.00001f, dot(getFlippedShadingNormal(sd), -rayDir));
    float reflectionRatio = evalFresnelSchlick(F0, F90, cosTheta);
    float refractionRatio = 1.f - reflectionRatio;

    // 2. Prepare color storage
    float4 reflectedColor = float4(0, 0, 0, 0);
    float4 refractedColor = float4(0, 0, 0, 0);
    float absorptionTotalDistance = 0.f;

    // 3. Check for total internal reflection
    bool tir = false;
    float3 refractDir = rayDir; // Default if eta == 1.0

    if (eta != 1.0)
    {
        if (!refractWithTIR(rayDir, orientedFaceNormal, eta, refractDir))
            tir = true;
    }

    // 4. Trace reflection ray if needed
    if (reflectionRatio > 0.001f || tir)
    {
        // Handle total internal reflection
        float3 reflectDir = reflect(rayDir, orientedFaceNormal); // Compute the reflection direction

        // Define reflection ray
        RayDesc reflectRay;
        reflectRay.Origin = sd.computeRayOrigin(true); // Offset to avoid self-intersection
        reflectRay.Direction = reflectDir;
        reflectRay.TMin = 0.001f;
        reflectRay.TMax = 100000.f;

        // Trace reflection ray
        PrimaryRayData reflectedRayData = {};
        reflectedRayData.depth = hitData.depth + 1;
        reflectedRayData.hitT = 0;
        reflectedRayData.absorptionDistance = hitData.absorptionDistance;
        TraceRay(gScene.rtAccel, RAY_FLAG_NONE, 0xFF, 0, rayTypeCount, 0, reflectRay, reflectedRayData);

        reflectedColor = reflectedRayData.color;
        absorptionTotalDistance = reflectedRayData.absorptionDistance;

        // If we are in a TiR case, the next reflection ray will be inside the medium. 
        // That's why we add its distance to the total absorption distance.
        if (tir)
        {
            absorptionTotalDistance += reflectedRayData.hitT;
        }
    }

    // 5. Trace refraction ray if not TIR
    if (!tir && refractionRatio > 0.001f)
    {
        // Trace a refracted ray to get the color after the transmission.
        RayDesc refractRay;
        refractRay.Origin = sd.computeRayOrigin(false);
        refractRay.Direction = refractDir;
        refractRay.TMin = 0.001f;
        refractRay.TMax = 100000.f;

        PrimaryRayData refractedRayData = {};
        refractedRayData.depth = hitData.depth + 1;
        refractedRayData.hitT = 0.f;
        refractedRayData.absorptionDistance = hitData.absorptionDistance;
        TraceRay(gScene.rtAccel, RAY_FLAG_NONE, 0xFF, 0, rayTypeCount, 0, refractRay, refractedRayData);

        refractedColor = refractedRayData.color;
        absorptionTotalDistance = refractedRayData.absorptionDistance;
    }

    // If the current ray is inside the medium, add its distance to the total absorb distance.
    if (!sd.frontFacing)
    {
        absorptionTotalDistance += currentRayDistance;
    }

    hitData.absorptionDistance = absorptionTotalDistance;

    // Apply Beer's Law attenuation
    float3 absorb = exp(-absorptionCoeff * absorptionTotalDistance);
    refractedColor *= float4(absorb, 1.f);

    // 6. Mix results
    float4 finalColor = tir ? reflectedColor :
            reflectionRatio * reflectedColor + refractionRatio * refractedColor;

    hitData.color = finalColor;
}

[shader("closesthit")]
void RaymarchingClosestHit(inout PrimaryRayData hitData, BuiltInTriangleIntersectionAttributes attribs)
{
    // float tColor = hitData.hitT * 0.2f;
    // float3 finalColor = float3(tColor, tColor, tColor);
    // finalColor *= float3(0.1, 0.3, 1);

    // hitData.color = float4(finalColor, 1.f);

    hitData.color = float4(0.1, 0.3, 1, 1);
}

[shader("intersection")]
void RaymarchingIntersection()
{
    float3 rayDir = WorldRayDirection();
    float3 rayOrigin = WorldRayOrigin();

    float3 finalColor = float3(0, 0, 0);

    float t = 0.f; // total distance travelled

    // Raymarching.
    for (int i = 0; i < 80; i++)
    {
        float3 p = rayOrigin + rayDir * t; // Position along the ray.

        float d = map(p); // Current distance to the scene.

        t += d; // March the ray.

        // Early stop if close enough or if too far.
        if (d < 0.001f)
        {
            break;
        }

        if (t > 100.f)
        {
            break;
        }
    }

    if (t < 100.f)
    {
        //t *= 0.2;
        BuiltInTriangleIntersectionAttributes attr;
        ReportHit(t, /*hitKind*/ 0, attr);
        // finalColor = float3(t, t, t);
        // finalColor *= float3(0.1, 0.3, 1);
    }
    // else
    // {
    //     finalColor = gScene.envMap.eval(rayDir);
    // }

    // hitData.color = float4(finalColor, 1);

    // return;
}

// Ray generation (just a simple ray going through the scene)
[shader("raygeneration")]
void rayGen()
{
    uint3 launchIndex = DispatchRaysIndex();

    RayDesc ray;
    ray = gScene.camera.computeRayPinhole(launchIndex.xy, vector<uint, 2>(viewportDims)).toRayDesc();

    PrimaryRayData hitData;
    hitData.color = float4(0.f, 0.f, 0.f, 0.f);
    hitData.depth = 0;
    TraceRay(gScene.rtAccel, RAY_FLAG_NONE /*rayFlags*/, 0xFF, /*Test all Geometry*/ 0 /* ray index*/, rayTypeCount, 0, ray, hitData);
    gOutput[launchIndex.xy] = hitData.color;
}

