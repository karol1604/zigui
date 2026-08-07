const std = @import("std");

pub const Vec2 = struct {
    x: f64,
    y: f64,

    pub fn tof32(self: Vec2) struct { x: f32, y: f32 } {
        return .{ .x = @floatCast(self.x), .y = @floatCast(self.y) };
    }
};

pub fn vec2(x: f64, y: f64) Vec2 {
    return .{ .x = x, .y = y };
}

pub const Rect = struct {
    pos: Vec2,
    size: Vec2,

    pub fn init(x: f64, y: f64, width: f64, height: f64) Rect {
        return .{
            .pos = .{ .x = x, .y = y },
            .size = .{ .x = width, .y = height },
        };
    }

    pub fn contains(self: Rect, point: Vec2) bool {
        return point.x >= self.pos.x and
            point.y >= self.pos.y and
            point.x < self.pos.x + self.size.x and
            point.y < self.pos.y + self.size.y;
    }
};

pub const Color = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,

    /// The components are expected to be in the range [0.0, 1.0].
    pub fn rgba(r: f32, g: f32, b: f32, a: f32) Color {
        return .{
            .r = r,
            .g = g,
            .b = b,
            .a = a,
        };
    }

    pub fn rgb(r: f32, g: f32, b: f32) Color {
        return Color.rgba(r, g, b, 1.0);
    }

    pub fn fromHex(hex: u32) Color {
        const r: f32 = @floatFromInt((hex >> 16) & 0xFF);
        const g: f32 = @floatFromInt((hex >> 8) & 0xFF);
        const b: f32 = @floatFromInt(hex & 0xFF);

        return .{
            .r = r / 255.0,
            .g = g / 255.0,
            .b = b / 255.0,
            .a = 1.0,
        };
    }
};

pub const Stroke = struct {
    color: Color,
    width: f32,
};

pub const Paint = struct {
    fill: ?Color = null,
    stroke: ?Color = null,
    stroke_width: f32 = 1,
};

pub const RectCommand = struct {
    rect: Rect,
    paint: Paint,
};

pub const EllipseCommand = struct {
    rect: Rect,
    paint: Paint,
};

pub const LineCommand = struct {
    start: Vec2,
    end: Vec2,
    stroke: Stroke,
};

pub const DrawCommand = union(enum) {
    rect: RectCommand,
    ellipse: EllipseCommand,
    line: LineCommand,
    text: TextCommand,
};

pub const TextCommand = struct {
    text: []const u8,
};

pub const DrawList = struct {
    commands: std.ArrayList(DrawCommand),
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) !DrawList {
        return .{
            .commands = .empty,
            .alloc = alloc,
        };
    }

    pub fn deinit(self: *DrawList) void {
        self.commands.deinit(self.alloc);
    }

    pub fn reset(self: *DrawList) void {
        self.commands.clearRetainingCapacity();
    }

    pub fn addRect(self: *DrawList, rect: Rect, paint: Paint) !void {
        try self.commands.append(self.alloc, .{ .rect = .{
            .rect = rect,
            .paint = paint,
        } });
    }

    pub fn addText(self: *DrawList, text: []const u8) !void {
        try self.commands.append(self.alloc, .{ .text = .{
            .text = text,
        } });
    }

    pub fn addEllipse(self: *DrawList, rect: Rect, paint: Paint) !void {
        try self.commands.append(self.alloc, .{ .ellipse = .{
            .rect = rect,
            .paint = paint,
        } });
    }

    pub fn addLine(self: *DrawList, start: Vec2, end: Vec2, stroke: Stroke) !void {
        try self.commands.append(self.alloc, .{ .line = .{
            .start = start,
            .end = end,
            .stroke = stroke,
        } });
    }

    pub fn addCircle(self: *DrawList, center: Vec2, radius: f64, paint: Paint) !void {
        const rect = Rect.init(
            center.x - radius,
            center.y - radius,
            radius * 2,
            radius * 2,
        );
        try self.addEllipse(rect, paint);
    }
};
