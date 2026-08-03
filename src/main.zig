const std = @import("std");
const Io = std.Io;

const zigui = @import("zigui");

const glfw = @import("glfw");
const cg = zigui.cg;
const macos = @import("platform/macos.zig");

const Rect = zigui.Rect;

fn cBool(val: c_int) bool {
    return val != 0;
}

const WINDOW_WIDTH: usize = 800;
const WINDOW_HEIGHT: usize = 600;

const ex_rect = Rect.init(50, 50, 700, 100);

pub fn main(init: std.process.Init) !void {
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
        "zig gui",
        null,
        null,
    ) orelse return error.WindowCreationFailed;

    defer glfw.glfwDestroyWindow(window);

    const alloc = init.arena.allocator();

    var render_state = try zigui.RendererState.init(alloc);
    defer render_state.deinit();

    const view = try macos.attach(window, &render_state);
    defer macos.detach(view);

    while (!cBool(glfw.glfwWindowShouldClose(window))) {
        glfw.glfwPollEvents();
        render_state.draw_list.reset();

        try render_state.draw_list.addRect(
            Rect.init(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT),
            .{
                .fill = zigui.Color.rgba(0.1, 0.1, 0.1, 1.0),
            },
        );

        var xpos: f64 = 0;
        var ypos: f64 = 0;
        glfw.glfwGetCursorPos(window, &xpos, &ypos);

        try render_state.draw_list.addRect(
            ex_rect,
            .{
                .stroke = zigui.Color.rgba(0.1, 0.5, 0.1, 1.0),
                .fill = zigui.Color.rgba(0.1, 0.1, 0.5, 1.0),
            },
        );

        if (ex_rect.contains(zigui.vec2(xpos, ypos))) {
            try render_state.draw_list.addRect(
                ex_rect,
                .{
                    .fill = zigui.Color.rgba(0.5, 0.1, 0.1, 1.0),
                },
            );
        }

        try render_state.draw_list.addCircle(
            zigui.vec2(400, 300),
            100,
            .{
                .fill = zigui.Color.fromHex(0x80fc03),
                .stroke = zigui.Color.fromHex(0x03b1fc),
                .stroke_width = 20,
            },
        );

        try render_state.draw_list.addCircle(
            zigui.vec2(400, 300),
            50,
            zigui.Paint{
                .fill = zigui.Color.fromHex(0xfc03ca),
                .stroke_width = 20,
            },
        );

        try render_state.draw_list.addCircle(
            zigui.vec2(400, 300),
            25,
            zigui.Paint{
                .fill = zigui.Color.fromHex(0x03fcd3),
                .stroke_width = 20,
            },
        );

        try render_state.draw_list.addLine(
            zigui.vec2(100, 300),
            zigui.vec2(700, 300),
            .{
                .color = zigui.Color.fromHex(0x7703fc),
                .width = 5,
            },
        );

        try render_state.draw_list.addLine(
            zigui.vec2(400, 100),
            zigui.vec2(400, 500),
            .{
                .color = zigui.Color.fromHex(0x7703fc),
                .width = 5,
            },
        );

        macos.redraw(view);
    }
}

export fn zig_gui_draw(
    raw_render_state: ?*anyopaque,
    raw_context: ?*anyopaque,
    width: f64,
    height: f64,
) callconv(.c) void {
    _ = width;
    _ = height;
    const raw = raw_context orelse return;

    const ctx: cg.CGContextRef = @ptrCast(raw);
    const render_state: *zigui.RendererState =
        @ptrCast(@alignCast(raw_render_state orelse return));

    render_state.render(ctx) catch |err| {
        std.log.err("CoreGraphics rendering failed: {}", .{err});
    };

    //
}
