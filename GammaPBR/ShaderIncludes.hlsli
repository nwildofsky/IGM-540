#ifndef SHADER_INCLUDES
#define SHADER_INCLUDES

#define LIGHT_TYPE_DIRECTIONAL	0
#define LIGHT_TYPE_POINT		1
#define LIGHT_TYPE_SPOT			2
#define MAX_SPECULAR_EXPONENT	256.0f

// PBR CONSTANTS ===================

// Make sure to place these at the top of your shader(s) or shader include file
// - You don't necessarily have to keep all the comments; they're here for your reference

// The fresnel value for non-metals (dielectrics)
// Page 9: "F0 of nonmetals is now a constant 0.04"
// http://blog.selfshadow.com/publications/s2013-shading-course/karis/s2013_pbs_epic_notes_v2.pdf
static const float F0_NON_METAL = 0.04f;
// Minimum roughness for when spec distribution function denominator goes to zero
static const float MIN_ROUGHNESS = 0.0000001f; // 6 zeros after decimal
// Handy to have this as a constant
static const float PI = 3.14159265359f;

struct Light {
	int type;						// directional, point, spot
	float3 direction;
	float range;					// attenuation range
	float3 position;
	float intensity;
	float3 color;
	float spotFalloff;				// spot light cone size
	float3 padding;					// purposeful padding to hit the 16-byte boundary
};

// Struct representing a single vertex worth of data
// - This should match the vertex definition in our C++ code
// - By "match", I mean the size, order and number of members
// - The name of the struct itself is unimportant, but should be descriptive
// - Each variable must have a semantic, which defines its usage
struct VertexShaderInput
{
	// Data type
	//  |
	//  |   Name          Semantic
	//  |    |                |
	//  v    v                v
	float3 localPosition	: POSITION;     // XYZ position
	float3 normal			: NORMAL;
	float3 tangent			: TANGENT;
	float2 uv				: TEXCOORD;
};

// Struct representing the data we're sending down the pipeline
// - Should match our pixel shader's input (hence the name: Vertex to Pixel)
// - At a minimum, we need a piece of data defined tagged as SV_POSITION
// - The name of the struct itself is unimportant, but should be descriptive
// - Each variable must have a semantic, which defines its usage
struct VertexToPixel
{
	// Data type
	//  |
	//  |   Name          Semantic
	//  |    |                |
	//  v    v                v
	float4 screenPosition	: SV_POSITION;	// XYZW position (System Value Position)
	float2 uv				: TEXCOORD;
	float3 normal			: NORMAL;
	float3 tangent			: TANGENT;
	float3 worldPosition	: POSITION;
};

struct VertexToPixelSky
{
	float4 position		: SV_POSITION;
	float3 sampleDir	: DIRECTION;
};

// https://gamedev.stackexchange.com/questions/138511/sampled-texture-renders-dark
float3 LightenToGamma(float3 color) { return pow(color, 1/2.2f); }
float3 DarkenToGamma(float3 color) { return pow(color, 2.2f); }

float3 Diffuse(float3 dirToLight, float3 normal) { return saturate(dot(normal, dirToLight)); }
float3 Specular(Light light, float3 normal, float3 view, float exponent)
{
	if (exponent > 0.05f)
	{
		float3 r = reflect(normalize(light.direction), normal);
		return pow(saturate(dot(r, view)), exponent);
	}

	return float3(0, 0, 0);
}
float Attenuate(Light light, float3 worldPos)
{
	float dist = distance(light.position, worldPos);
	float att = saturate(1.0f - (dist * dist / (light.range * light.range)));
	return att * att;
}

// PBR FUNCTIONS ====================================================================================
// 
// Calculates diffuse amount based on energy conservation
//
// diffuse - Diffuse amount
// specular - Specular color (including light color)
// metalness - surface metalness amount
//
// Metals should have an albedo of (0,0,0)...mostly
// See slide 65: http://blog.selfshadow.com/publications/s2014-shading-course/hoffman/s2014_pbs_physics_math_slides.pdf
float3 DiffuseEnergyConserve(float3 diffuse, float3 specular, float metalness)
{
	return diffuse * ((1 - saturate(specular)) * (1 - metalness));
}

