#pragma once

#include <DirectXMath.h>
#include <memory>
#include <unordered_map>
#include "SimpleShader.h"

class Material
{
public:
	Material(
		const char* name,
		std::shared_ptr<SimpleVertexShader> vxShader,
		std::shared_ptr<SimplePixelShader> pxShader,
		DirectX::XMFLOAT4 colorTint = DirectX::XMFLOAT4(1, 1, 1, 1),
		float roughness = 0.0f,
		float metallic = 0.0f,
		float texScale = 1.0f,
		DirectX::XMFLOAT2 texOffset = DirectX::XMFLOAT2(0, 0)
	);

	std::shared_ptr<SimpleVertexShader> GetVertexShader() { return vertexShader; }
	std::shared_ptr<SimplePixelShader> GetPixelShader() { return pixelShader; }
	const char* GetName() { return name; }
	DirectX::XMFLOAT4 GetColorTint() { return colorTint; }
	float GetRoughness() { return roughness; }
	float GetMetallic() { return metallic; }
	float GetTextureScale() { return textureScale; }
	DirectX::XMFLOAT2 GetTextureOffset() { return textureOffset; }

	void SetVertexShader(std::shared_ptr<SimpleVertexShader> vxShader) { vertexShader = vxShader; }
	void SetPixelShader(std::shared_ptr<SimplePixelShader> pxShader) { pixelShader = pxShader; }
	void SetName(const char* val) { name = val; }
	void SetColorTint(DirectX::XMFLOAT4 color) { colorTint = color; }
	void SetRoughness(float val) { roughness = val; }
	void SetMetallic(float val) { metallic = val; }
	void SetTextureScale(float val) { textureScale = val; }
	void SetTextureOffset(DirectX::XMFLOAT2 val) { textureOffset = val; }

	void SetAlbedo(Microsoft::WRL::ComPtr<ID3D11ShaderResourceView> srv) { textureSrvs.insert_or_assign("Albedo", srv); }
	void SetNormal(Microsoft::WRL::ComPtr<ID3D11ShaderResourceView> srv) { textureSrvs.insert_or_assign("NormalMap", srv); }
	void SetRoughness(Microsoft::WRL::ComPtr<ID3D11ShaderResourceView> srv);
	void SetMetallic(Microsoft::WRL::ComPtr<ID3D11ShaderResourceView> srv);
	void SetAllPbrTextures(Microsoft::WRL::ComPtr<ID3D11ShaderResourceView> textures[4]);
	void AddSampler(std::string shaderName, Microsoft::WRL::ComPtr<ID3D11SamplerState> sampler) { textureSamplers.insert({shaderName, sampler}); }

	void Prepare();

private:
	std::shared_ptr<SimpleVertexShader> vertexShader;
	std::shared_ptr<SimplePixelShader> pixelShader;

	const char* name;
	DirectX::XMFLOAT4 colorTint;
	float roughness;
	float metallic;
	float textureScale;
	DirectX::XMFLOAT2 textureOffset;

	std::unordered_map<std::string, Microsoft::WRL::ComPtr<ID3D11ShaderResourceView>> textureSrvs;
	std::unordered_map<std::string, Microsoft::WRL::ComPtr<ID3D11SamplerState>> textureSamplers;
};

