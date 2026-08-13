const std = @import("std");
const draw = @import("draw.zig");
const font = @import("font.zig");

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
    scroll_offset: Vec2 = .{ .x = 0, .y = 0 },

    pub fn beginFrame(self: *InputState) void {
        self.mouse_button_left.pressed = false;
        self.mouse_button_left.released = false;
        self.scroll_offset = .{ .x = 0, .y = 0 };
    }

    pub fn setMouseButton(self: *InputState, is_down: bool) void {
        if (is_down and !self.mouse_button_left.down)
            self.mouse_button_left.pressed = true;

        if (!is_down and self.mouse_button_left.down)
            self.mouse_button_left.released = true;

        self.mouse_button_left.down = is_down;
    }
};

const Layout = struct {
    bounds: Rect,
    gap: f64,
    cursor_y: f64,
};

const ScrollState = struct {
    offset_y: f64 = 0,
    content_height: f64 = 0,
};
const ScrollContext = struct {
    id: u64,
    viewport: Rect,
    options: Ui.ScrollOptions,
};

pub const Ui = struct {
    /// ID of the currently hovered element.
    hot_id: ?u64 = null,
    /// ID of the currently active element (pressed and held).
    active_id: ?u64 = null,
    input: *const InputState = undefined,
    draw_list: *DrawList = undefined,
    clip_stack: std.ArrayList(?Rect) = .empty,
    alloc: std.mem.Allocator,
    fonts: *const font.FontManager,
    default_font: draw.FontHandle,
    layout_stack: std.ArrayList(Layout) = .empty,
    scroll_states: std.AutoHashMap(u64, ScrollState),
    scroll_stack: std.ArrayList(ScrollContext) = .empty,

    pub fn init(alloc: std.mem.Allocator, fonts: *const font.FontManager, default_font: draw.FontHandle) Ui {
        return Ui{
            .alloc = alloc,
            .fonts = fonts,
            .default_font = default_font,
            .scroll_states = std.AutoHashMap(u64, ScrollState).init(alloc),
        };
    }
    pub fn deinit(self: *Ui) void {
        self.clip_stack.deinit(self.alloc);
        self.layout_stack.deinit(self.alloc);
        self.scroll_states.deinit();
        self.scroll_stack.deinit(self.alloc);
    }

    pub fn pushClip(self: *Ui, rect: Rect) !void {
        const effective: ?Rect = if (self.clip_stack.items.len == 0)
            if (rect.size.x > 0 and rect.size.y > 0) rect else null
        else if (self.clip_stack.items[self.clip_stack.items.len - 1]) |parent|
            parent.intersect(rect)
        else
            null;

        try self.clip_stack.append(self.alloc, effective);
        errdefer _ = self.clip_stack.pop();

        try self.draw_list.pushClip(rect);
    }

    pub fn popClip(self: *Ui) !void {
        if (self.clip_stack.items.len == 0)
            return error.ClipStackUnderflow;

        try self.draw_list.popClip();
        _ = self.clip_stack.pop();
    }

    pub fn beginFrame(self: *Ui, input: *const InputState, draw_list: *DrawList) void {
        self.input = input;
        self.draw_list = draw_list;
        self.hot_id = null;
    }

    pub fn endFrame(self: *Ui) void {
        std.debug.assert(self.clip_stack.items.len == 0);
        std.debug.assert(self.layout_stack.items.len == 0);
        std.debug.assert(self.scroll_stack.items.len == 0);

        if (self.input.mouse_button_left.released) {
            self.active_id = null;
        }
    }

    fn isInsideCurrentClip(self: *Ui, pos: Vec2) bool {
        if (self.clip_stack.items.len == 0)
            return true;

        const clip =
            self.clip_stack.items[self.clip_stack.items.len - 1] orelse
            return false;

        return clip.contains(pos);
    }

    pub const ScrollOptions = struct {
        gap: f64 = 8,
        scroll_speed: f64 = 15,
        scrollbar_width: f64 = 6,
        scrollbar_gap: f64 = 4,
        scrollbar_margin: f64 = 2,
        min_thumb_height: f64 = 20,
        track_color: Color = Color.DarkGray,
        thumb_color: Color = Color.Gray,
    };
    pub fn beginScroll(self: *Ui, id: u64, viewport: Rect, options: ScrollOptions) !void {
        const entry = try self.scroll_states.getOrPut(id);
        if (!entry.found_existing) {
            entry.value_ptr.* = .{};
        }

        const state = entry.value_ptr;

        const hovered = viewport.contains(self.input.mouse_pos) and
            self.isInsideCurrentClip(self.input.mouse_pos);
        if (hovered) {
            state.offset_y -= self.input.scroll_offset.y * options.scroll_speed;
        }

        const max_offset = @max(0, state.content_height - viewport.size.y);
        state.offset_y = std.math.clamp(state.offset_y, 0, max_offset);

        try self.pushClip(viewport);

        const gutter = options.scrollbar_width + options.scrollbar_gap + options.scrollbar_margin * 2;
        const content_width = @max(0, viewport.size.x - gutter);

        try self.beginColumn(
            Rect.init(
                viewport.pos.x,
                viewport.pos.y - state.offset_y,
                content_width,
                viewport.size.y,
            ),
            options.gap,
        );

        try self.scroll_stack.append(self.alloc, .{
            .id = id,
            .viewport = viewport,
            .options = options,
        });
    }

    pub fn endScroll(self: *Ui) !void {
        if (self.scroll_stack.items.len == 0) return error.ScrollStackUnderflow;

        const content_height = try self.endColumn();
        const context = self.scroll_stack.pop().?;

        const state = self.scroll_states.getPtr(context.id) orelse return error.MissingScrollState;

        state.content_height = content_height;

        const max_offset = @max(0, content_height - context.viewport.size.y);

        state.offset_y = std.math.clamp(state.offset_y, 0, max_offset);

        if (max_offset > 0) {
            try self.drawScrollbar(context.viewport, content_height, state.offset_y, context.options);
        }

        try self.popClip();
    }

    fn drawScrollbar(
        self: *Ui,
        viewport: Rect,
        content_height: f64,
        offset_y: f64,
        options: ScrollOptions,
    ) !void {
        const track = Rect.init(
            viewport.pos.x + viewport.size.x - options.scrollbar_margin - options.scrollbar_width,
            viewport.pos.y + options.scrollbar_margin,
            options.scrollbar_width,
            viewport.size.y - options.scrollbar_margin * 2,
        );

        const visible_fraction = std.math.clamp(viewport.size.y / content_height, 0, 1);
        const thumb_height = @min(
            track.size.y,
            @max(options.min_thumb_height, track.size.y * visible_fraction),
        );

        const max_offset = content_height - viewport.size.y;
        const scroll_fraction = std.math.clamp(offset_y / max_offset, 0, 1);
        const thumb_travel = track.size.y - thumb_height;

        const thumb = Rect.init(
            track.pos.x,
            track.pos.y + thumb_travel * scroll_fraction,
            track.size.x,
            thumb_height,
        );

        try self.draw_list.addRect(track, .{ .fill = options.track_color });
        try self.draw_list.addRect(thumb, .{ .fill = options.thumb_color });
    }

    pub const ButtonOptions = struct {
        color: Color = Color.RoyalBlue,
        text_color: Color = Color.White,
        padding_y: f64 = 8,
    };

    fn buttonAt(
        self: *Ui,
        id: u64,
        rect: Rect,
        label_text: []const u8,
        label_size: Vec2,
        options: ButtonOptions,
    ) !bool {
        const hovered = rect.contains(self.input.mouse_pos) and
            self.isInsideCurrentClip(self.input.mouse_pos);

        if (hovered) self.hot_id = id;

        if (hovered and self.input.mouse_button_left.pressed) self.active_id = id;

        const active = self.active_id == id;
        var clicked = false;

        if (active and self.input.mouse_button_left.released) {
            clicked = hovered;
            self.active_id = null;
        }

        const color = options.color;
        const fill = if (active and self.input.mouse_button_left.down)
            color.darken(0.2)
        else if (hovered)
            color.lighten(0.12)
        else
            color;

        try self.draw_list.addRect(rect, .{
            .fill = fill,
            .stroke = color.getStrokeColor(),
            .stroke_width = 1,
        });

        const label_position = draw.vec2(
            rect.pos.x + (rect.size.x - label_size.x) / 2,
            rect.pos.y + (rect.size.y - label_size.y) / 2,
        );

        try self.draw_list.addText(self.default_font, label_text, label_position, options.text_color);

        return clicked;
    }

    pub fn button(self: *Ui, id: u64, label_text: []const u8, options: ButtonOptions) !bool {
        const label_size = try self.fonts.measureText(self.default_font, label_text);
        const height = label_size.y + options.padding_y * 2;
        const rect = try self.nextRect(height);

        return self.buttonAt(id, rect, label_text, label_size, options);
    }

    pub const LabelOptions = struct {
        text_color: Color = Color.White,
    };
    pub fn label(self: *Ui, text: []const u8, options: LabelOptions) !void {
        const label_size = try self.fonts.measureText(self.default_font, text);
        const rect = try self.nextRect(label_size.y);

        try self.draw_list.addText(
            self.default_font,
            text,
            draw.vec2(rect.pos.x, rect.pos.y),
            options.text_color,
        );
    }

    pub const SliderOptions = struct {
        height: f64 = 28,
        track_height: f64 = 4,
        knob_radius: f64 = 8,

        track_color: Color = Color.DarkGray,
        fill_color: Color = Color.RoyalBlue,
        knob_color: Color = Color.White,
    };

    pub fn slider(self: *Ui, id: u64, value: *f64, min: f64, max: f64, options: SliderOptions) !bool {
        std.debug.assert(min < max);
        const rect = try self.nextRect(options.height);
        const hovered = rect.contains(self.input.mouse_pos) and
            self.isInsideCurrentClip(self.input.mouse_pos);

        if (hovered) self.hot_id = id;
        if (hovered and self.input.mouse_button_left.pressed) self.active_id = id;

        const active = self.active_id == id;
        var changed = false;

        const center_y = rect.pos.y + rect.size.y / 2;
        const track = Rect.init(
            rect.pos.x + options.knob_radius,
            center_y - options.track_height / 2,
            @max(0, rect.size.x - options.knob_radius * 2), // inset so knob doesn't go outside the slider rect
            options.track_height,
        );

        if (active and self.input.mouse_button_left.down) {
            const t = std.math.clamp(
                (self.input.mouse_pos.x - track.pos.x) / track.size.x,
                0.0,
                1.0,
            );
            const new_value = min + t * (max - min);
            if (new_value != value.*) {
                value.* = new_value;
                changed = true;
            }
        }

        const slider_pc = std.math.clamp(
            (value.* - min) / (max - min),
            0,
            1,
        );

        try self.draw_list.addRect(track, .{
            .fill = options.track_color,
            .stroke = options.track_color.getStrokeColor(),
            .stroke_width = 1,
        });

        const filled_rect = Rect.init(
            track.pos.x,
            track.pos.y,
            track.size.x * slider_pc,
            track.size.y,
        );
        try self.draw_list.addRect(filled_rect, .{
            .fill = options.fill_color,
            .stroke = null,
        });

        const knob_center = draw.vec2(track.pos.x + track.size.x * slider_pc, center_y);
        try self.draw_list.addCircle(knob_center, options.knob_radius, .{
            .fill = options.knob_color,
            .stroke = options.knob_color.getStrokeColor(),
            .stroke_width = 1,
        });

        return changed;
    }

    pub fn spacer(self: *Ui, height: f64) !void {
        _ = try self.nextRect(height);
    }

    pub fn beginColumn(self: *Ui, rect: Rect, gap: f64) !void {
        const layout = Layout{
            .bounds = rect,
            .gap = gap,
            .cursor_y = rect.pos.y,
        };

        try self.layout_stack.append(self.alloc, layout);
    }

    /// Returns the total height of the column content, including the last gap.
    pub fn endColumn(self: *Ui) !f64 {
        if (self.layout_stack.items.len == 0) return error.LayoutStackUnderflow;
        const layout = self.layout_stack.pop().?;

        return @max(0, layout.cursor_y - layout.bounds.pos.y - layout.gap);
    }

    fn nextRect(self: *Ui, height: f64) !Rect {
        if (self.layout_stack.items.len == 0) return error.NoActiveLayout;
        const layout = &self.layout_stack.items[self.layout_stack.items.len - 1];

        const rect = Rect.init(
            layout.bounds.pos.x,
            layout.cursor_y,
            layout.bounds.size.x,
            height,
        );

        layout.cursor_y += height + layout.gap;
        return rect;
    }
};
