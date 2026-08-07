const std = @import("std");
const draw = @import("draw.zig");
const metal = @import("metalzig");

const Rect = draw.Rect;
const RectCommand = draw.RectCommand;
const EllipseCommand = draw.EllipseCommand;
const LineCommand = draw.LineCommand;
const TextCommand = draw.TextCommand;
const DrawList = draw.DrawList;

pub const Vertex = extern struct {
    position: [2]f32,
    _padding: [2]f32 = .{ 0, 0 }, //  we need to match metal's alignment
    color: [4]f32,
};

pub const FrameUniforms = extern struct { viewport_size: [2]f32 };

pub const MetalRenderer = struct {
    command_queue: metal.CommandQueue,
    pipeline: metal.RenderPipelineState,
    vertices: std.ArrayList(Vertex),
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator, device: *const metal.Device) !MetalRenderer {
        var command_queue = try device.newCommandQueue();
        errdefer command_queue.deinit();

        var shader_diagnostics = metal.ErrorInfo.init();
        defer shader_diagnostics.deinit();

        var library = device.newLibraryWithSourceDetailed(
            @embedFile("./shaders/test.metal"),
            &shader_diagnostics,
        ) catch |err| {
            std.debug.print("Metal shader error:\n{s}\n", .{shader_diagnostics.message()});
            return err;
        };
        defer library.deinit();

        var vertex_fn = try library.newFunctionWithName("vertex_main");
        defer vertex_fn.deinit();

        var fragment_fn = try library.newFunctionWithName("fragment_main");
        defer fragment_fn.deinit();

        const pipeline_desc = metal.RenderPipelineDescriptor{
            .vertex_function = &vertex_fn,
            .fragment_function = &fragment_fn,
            .color_attachment = metal.ColorAttachmentDescriptor{
                .pixel_format = .bgra8_unorm,
            },
        };
        var pipeline = try device.newRenderPipelineState(pipeline_desc);
        errdefer pipeline.deinit();

        return MetalRenderer{
            .command_queue = command_queue,
            .pipeline = pipeline,
            .vertices = .empty,
            .alloc = alloc,
        };
    }

    pub fn deinit(self: *MetalRenderer) void {
        self.command_queue.deinit();
        self.pipeline.deinit();
        self.vertices.deinit(self.alloc);
    }

    pub fn render(
        self: *MetalRenderer,
        layer: *const metal.MetalLayer,
        draw_list: *const DrawList,
        logical_size: [2]f32,
        framebuffer_size: [2]u32,
    ) !void {
        var drawable = layer.nextDrawable() catch |err| switch (err) {
            error.NoDrawableAvailable => return,
        };
        defer drawable.deinit();

        var texture = try drawable.texture();
        defer texture.deinit();

        const render_pass_desc = metal.RenderPassDescriptor{
            .color_texture = &texture,
            .load_action = .clear,
            .store_action = .store,
            .clear_color = metal.ClearColor{
                .red = 0.1,
                .green = 0.1,
                .blue = 0.1,
                .alpha = 1.0,
            },
        };

        var command_buffer = try self.command_queue.newCommandBuffer();
        defer command_buffer.deinit();

        var render_encoder = try command_buffer.newRenderCommandEncoder(render_pass_desc);
        defer render_encoder.deinit();

        try render_encoder.setViewport(.{
            .origin_x = 0,
            .origin_y = 0,
            .width = @floatFromInt(framebuffer_size[0]),
            .height = @floatFromInt(framebuffer_size[1]),
            .znear = 0,
            .zfar = 1,
        });

        render_encoder.setRenderPipelineState(&self.pipeline);

        const frame_uniforms = FrameUniforms{ .viewport_size = logical_size };
        try render_encoder.setVertexBytes(std.mem.asBytes(&frame_uniforms), 1);

        self.vertices.clearRetainingCapacity();

        for (draw_list.commands.items) |command| {
            switch (command) {
                .rect => |rect| {
                    if (rect.paint.fill) |fill| {
                        try appendRect(
                            &self.vertices,
                            self.alloc,
                            rect.rect,
                            fill,
                        );
                    }
                    if (rect.paint.stroke) |stroke| {
                        try appendRectStroke(
                            &self.vertices,
                            self.alloc,
                            rect.rect,
                            stroke,
                            rect.paint.stroke_width,
                        );
                    }
                },
                .line => |line| {
                    try appendLine(
                        &self.vertices,
                        self.alloc,
                        line.start,
                        line.end,
                        line.stroke.color,
                        line.stroke.width,
                    );
                },
                else => {},
            }
        }

        if (self.vertices.items.len > 0) {
            try render_encoder.setVertexBytes(
                std.mem.sliceAsBytes(self.vertices.items),
                0,
            );
            try render_encoder.drawPrimitives(.triangle, 0, self.vertices.items.len, 1);
        }

        try render_encoder.endEncoding();

        try command_buffer.present(&drawable);
        try command_buffer.commit();
    }
};