// GGX (Trowbridge-Reitz)
//
// a - Roughness
// h - Half vector
// n - Normal
// 
// D(h, n) = a^2 / pi * ((n dot h)^2 * (a^2 - 1) + 1)^2
float SpecDistribution(float3 n, float3 h, float roughness)
{
	// Pre-calculations
	float NdotH = saturate(dot(n, h));
	float NdotH2 = NdotH * NdotH;
	float a = roughness * roughness;
	float a2 = max(a * a, MIN_ROUGHNESS); // Applied after remap!

	// ((n dot h)^2 * (a^2 - 1) + 1)
	float denomToSquare = NdotH2 * (a2 - 1) + 1;
	// Can go to zero if roughness is 0 and NdotH is 1; MIN_ROUGHNESS helps here

	// Final value
	return a2 / (PI * denomToSquare * denomToSquare);
}

// Fresnel term - Schlick approx.
// 
// v - View vector
// h - Half vector
// f0 - Value when l = n (full specular color)
//
// F(v,h,f0) = f0 + (1-f0)(1 - (v dot h))^5
float3 Fresnel(float3 v, float3 h, float3 f0)
{
	// Pre-calculations
	float VdotH = saturate(dot(v, h));

	// Final value
	return f0 + (1 - f0) * pow(1 - VdotH, 5);
}

// Geometric Shadowing - Schlick-GGX (based on Schlick-Beckmann)
// - k is remapped to a / 2, roughness remapped to (r+1)/2
//
// n - Normal
// v - View vector
//
// G(l,v)
float GeometricShadowing(float3 n, float3 v, float roughness)
{
	// End result of remapping:
	//float k = pow(roughness + 1, 2) / 8.0f;
	float a = roughness * roughness;
	float k = a / 2.0f;
	float NdotV = saturate(dot(n, v));

	// Final value
	return NdotV / (NdotV * (1 - k) + k);
}

// Microfacet BRDF (Specular)
//
// f(l,v) = D(h)F(v,h)G(l,v,h) / 4(n dot l)(n dot v)
// - part of the denominator are canceled out by numerator (see below)
//
// D() - Spec Dist - Trowbridge-Reitz (GGX)
// F() - Fresnel - Schlick approx
// G() - Geometric Shadowing - Schlick-GGX
float3 MicrofacetBRDF(float3 n, float3 l, float3 v, float roughness, float3 specColor)
{
	// Other vectors
	float3 h = normalize(v + l);

	// Grab various functions
	float D = SpecDistribution(n, h, roughness);
	float3 F = Fresnel(v, h, specColor);
	float G = GeometricShadowing(n, v, roughness) * GeometricShadowing(n, l, roughness);

	// Final formula
	// Denominator dot products partially canceled by G()!
	// See page 16: http://blog.selfshadow.com/publications/s2012-shading-course/hoffman/s2012_pbs_physics_math_notes.pdf
	return (D * F * G) / (4 * max(dot(n, v), dot(n, l)));
}
// =====================================================================================================


float3 ColorFromLight(Light light, float3 normal, float3 worldPos, float3 view, float3 surfaceColor, float3 specularColor, float roughness, float metallic)
{
	switch(light.type)
	{
		case LIGHT_TYPE_DIRECTIONAL:
		{
			float3 dirToLight = normalize(-light.direction);
			
			float3 diffuse = Diffuse(dirToLight, normal);
			float3 specular = MicrofacetBRDF(normal, dirToLight, view, roughness, specularColor);
			// Caluclate diffuse with energy conservation
			// (Reflected light doesn't get diffused)
			diffuse = DiffuseEnergyConserve(diffuse, specular, metallic);
			float3 total = (diffuse * surfaceColor + specular) * light.intensity * light.color;

			return total;
		}

		case LIGHT_TYPE_POINT:
		{
			float3 dirToLight = normalize(light.position - worldPos);

			float3 diffuse = Diffuse(dirToLight, normal);
			float3 specular = MicrofacetBRDF(normal, dirToLight, view, roughness, specularColor);
			// Caluclate diffuse with energy conservation
			// (Reflected light doesn't get diffused)
			diffuse = DiffuseEnergyConserve(diffuse, specular, metallic);
			float3 total = (diffuse * surfaceColor + specular) * light.intensity * light.color * Attenuate(light, worldPos);

			return total;
		}
			
		// TODO: Spotlight
		default:
			return float3(0.f, 0.f, 0.f);
	}
}

#endif