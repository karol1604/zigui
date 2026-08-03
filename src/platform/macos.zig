extern fn gui_macos_attach(
    window: *anyopaque,
) ?*anyopaque;

extern fn gui_macos_redraw(
    view: *anyopaque,
) void;

extern fn gui_macos_detach(
    view: *anyopaque,
) void;

pub fn attach(window: anytype) !*anyopaque {
    return gui_macos_attach(@ptrCast(window)) orelse error.MacOSViewCreationFailed;
}

pub fn redraw(view: *anyopaque) void {
    gui_macos_redraw(view);
}

pub fn detach(view: *anyopaque) void {
    gui_macos_detach(view);
}
