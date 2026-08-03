extern fn gui_macos_attach(
    window: *anyopaque,
    render_state: *anyopaque,
) ?*anyopaque;

extern fn gui_macos_redraw(
    view: *anyopaque,
) void;

extern fn gui_macos_detach(
    view: *anyopaque,
) void;

pub fn attach(window: anytype, render_state: anytype) !*anyopaque {
    return gui_macos_attach(
        @ptrCast(window),
        @ptrCast(render_state),
    ) orelse error.MacOSViewCreationFailed;
}

pub fn redraw(view: *anyopaque) void {
    gui_macos_redraw(view);
}

pub fn detach(view: *anyopaque) void {
    gui_macos_detach(view);
}
