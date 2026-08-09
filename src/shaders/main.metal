#include <metal_stdlib>
using namespace metal;

struct VertexOut {
  float4 position [[position]];
  float2 shape_pos;
  float4 color;
  float2 uv;
};

struct Vertex {
  float2 position;
  float2 shape_pos;
  float4 color;
  float2 uv;
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
  out.shape_pos = v.shape_pos;
  out.uv = v.uv;
  return out;
}

constexpr sampler tex_sampler(
    min_filter::linear,
    mag_filter::linear
);

fragment float4 fragment_main(
  VertexOut in [[stage_in]],
  texture2d<float> tex [[texture(0)]]
) {
  float distance = length(in.shape_pos);
  float aa = max(fwidth(distance), 0.00001);

  float coverage = 1.0 - smoothstep(
      1.0 - aa,
      1.0 + aa,
      distance
  );

  if (coverage <= 0.0) {
      discard_fragment();
  }

  float4 sampled = tex.sample(tex_sampler, in.uv);


    return float4(
        sampled.rgb * in.color.rgb,
        sampled.a * in.color.a * coverage
    );

  return float4(
      in.color.rgb,
      in.color.a * coverage
  );


}
