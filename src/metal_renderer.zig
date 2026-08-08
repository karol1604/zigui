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
    batches: std.ArrayList(Batch),
    clip_stack: std.ArrayList(?Rect),
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
            .batches = .empty,
            .clip_stack = .empty,
            .alloc = alloc,
        };
    }

    pub fn deinit(self: *MetalRenderer) void {
        self.command_queue.deinit();
        self.pipeline.deinit();
        self.vertices.deinit(self.alloc);
        self.batches.deinit(self.alloc);
        self.clip_stack.deinit(self.alloc);
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
        self.batches.clearRetainingCapacity();
        self.clip_stack.clearRetainingCapacity();

        var active_clip: ?Rect = .{
            .pos = draw.vec2(0, 0),
            .size = draw.vec2(logical_size[0], logical_size[1]),
        };
        var batch_start: usize = 0;

        try self.clip_stack.append(self.alloc, active_clip);

        command_loop: for (draw_list.commands.items) |command| {
            switch (command) {
                .push_clip => |rect| {
                    if (active_clip) |clip| {
                        batch_start = try self.finishBatch(batch_start, clip);
                    }

                    active_clip = if (active_clip) |parent|
                        parent.intersect(rect)
                    else
                        null;
                    try self.clip_stack.append(self.alloc, active_clip);
                },
                .pop_clip => {
                    // NOTE: for debug
                    if (active_clip) |cl| {
                        try appendRectStroke(
                            &self.vertices,
                            self.alloc,
                            cl,
                            draw.Color.Lime,
                            1,
                        );
                    }

                    if (active_clip) |clip| {
                        batch_start = try self.finishBatch(batch_start, clip);
                    }

                    if (self.clip_stack.items.len <= 1)
                        return error.ClipStackUnderflow;

                    _ = self.clip_stack.pop();
                    active_clip = self.clip_stack.items[self.clip_stack.items.len - 1];
                },
                else => {
                    if (active_clip == null) continue :command_loop;

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
                        else => {
                            std.log.warn("Unsupported draw command: {s}", .{@tagName(command)});
                        },
                    }
                },
            }
        }
        if (active_clip) |clip| {
            _ = try self.finishBatch(batch_start, clip);
        }

        if (self.clip_stack.items.len != 1) {
            try render_encoder.endEncoding();
            return error.UnbalancedClipStack;
        }

        if (self.batches.items.len > 0) {
            try render_encoder.setVertexBytes(
                std.mem.sliceAsBytes(self.vertices.items),
                0,
            );

            for (self.batches.items) |batch| {
                try render_encoder.setScissorRect(
                    clipToScissorRect(batch.clip, logical_size, framebuffer_size),
                );

                try render_encoder.drawPrimitives(
                    .triangle,
                    batch.first_vertex,
                    batch.vertex_count,
                    1,
                );
            }
        }

        try render_encoder.endEncoding();

        try command_buffer.present(&drawable);
        try command_buffer.commit();
    }

    /// Returns the new batch start index after finishing the current batch.
    fn finishBatch(
        self: *MetalRenderer,
        batch_start: usize,
        active_clip: Rect,
    ) !usize {
        const end = self.vertices.items.len;

        if (end == batch_start)
            return batch_start; // no new vertices, no need to create a batch.

        try self.batches.append(self.alloc, .{
            .first_vertex = batch_start,
            .vertex_count = end - batch_start,
            .clip = active_clip,
        });

        return end;
    }
};

const Batch = struct {
    first_vertex: usize,
    vertex_count: usize,
    clip: Rect,
};

fn clipToScissorRect(
    clip: Rect,
    logical_size: [2]f32,
    framebuffer_size: [2]u32,
) metal.ScissorRect {
    const scale_x = @as(f64, @floatFromInt(framebuffer_size[0])) / logical_size[0];
    const scale_y = @as(f64, @floatFromInt(framebuffer_size[1])) / logical_size[1];

    const left = std.math.clamp(clip.pos.x, 0, logical_size[0]);
    const top = std.math.clamp(clip.pos.y, 0, logical_size[1]);
    const right = std.math.clamp(clip.pos.x + clip.size.x, 0, logical_size[0]);
    const bottom = std.math.clamp(clip.pos.y + clip.size.y, 0, logical_size[1]);

    const left_fb: usize = @floor(left * scale_x);
    const top_fb: usize = @floor(top * scale_y);
    const right_fb: usize = @ceil(right * scale_x);
    const bottom_fb: usize = @ceil(bottom * scale_y);

    return metal.ScissorRect{
        .x = left_fb,
        .y = top_fb,
        .width = right_fb - left_fb,
        .height = bottom_fb - top_fb,
    };
}

fn appendRect(
    vertices: *std.ArrayList(Vertex),
    allocator: std.mem.Allocator,
    rect: Rect,
    color: draw.Color,
) !void {
    if (rect.size.x <= 0 or rect.size.y <= 0) return;

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
