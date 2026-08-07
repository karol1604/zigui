#include <metal_stdlib>
using namespace metal;

struct VertexOut {
	float4 position [[position]];
	float4 color;
};

struct Vertex {
  float2 position;
  float4 color;
};

struct FrameUniforms {
  float2 viewport_size;
};

vertex VertexOut vertex_main(
  device const Vertex* vertices [[buffer(0)]],
  constant FrameUniforms& frame [[buffer(1)]],
  uint vertex_id [[vertex_id]]
) {
  Vertex v = vertices[vertex_id];

  float2 normalized = v.position / frame.viewport_size;

  VertexOut out;
  out.position = float4(
	  normalized.x * 2.0 - 1.0,
	  1.0 - normalized.y * 2.0,
	  0.0,
	  1.0
  );
  out.color = v.color;
  return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]]) {
	return in.color;
}
