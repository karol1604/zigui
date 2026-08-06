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

    var input_state: zigui.InputState = .{};
    var ui: zigui.Ui = .{};

    _ = glfw.glfwSetWindowUserPointer(window, @ptrCast(&input_state));

    _ = glfw.glfwSetCursorPosCallback(window, cursorPosCallback);
    _ = glfw.glfwSetMouseButtonCallback(window, mouseButtonCallback);
    _ = glfw.glfwSetWindowFocusCallback(window, windowFocusCallback);

    while (!cBool(glfw.glfwWindowShouldClose(window))) {
        var width: c_int = 0;
        var height: c_int = 0;
        glfw.glfwGetFramebufferSize(window, &width, &height);

        input_state.beginFrame();

        glfw.glfwPollEvents();
        render_state.draw_list.reset();
        ui.beginFrame(&input_state, &render_state.draw_list);
        defer ui.endFrame();

        try render_state.draw_list.addRect(
            Rect.init(0, 0, @floatFromInt(width), @floatFromInt(height)),
            .{
                .fill = zigui.Color.rgba(0.1, 0.1, 0.1, 1.0),
            },
        );

        var xpos: f64 = 0;
        var ypos: f64 = 0;
        glfw.glfwGetCursorPos(window, &xpos, &ypos);

        if (try ui.button(1, ex_rect)) {
            std.log.info("Button clicked!", .{});
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

fn getInputState(
    window: ?*glfw.GLFWwindow,
) ?*zigui.InputState {
    const actual_window = window orelse return null;

    const raw =
        glfw.glfwGetWindowUserPointer(actual_window) orelse
        return null;

    return @ptrCast(@alignCast(raw));
}

fn cursorPosCallback(window: ?*glfw.GLFWwindow, x: f64, y: f64) callconv(.c) void {
    const input_state = getInputState(window) orelse return;
    input_state.mouse_pos = zigui.vec2(x, y);
}

fn mouseButtonCallback(
    window: ?*glfw.GLFWwindow,
    button: c_int,
    action: c_int,
    _: c_int,
) callconv(.c) void {
    const input = getInputState(window) orelse return;

    if (button != glfw.GLFW_MOUSE_BUTTON_LEFT)
        return;

    switch (action) {
        glfw.GLFW_PRESS => input.setMouseButton(true),
        glfw.GLFW_RELEASE => input.setMouseButton(false),
        else => {},
    }
}

fn windowFocusCallback(
    window: ?*glfw.GLFWwindow,
    focused: c_int,
) callconv(.c) void {
    const input = getInputState(window) orelse return;

    if (!cBool(focused)) {
        if (input.mouse_button_left.down)
            input.mouse_button_left.released = true;

        input.mouse_button_left.down = false;
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
}
