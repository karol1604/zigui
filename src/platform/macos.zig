extern fn gui_macos_attach(
    window: *anyopaque,
    metal_layer: *anyopaque,
) ?*anyopaque;

extern fn gui_macos_resize_drawable(
    view: *anyopaque,
    width: usize,
    height: usize,
) void;

extern fn gui_macos_detach(view: *anyopaque) void;

/// Attaches a caller-owned CAMetalLayer to a child view of a GLFW Cocoa window.
pub fn attach(window: anytype, metal_layer: anytype) !*anyopaque {
    return gui_macos_attach(
        @ptrCast(window),
        @ptrCast(metal_layer),
    ) orelse
        error.MacOSViewCreationFailed;
}

/// Updates CAMetalLayer.drawableSize using physical framebuffer pixels.
pub fn resizeDrawable(view: *anyopaque, width: usize, height: usize) void {
    gui_macos_resize_drawable(view, width, height);
}

pub fn detach(view: *anyopaque) void {
    gui_macos_detach(view);
}