fn appendRect(
    vertices: *std.ArrayList(Vertex),
    allocator: std.mem.Allocator,
    rect: Rect,
    color: draw.Color,
) !void {
    const left: f32 = @floatCast(rect.pos.x);
    const top: f32 = @floatCast(rect.pos.y);
    const right: f32 = @floatCast(rect.pos.x + rect.size.x);
    const bottom: f32 = @floatCast(rect.pos.y + rect.size.y);

    const c = [4]f32{ color.r, color.g, color.b, color.a };

    try vertices.appendSlice(allocator, &.{
        .{ .position = .{ left, top }, .color = c },
        .{ .position = .{ left, bottom }, .color = c },
        .{ .position = .{ right, top }, .color = c },

        .{ .position = .{ right, top }, .color = c },
        .{ .position = .{ left, bottom }, .color = c },
        .{ .position = .{ right, bottom }, .color = c },
    });
}

fn appendRectStroke(
    vertices: *std.ArrayList(Vertex),
    allocator: std.mem.Allocator,
    rect: Rect,
    color: draw.Color,
    stroke_width: f32,
) !void {
    if (stroke_width <= 0) return;
    if (rect.size.x <= 0 or rect.size.y <= 0) return;

    const max_width: f64 = @min(rect.size.x, rect.size.y) / 2.0;
    const width: f64 = @min(stroke_width, max_width);

    const top = Rect.init(
        rect.pos.x,
        rect.pos.y,
        rect.size.x,
        width,
    );
    const bottom = Rect.init(
        rect.pos.x,
        rect.pos.y + rect.size.y - width,
        rect.size.x,
        width,
    );
    const middle_height = rect.size.y - width * 2;
    const left = Rect.init(
        rect.pos.x,
        rect.pos.y + width,
        width,
        middle_height,
    );
    const right = Rect.init(
        rect.pos.x + rect.size.x - width,
        rect.pos.y + width,
        width,
        middle_height,
    );

    if (stroke_width <= 0) return;
    if (rect.size.x <= 0 or rect.size.y <= 0) return;

    try appendRect(vertices, allocator, left, color);
    try appendRect(vertices, allocator, right, color);
    try appendRect(vertices, allocator, top, color);
    try appendRect(vertices, allocator, bottom, color);
}

fn appendLine(
    vertices: *std.ArrayList(Vertex),
    allocator: std.mem.Allocator,
    start: draw.Vec2,
    end: draw.Vec2,
    color: draw.Color,
    width: f32,
) !void {
    if (width <= 0.0) return;
    const dx = end.x - start.x;
    const dy = end.y - start.y;
    const length_sq = dx * dx + dy * dy;
    if (length_sq <= 0.000001) return;

    const length = @sqrt(length_sq);
    const nx = -dy / length;
    const ny = dx / length;

    const half_width = width / 2.0;

    const v0 = draw.vec2(
        start.x + nx * half_width,
        start.y + ny * half_width,
    ).tof32();
    const v1 = draw.vec2(
        start.x - nx * half_width,
        start.y - ny * half_width,
    ).tof32();
    const v2 = draw.vec2(
        end.x + nx * half_width,
        end.y + ny * half_width,
    ).tof32();
    const v3 = draw.vec2(
        end.x - nx * half_width,
        end.y - ny * half_width,
    ).tof32();

    const c = [4]f32{ color.r, color.g, color.b, color.a };
    try vertices.appendSlice(allocator, &.{
        .{ .position = .{ v0.x, v0.y }, .color = c },
        .{ .position = .{ v1.x, v1.y }, .color = c },
        .{ .position = .{ v2.x, v2.y }, .color = c },

        .{ .position = .{ v2.x, v2.y }, .color = c },
        .{ .position = .{ v1.x, v1.y }, .color = c },
        .{ .position = .{ v3.x, v3.y }, .color = c },
    });
}
