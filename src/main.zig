const std = @import("std");

const glfw = @import("glfw");
const metal = @import("metalzig");
const macos = @import("platform/macos.zig");

fn cBool(val: c_int) bool {
    return val != 0;
}

const WINDOW_WIDTH = 800;
const WINDOW_HEIGHT = 600;

pub fn main(_: std.process.Init) !void {
    const shader_source =
        \\#include <metal_stdlib>
        \\using namespace metal;
        \\
        \\struct VertexOut {
        \\    float4 position [[position]];
        \\    float4 color;
        \\};
        \\
        \\vertex VertexOut vertex_main(uint id [[vertex_id]]) {
        \\    float2 positions[3] = {
        \\        float2( 0.0,  0.5),
        \\        float2(-0.5, -0.5),
        \\        float2( 0.5, -0.5),
        \\    };
        \\
        \\    float4 colors[3] = {
        \\        float4(1, 0, 0, 1),
        \\        float4(0, 1, 0, 1),
        \\        float4(0, 0, 1, 1),
        \\    };
        \\
        \\    VertexOut out;
        \\    out.position = float4(positions[id], 0, 1);
        \\    out.color = colors[id];
        \\    return out;
        \\}
        \\
        \\fragment float4 fragment_main(VertexOut in [[stage_in]]) {
        \\    return in.color;
        \\}
    ;

    if (!cBool(glfw.glfwInit()))
        return error.GlfwInitFailed;
    defer glfw.glfwTerminate();

    glfw.glfwWindowHint(
        glfw.GLFW_CLIENT_API,
        glfw.GLFW_NO_API,
    );

    const window = glfw.glfwCreateWindow(
        WINDOW_WIDTH,
        WINDOW_HEIGHT,
        "zig gui + metal",
        null,
        null,
    ) orelse return error.WindowCreationFailed;
    defer glfw.glfwDestroyWindow(window);

    var device = try metal.Device.systemDefault();
    defer device.deinit();

    var command_queue = try device.newCommandQueue();
    defer command_queue.deinit();

    var layer = try device.newMetalLayer();
    defer layer.deinit();
    layer.setPixelFormat(.bgra8_unorm);
    layer.setFramebufferOnly(true);

    const view = try macos.attach(window, layer.nativeHandle());
    defer macos.detach(view);
    _ = &command_queue;

    const library = try device.newLibraryWithSource(shader_source);

    const vertex_fn = try library.newFunctionWithName("vertex_main");
    const fragment_fn = try library.newFunctionWithName("fragment_main");

    const pipeline_desc = metal.RenderPipelineDescriptor{
        .vertex_function = &vertex_fn,
        .fragment_function = &fragment_fn,
        .color_attachment = metal.ColorAttachmentDescriptor{
            .pixel_format = .bgra8_unorm,
        },
    };
    const pipeline = try device.newRenderPipelineState(pipeline_desc);

    while (!cBool(glfw.glfwWindowShouldClose(window))) {
        glfw.glfwPollEvents();

        var width: c_int = 0;
        var height: c_int = 0;
        glfw.glfwGetFramebufferSize(window, &width, &height);

        if (width <= 0 or height <= 0)
            continue;

        macos.resizeDrawable(
            view,
            @intCast(width),
            @intCast(height),
        );

        const drawable = layer.nextDrawable() catch continue;
        const pass = metal.RenderPassDescriptor{
            .color_texture = &(try drawable.texture()),
            .load_action = .clear,
            .store_action = .store,
            .clear_color = metal.ClearColor{
                .red = 0.1,
                .green = 0.1,
                .blue = 0.1,
                .alpha = 1.0,
            },
        };

        var command_buffer = try command_queue.newCommandBuffer();
        var encoder = try command_buffer.newRenderCommandEncoder(pass);
        encoder.setRenderPipelineState(&pipeline);
        try encoder.setViewport(.{
            .origin_x = 0,
            .origin_y = 0,
            .width = @floatFromInt(width),
            .height = @floatFromInt(height),
            .znear = 0,
            .zfar = 1,
        });

        try encoder.drawPrimitives(.triangle, 0, 3, 1);
        try encoder.endEncoding();

        try command_buffer.present(&drawable);
        try command_buffer.commit();
    }
}
