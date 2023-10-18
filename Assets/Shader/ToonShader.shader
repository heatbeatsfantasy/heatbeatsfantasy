Shader "Unlit/ToonShader"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        //外轮廓参数
        _OutlineWidth("Outline_Width",Range(0.01,1)) = 0.01
        _OutlineColor("Outline_Color",Color) = (0.5,0.5,0.5,1)
        //色阶参数
        _RampStart("交界起始RampStart",Range(0.1,1)) = 0.3
        _RampSize("交界大小RampSize",Range(0,1)) = 0.1
        [IntRange]_RampStep("交界段数RampStep",Range(1,10)) = 1
        _RampSmooth("交界柔和度RampSmooth",Range(0.01,1)) = 0.1
        _DarkColor("暗面DarkColor",Color) = (0.4,0.4,0.4,1)
        _LightColor("亮面LightColor",Color) = (0.8,0.8,0.8,1)
        //高光参数
        _SpecPow("SpecPow光泽度",Range(0,1)) = 0.1
        _SpecularColor("SpecularColor高光",Color) = (1.0,1.0,1.0,1)
        _SpecIntensity("SpecIntensity高光强度",Range(0,1)) = 0
        _SpecSmooth("SpecSmooth高光柔和度",Range(0,0.5)) = 0.1
        //边缘光参数
        _RimColor("RimColor边缘光",Color) = (1.0,1.0,1.0,1)
        _RimThreshold("RimThreshold边缘光阈值",Range(0,1)) = 0.45
        _RimSmooth("RimSmooth边缘光柔和度",Range(0,0.5)) = 0.1
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 500

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            // make fog work
            #pragma multi_compile_fog

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal:NORMAL;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                UNITY_FOG_COORDS(1)
                float4 vertex : SV_POSITION;
                //加入光照所需要的法线和世界坐标
                float3 worldNormal:TEXCOORD1;
                float3 worldPos:TEXCOORD2;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
            float _RampStart;
            float _RampSize;
            float _RampStep;
            float _RampSmooth;
            float3 _DarkColor;
            float3 _LightColor;
            float _SpecPow;
            float3 _SpecularColor;
            float _SpecIntensity;
            float _SpecSmooth;
            float3 _RimColor;
            float _RimThreshold;
            float _RimSmooth;
            //加入一个Linearstep方法让明暗分明
            float Linearstep(float min , float max,float t)
            {
                return saturate((t-min)/(max-min));
            }

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.worldPos = mul(unity_ObjectToWorld,v.vertex).xyz;
                o.worldNormal = normalize(UnityObjectToWorldNormal(v.normal));
                UNITY_TRANSFER_FOG(o,o.vertex);
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                // sample the texture
                fixed4 col = tex2D(_MainTex, i.uv);
                float3 normal = normalize(i.worldNormal);
                //frag方法，首先通过世界坐标拿到光照方向，用法线点乘入射光，获取入射光与模型表面的夹角，矫正角度范围返回的是0~1而不是-1~1。
                float3 worldLightDir = UnityWorldSpaceLightDir(i.worldPos);
                float NoL = dot(i.worldNormal,worldLightDir);
                float halfLambert = NoL*0.5+0.5;


                //使用blinnphone计算高光
                float3 viewDir = normalize(_WorldSpaceCameraPos.xyz - i.worldPos.xyz);
                float3 halfDir = normalize(viewDir+worldLightDir);
                float NoH = dot(normal,halfDir);
                float blinnPhone = pow(max(0,NoH),_SpecPow*128.0);
                float3 specularColor = smoothstep(0.7-_SpecSmooth/2,0.7+_SpecSmooth/2,blinnPhone)*_SpecularColor*_SpecIntensity;
                //return blinnPhone;

                //边缘光(明晰：当法向量近乎垂直于视向量，这时的法向量所在的片元为边缘)
                float NoV = dot(i.worldNormal,viewDir);
                float rim = (1-max(0,NoV))*NoL;//这里计算的边缘光需要先反转再漫反射
                float3 rimColor = smoothstep(_RimThreshold-_RimSmooth/2,_RimThreshold+_RimSmooth/2,rim)*_RimColor;

                //通过亮度来计算线性ramp（斜坡）
                float ramp = Linearstep(_RampStart,_RampStart+_RampSize,halfLambert);
                float step = ramp * _RampStep;//使每个色阶大小为1，方便计算
                float gridStep = floor(step);//得到当前所处色阶
                float smoothStep = smoothstep(gridStep,gridStep+_RampSmooth,step)+gridStep;
                ramp = smoothStep/_RampStep;//回到原来空间
                float3 rampColor = lerp(_DarkColor,_LightColor,ramp);
                rampColor *= col;
                float3 finalColor = saturate(rampColor+specularColor+rimColor);//混合色阶，高光，边缘光
                return float4(finalColor,1);
                // apply fog
                UNITY_APPLY_FOG(i.fogCoord, col);
                //return col * halfLambert;
            }
            ENDCG
        }

        //外轮廓线（outline）
        Pass
        {
            Cull Front
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            // make fog work
            #pragma multi_compile_fog

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal:NORMAL;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                UNITY_FOG_COORDS(1)
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
            float _OutlineWidth;
            float4 _OutlineColor;

            v2f vert (appdata v)
            {
                v2f o;
                float4 newVertex = float4(v.vertex.xyz+normalize(v.normal)*_OutlineWidth*0.05,1);
                o.vertex = UnityObjectToClipPos(newVertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                UNITY_TRANSFER_FOG(o,o.vertex);
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
               return _OutlineColor;
            }
            ENDCG
        }
    }
}
