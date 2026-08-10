const std = @import("std");

const glfw = @import("glfw");
const metal = @import("metalzig");
const macos = @import("platform/macos.zig");
const zigui = @import("zigui");
const zigimg = @import("zigimg");
const cg = @import("coregraphics");

fn cBool(val: c_int) bool {
    return val != 0;
}

const WINDOW_WIDTH = 800;
const WINDOW_HEIGHT = 600;

pub fn main(init: std.process.Init) !void {
    // const alloc = init.arena.allocator();
    const alloc = init.gpa;

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

    var renderer = try zigui.MetalRenderer.init(alloc, &device);
    defer renderer.deinit();

    var layer = try device.newMetalLayer();
    defer layer.deinit();

    // NOTE: has to be the same as the pipeline descriptor in the renderer!
    layer.setPixelFormat(.bgra8_unorm);
    layer.setFramebufferOnly(true);

    const view = try macos.attach(window, layer.nativeHandle());
    defer macos.detach(view);

    var draw_list = try zigui.DrawList.init(alloc);
    defer draw_list.deinit();
    var ui: zigui.Ui = .{ .alloc = alloc };
    defer ui.deinit();
    var input_state: zigui.InputState = .{};

    _ = glfw.glfwSetWindowUserPointer(window, @ptrCast(&input_state));

    _ = glfw.glfwSetCursorPosCallback(window, cursorPosCallback);
    _ = glfw.glfwSetMouseButtonCallback(window, mouseButtonCallback);
    _ = glfw.glfwSetWindowFocusCallback(window, windowFocusCallback);

    var read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;
    var image = try zigimg.Image.fromFilePath(alloc, init.io, "paper.jpg", read_buffer[0..]);
    defer image.deinit(alloc);

    std.log.info("Image loaded: {d}x{d} => {any}", .{ image.width, image.height, image.pixelFormat() });
    std.log.info("Image data length: {any}", .{image.pixels.rgb24[0]});

    const texture_pixels = try alloc.alloc(u8, image.width * image.height * 4);
    defer alloc.free(texture_pixels);

    for (image.pixels.rgb24, 0..) |pixel, idx| {
        texture_pixels[idx * 4 + 0] = pixel.r;
        texture_pixels[idx * 4 + 1] = pixel.g;
        texture_pixels[idx * 4 + 2] = pixel.b;
        texture_pixels[idx * 4 + 3] = 255;
    }
    const tex = try renderer.createTextureRgba8(image.width, image.height, texture_pixels, 4 * image.width);
    _ = tex;

    const checker_pixels = [_]u8{
        255, 0,   0,   255,
        0,   255, 0,   255,
        0,   0,   255, 255,
        255, 255, 255, 255,
    };
    const checker = try renderer.createTextureRgba8(2, 2, &checker_pixels, 4 * 2);
    _ = checker;

    const font = try renderer.createFont(52);

    while (!cBool(glfw.glfwWindowShouldClose(window))) {
        input_state.beginFrame();
        glfw.glfwPollEvents();

        var fb_width: c_int = 0;
        var fb_height: c_int = 0;
        glfw.glfwGetFramebufferSize(window, &fb_width, &fb_height);

        var logical_width: c_int = 0;
        var logical_height: c_int = 0;
        glfw.glfwGetWindowSize(window, &logical_width, &logical_height);

        if (fb_width <= 0 or fb_height <= 0)
            continue;

        macos.resizeDrawable(
            view,
            @intCast(fb_width),
            @intCast(fb_height),
        );

        draw_list.reset();
        ui.beginFrame(&input_state, &draw_list);

        try draw_list.addText(
            font,
            "hello from zigui!",
            zigui.vec2(200, 200),
            zigui.Color.Crimson,
        );

        // try draw_list.addRect(
        //     zigui.Rect.init(100, 100, 300, 200),
        //     .{
        //         .fill = zigui.Color.Lime,
        //     },
        // );
        //
        // try draw_list.addImage(
        //     tex,
        //     zigui.Rect.init(400, 100, 300, 400),
        //     .{
        //         .uv_min = .{ 0.5, 0.5 },
        //         .uv_max = .{ 1, 1 },
        //         .tint = zigui.Color.Crimson,
        //     },
        // );
        //
        // try ui.pushClip(zigui.Rect.init(0, 0, 300, 300));
        //
        // if (try ui.button(1, zigui.Rect.init(25, 25, 100, 50), zigui.Color.Coral)) {
        //     std.log.info("Button 1 pressed!", .{});
        // }
        // try ui.pushClip(zigui.Rect.init(150, 0, 200, 50));
        //
        // if (try ui.button(2, zigui.Rect.init(150, 25, 100, 50), zigui.Color.Teal)) {
        //     std.log.info("Button 2 pressed!", .{});
        // }
        // try ui.popClip();
        //
        // try draw_list.addRect(
        //     zigui.Rect.init(100, 100, 400, 400),
        //     .{
        //         .fill = zigui.Color.rgb(1, 0.4, 0.6),
        //         .stroke = zigui.Color.fromHex(0x6642f5),
        //         .stroke_width = 20,
        //     },
        // );
        // try draw_list.addLine(
        //     zigui.vec2(100, 100),
        //     zigui.vec2(500, 500),
        //     .{
        //         .color = zigui.Color.Red,
        //         .width = 4,
        //     },
        // );
        // try ui.popClip();
        //
        // try ui.pushClip(zigui.Rect.init(400, 124000, 200, 200));
        //
        // try draw_list.addLine(
        //     zigui.vec2(100, 500),
        //     zigui.vec2(500, 100),
        //     .{
        //         .color = zigui.Color.Red,
        //         .width = 4,
        //     },
        // );
        // try ui.popClip();
        //
        // try draw_list.addCircle(
        //     zigui.vec2(400, 400),
        //     100,
        //     .{
        //         .fill = zigui.Color.Crimson,
        //         // .stroke = zigui.Color.fromHex(0x6642f5),
        //         // .stroke_width = 20,
        //     },
        // );
        //
        ui.endFrame();

        try renderer.render(
            &layer,
            &draw_list,
            .{ @floatFromInt(logical_width), @floatFromInt(logical_height) },
            .{ @intCast(fb_width), @intCast(fb_height) },
        );
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
