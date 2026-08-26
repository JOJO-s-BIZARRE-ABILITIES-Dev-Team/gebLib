-- Build source for gebLib's shaders/fxc/geblib_impact_ps20b.vcs.
-- Compile the returned HLSL as geblib_impact_ps2x.hlsl with ShaderCompile -ver 20b.
-- This file is source data only and is not included at runtime.

return [==[
sampler TexBase : register(s0);
sampler AttackerMask : register(s1);
sampler VictimMask : register(s2);

float4 C0 : register(c0); // scene mix, posterize, edge strength, encoded etch/mask state
float4 C1 : register(c1); // focus xy, screen-space direction xy
float4 C2 : register(c2); // paper rgb, radial distortion
float4 C3 : register(c3); // ink rgb, directional smear in pixels
float2 TexBaseSize : register(c4);

struct PS_INPUT
{
    float2 uv : TEXCOORD0;
};

float Luminance(float3 color)
{
    return dot(color, float3(0.299, 0.587, 0.114));
}

float4 main(PS_INPUT input) : COLOR
{
    float2 uv = input.uv;
    float2 fromFocus = uv - C1.xy;
    float aspect = TexBaseSize.y / max(TexBaseSize.x, 0.000001);
    float radialDistance = length(float2(fromFocus.x * aspect, fromFocus.y));
    float radialWindow = saturate(1.0 - radialDistance * 1.45);
    float2 warpedUv = saturate(uv + fromFocus * C2.w * radialWindow);

    float2 smearStep = float2(C1.z * TexBaseSize.x, C1.w * TexBaseSize.y) * C3.w;
    float3 scene = tex2D(TexBase, warpedUv).rgb * 0.34;
    scene += tex2D(TexBase, saturate(warpedUv - smearStep)).rgb * 0.24;
    scene += tex2D(TexBase, saturate(warpedUv - smearStep * 2.0)).rgb * 0.18;
    scene += tex2D(TexBase, saturate(warpedUv + smearStep)).rgb * 0.14;
    scene += tex2D(TexBase, saturate(warpedUv + smearStep * 2.0)).rgb * 0.10;

    float2 edgeStep = TexBaseSize * 1.6;
    float leftLum = Luminance(tex2D(TexBase, saturate(warpedUv - float2(edgeStep.x, 0.0))).rgb);
    float rightLum = Luminance(tex2D(TexBase, saturate(warpedUv + float2(edgeStep.x, 0.0))).rgb);
    float upLum = Luminance(tex2D(TexBase, saturate(warpedUv - float2(0.0, edgeStep.y))).rgb);
    float downLum = Luminance(tex2D(TexBase, saturate(warpedUv + float2(0.0, edgeStep.y))).rgb);
    float edge = saturate((abs(leftLum - rightLum) + abs(upLum - downLum)) * C0.z);

    float luminance = Luminance(scene);
    float levels = max(2.0, 9.0 - C0.y * 7.0);
    float posterized = floor(luminance * levels + 0.5) / levels;
    float3 inkedScene = lerp(C2.rgb, C3.rgb, 1.0 - posterized);
    float3 result = lerp(C2.rgb, lerp(scene, inkedScene, C0.y), C0.x);
    result = lerp(result, C3.rgb, edge);

    float maskEnabled = step(1.5, C0.w);
    float etch = frac(C0.w * 0.5) * 2.0;
    float2 pixel = uv / max(TexBaseSize, float2(0.000001, 0.000001));
    float diagonalA = 1.0 - smoothstep(0.34, 0.48, abs(frac((pixel.x + pixel.y * 0.62) / 7.0) - 0.5));
    float diagonalB = 1.0 - smoothstep(0.38, 0.49, abs(frac((pixel.x - pixel.y * 0.78) / 11.0) - 0.5));
    float brokenStroke = step(0.29, frac(pixel.x * 0.173 + pixel.y * 0.319));
    float grain = frac(pixel.x * 0.754877 + pixel.y * 0.569841);
    float darkTone = step(luminance + (grain - 0.5) * 0.22, 0.58);
    float hatch = saturate((diagonalA + diagonalB * 0.62) * brokenStroke * saturate(0.72 - luminance));
    float etchedInk = saturate(darkTone + hatch + edge * 1.3);
    float3 etchedResult = lerp(C2.rgb, C3.rgb, etchedInk);
    result = lerp(result, etchedResult, etch);

    float4 attacker = tex2D(AttackerMask, uv);
    float4 victim = tex2D(VictimMask, uv);
    result = lerp(result, attacker.rgb, saturate(attacker.a) * maskEnabled);
    result = lerp(result, victim.rgb, saturate(victim.a) * maskEnabled);

    return float4(saturate(result), 1.0);
}
]==]
