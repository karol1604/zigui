const std = @import("std");
const Io = std.Io;

const zigui = @import("zigui");

const glfw = @import("glfw");
const cg = @import("coregraphics");
const macos = @import("platform/macos.zig");

fn cBool(val: c_int) bool {
    return val != 0;
}

pub fn main(init: std.process.Init) !void {
    _ = init;
    if (glfw.glfwInit() != glfw.GLFW_TRUE)
        return error.GlfwInitFailed;

    defer glfw.glfwTerminate();

    glfw.glfwWindowHint(
        glfw.GLFW_CLIENT_API,
        glfw.GLFW_NO_API,
    );

    const window = glfw.glfwCreateWindow(
        800,
        600,
        "zig gui",
        null,
        null,
    ) orelse return error.WindowCreationFailed;

    defer glfw.glfwDestroyWindow(window);

    const view = try macos.attach(window);
    defer macos.detach(view);

    while (glfw.glfwWindowShouldClose(window) ==
        glfw.GLFW_FALSE)
    {
        macos.redraw(view);

        glfw.glfwPollEvents();
    }
}

export fn zig_gui_draw(
    raw_context: ?*anyopaque,
    width: f64,
    height: f64,
) callconv(.c) void {
    _ = width;
    _ = height;

    const raw = raw_context orelse return;

    const ctx: cg.CGContextRef = @ptrCast(raw);

    cg.CGContextSetRGBFillColor(
        ctx,
        1.0,
        0.0,
        0.0,
        1.0,
    );

    const rect: cg.CGRect = .{
        .origin = .{
            .x = 50,
            .y = 50,
        },
        .size = .{
            .width = 200,
            .height = 100,
        },
    };

    cg.CGContextFillRect(ctx, rect);
}
