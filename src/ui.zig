const draw = @import("draw.zig");

const Vec2 = draw.Vec2;
const Rect = draw.Rect;
const Color = draw.Color;
const DrawList = draw.DrawList;

pub const ButtonState = struct {
    down: bool = false,
    pressed: bool = false,
    released: bool = false,
};

pub const InputState = struct {
    mouse_pos: Vec2 = .{ .x = 0, .y = 0 },
    mouse_button_left: ButtonState = .{},

    pub fn beginFrame(self: *InputState) void {
        self.mouse_button_left.pressed = false;
        self.mouse_button_left.released = false;
    }

    pub fn setMouseButton(self: *InputState, is_down: bool) void {
        if (is_down and !self.mouse_button_left.down)
            self.mouse_button_left.pressed = true;

        if (!is_down and self.mouse_button_left.down)
            self.mouse_button_left.released = true;

        self.mouse_button_left.down = is_down;
    }
};

pub const Ui = struct {
    /// ID of the currently hovered element.
    hot_id: ?u64 = null,
    /// ID of the currently active element (pressed and held).
    active_id: ?u64 = null,
    input: *const InputState = undefined,
    draw_list: *DrawList = undefined,

    pub fn beginFrame(self: *Ui, input: *const InputState, draw_list: *DrawList) void {
        self.input = input;
        self.draw_list = draw_list;
        self.hot_id = null;
    }

    pub fn endFrame(self: *Ui) void {
        if (self.input.mouse_button_left.released) {
            self.active_id = null;
        }
    }

    pub fn button(self: *Ui, id: u64, rect: Rect) !bool {
        const hovered = rect.contains(self.input.mouse_pos);

        if (hovered) self.hot_id = id;

        if (hovered and self.input.mouse_button_left.pressed) self.active_id = id;

        const active = self.active_id == id;
        var clicked = false;

        if (active and self.input.mouse_button_left.released) {
            clicked = hovered;
            self.active_id = null;
        }

        const fill = if (active and self.input.mouse_button_left.down)
            Color.fromHex(0x245C8A)
        else if (hovered)
            Color.fromHex(0x367DB5)
        else
            Color.fromHex(0x2B6591);

        try self.draw_list.addRect(rect, .{
            .fill = fill,
            .stroke = Color.fromHex(0x70A6CF),
            .stroke_width = 1,
        });

        return clicked;
    }
};
