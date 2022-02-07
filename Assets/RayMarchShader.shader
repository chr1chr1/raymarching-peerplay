Shader "PeerPlay/NewImageEffectShader"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        // No culling or depth
        Cull Off 
        ZWrite Off 
        ZTest Always

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0

            #include "UnityCG.cginc"
            #include "DistanceFunctions.cginc"

            sampler2D _MainTex;
            uniform sampler2D _CameraDepthTexture;
            uniform float4x4 _CamFrustum, _CamToWorld;
            uniform float _maxDistance, _box1round, _boxSphereSmooth, _sphereIntersectSmooth, _lightIntensity, _shadowIntensity, _shadowPenumbra;
            uniform float3 _lightDir, _modInterval, _lightCol;
            uniform float4 _sphere1, _sphere2, _box1, _mainColor;
            uniform float2 _shadowDist;
            uniform int _maxIterations;
            
            #define EPSILON 1e-3 // 0.001

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float3 ray : TEXCOORD1; // ray direction
            };

            v2f vert (appdata v)
            {
                v2f o;
                half index = v.vertex.z;
                v.vertex.z = 0;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;

                o.ray = _CamFrustum[(int)index].xyz;
                o.ray /= abs(o.ray.z);
                o.ray = mul(_CamToWorld, o.ray);
                
                return o;
            }

            float BoxSphere(float3 p)
            {
                float Sphere1 = sdSphere(p - _sphere1.xyz, _sphere1.w);
                float Box1 = sdRoundBox(p - _box1.xyz, _box1.www, _box1round);
                float combine1 = opSS(Sphere1, Box1, _boxSphereSmooth);
                float Sphere2 = sdSphere(p - _sphere2.xyz, _sphere2.w);
                float combine2 = opIS(Sphere2, combine1, _sphereIntersectSmooth);
                return combine2;
            }
            
            float distanceField(float3 p)
            {
                // float modX = pMod1(p.x, _modInterval.x);
                // float modY = pMod1(p.y, _modInterval.y);
                // float modZ = pMod1(p.z, _modInterval.z);
                float boxSphere1 = BoxSphere(p);
                float ground = sdPlane(p, float4(0,1,0,0));
                return opU(ground, boxSphere1);
            }

            // returns depth along viewing ray, aka distance to scene
            float RayMarch(float3 ro, float3 rd)
            {
                float distOrigin = 0;
                for (int i = 0; i < _maxIterations; i++) {
                    
                    float distSurface = distanceField(ro + distOrigin * rd);
                    distOrigin += distSurface;
                    
                    if (distOrigin < EPSILON || distOrigin > _maxDistance)
                        break;
                }
                return distOrigin;
            }

            // discrete derivative of the SDF function; fastest change  is normal to surface 
            float3 EstimateNormal(float3 p)
            {
                return normalize(float3(
                    distanceField(float3(p.x + EPSILON, p.y, p.z)) - distanceField(float3(p.x - EPSILON, p.y, p.z)),
                    distanceField(float3(p.x, p.y + EPSILON, p.z)) - distanceField(float3(p.x, p.y - EPSILON, p.z)),
                    distanceField(float3(p.x, p.y, p.z  + EPSILON)) - distanceField(float3(p.x, p.y, p.z - EPSILON))));
            }

            float hardShadow(float3 ro, float3 rd, float minDist, float maxDist)
            {
                for (float dist = minDist; dist < maxDist; dist++)
                {
                    float h = distanceField(ro+rd*dist);
                    if (h < EPSILON)
                    {
                        return 0.0;
                    }
                    dist += h;
                }
                return 1.0;
            }

            float softShadow(float3 ro, float3 rd, float minDist, float maxDist, float k)
            {
                float result = 1.0;
                for (float dist = minDist; dist < maxDist; dist++)
                {
                    float h = distanceField(ro+rd*dist);
                    if (h < EPSILON)
                    {
                        return 0.0;
                    }
                    result = min(result, k*h/dist);
                    dist += h;
                }
                return result;
            }

            uniform float _aoStepSize, _aoIntensity;
            uniform int _aoIterations;

            float AmbientOcclusion(float3 p, float3 n)
            {
                float step = _aoStepSize;
                float ao = 0.0;
                float dist;
                for (int i = 1; i <= _aoIterations; i++)
                {
                    dist = step * i;
                    ao += max(0.0, (dist - distanceField(p + n * dist)) / dist);
                }
                return 1.0 - ao * _aoIntensity;
            }

            float3 Shading(float3 p, float3 n)
            {
                float3 result;
                // Diffuse Color
                float3 color = _mainColor.rgb;
                // Directional Light
                float3 light = (_lightCol * dot(-_lightDir,n) * 0.5 + 0.5) * _lightIntensity;
                // Shadows
                float shadow = softShadow(p, -_lightDir, _shadowDist.x, _shadowDist.y, _shadowPenumbra) * 0.5 + 0.5;
                shadow = max(0.0, pow(shadow, _shadowIntensity));
                // Ambient Occlusion
                float ao = AmbientOcclusion(p, n);
                
                result = color * light * shadow * ao;
                return result;
            }

            float4 frag (v2f i) : SV_Target
            {
                float depth = LinearEyeDepth(tex2D(_CameraDepthTexture, i.uv).r);
                depth *= length(i.ray);
                float3 col = tex2D(_MainTex, i.uv);
                float3 rayDirection = normalize(i.ray.xyz);
                float3 rayOrigin = _WorldSpaceCameraPos;
                float dist = RayMarch(rayOrigin, rayDirection);
                
                if (dist >= _maxDistance || dist >= depth)
                {
                    //environment
                    float4 result = float4(rayDirection, 0);
                    return float4(col*(1.0-result.w) + result.xyz * result.w, 1);
                    
                }
                else
                {
                    //shading
                    float3 p = rayOrigin + rayDirection * dist;
                    float3 n = EstimateNormal(p);
                    float s = Shading(p, n);
                    float4 result = float4(_mainColor.rgb * s, 1);
                    return float4(col*(1.0-result.w) + result.xyz * result.w, 1);
                }
                

            }
            ENDCG
        }
    }
}
