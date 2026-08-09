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

    pub fn intersect(self: Rect, other: Rect) ?Rect {
        const x1 = @max(self.pos.x, other.pos.x);
        const y1 = @max(self.pos.y, other.pos.y);
        const x2 = @min(self.pos.x + self.size.x, other.pos.x + other.size.x);
        const y2 = @min(self.pos.y + self.size.y, other.pos.y + other.size.y);

        if (x2 <= x1 or y2 <= y1) {
            return null;
        }

        return .{
            .pos = .{ .x = x1, .y = y1 },
            .size = .{ .x = x2 - x1, .y = y2 - y1 },
        };
    }
};

pub const Color = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,

    pub const Transparent = Color.rgba(0.0, 0.0, 0.0, 0.0);

    pub const Black = Color.fromHex(0x000000);
    pub const White = Color.fromHex(0xFFFFFF);

    pub const Red = Color.fromHex(0xFF0000);
    pub const Green = Color.fromHex(0x008000);
    pub const Blue = Color.fromHex(0x0000FF);

    pub const Yellow = Color.fromHex(0xFFFF00);
    pub const Cyan = Color.fromHex(0x00FFFF);
    pub const Magenta = Color.fromHex(0xFF00FF);

    pub const Orange = Color.fromHex(0xFFA500);
    pub const Purple = Color.fromHex(0x800080);
    pub const Pink = Color.fromHex(0xFFC0CB);
    pub const Brown = Color.fromHex(0xA52A2A);

    pub const Gray = Color.fromHex(0x808080);
    pub const Grey = Gray;
    pub const LightGray = Color.fromHex(0xD3D3D3);
    pub const DarkGray = Color.fromHex(0x404040);
    pub const Silver = Color.fromHex(0xC0C0C0);

    pub const Maroon = Color.fromHex(0x800000);
    pub const Olive = Color.fromHex(0x808000);
    pub const Lime = Color.fromHex(0x00FF00);
    pub const Teal = Color.fromHex(0x008080);
    pub const Navy = Color.fromHex(0x000080);
    pub const Aqua = Color.fromHex(0x00FFFF);
    pub const Fuchsia = Color.fromHex(0xFF00FF);

    pub const Coral = Color.fromHex(0xFF7F50);
    pub const Salmon = Color.fromHex(0xFA8072);
    pub const Gold = Color.fromHex(0xFFD700);
    pub const Beige = Color.fromHex(0xF5F5DC);
    pub const Ivory = Color.fromHex(0xFFFFF0);
    pub const Khaki = Color.fromHex(0xF0E68C);
    pub const Violet = Color.fromHex(0xEE82EE);
    pub const Indigo = Color.fromHex(0x4B0082);
    pub const Lavender = Color.fromHex(0xE6E6FA);

    pub const Turquoise = Color.fromHex(0x40E0D0);
    pub const Mint = Color.fromHex(0x98FF98);
    pub const SkyBlue = Color.fromHex(0x87CEEB);
    pub const RoyalBlue = Color.fromHex(0x4169E1);

    pub const Crimson = Color.fromHex(0xDC143C);
    pub const Tomato = Color.fromHex(0xFF6347);
    pub const Chocolate = Color.fromHex(0xD2691E);
    pub const Tan = Color.fromHex(0xD2B48C);

    pub const Charcoal = Color.fromHex(0x36454F);
    pub const Slate = Color.fromHex(0x708090);

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

    fn luminance(c: Color) f32 {
        return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
    }

    fn mix(a: Color, b: Color, t: f32) Color {
        return .{
            .r = a.r + (b.r - a.r) * t,
            .g = a.g + (b.g - a.g) * t,
            .b = a.b + (b.b - a.b) * t,
            .a = a.a + (b.a - a.a) * t,
        };
    }

    pub fn lighten(self: Color, amount: f32) Color {
        var result = Color.mix(self, Color.White, std.math.clamp(amount, 0, 1));
        result.a = self.a;
        return result;
    }

    pub fn darken(self: Color, amount: f32) Color {
        var result = Color.mix(self, Color.Black, std.math.clamp(amount, 0, 1));
        result.a = self.a;
        return result;
    }

    pub fn getStrokeColor(self: Color) Color {
        const lum = Color.luminance(self);
        if (lum < 0.5) {
            return self.lighten(0.5);
        } else {
            return self.darken(0.5);
        }
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

pub const TextCommand = struct {
    text: []const u8,
};

pub const ImageCommand = struct {
    texture: TextureHandle,
    rect: Rect,

    uv_min: [2]f32 = .{ 0, 0 },
    uv_max: [2]f32 = .{ 1, 1 },

    tint: Color = Color.White,
};

pub const DrawCommand = union(enum) {
    rect: RectCommand,
    ellipse: EllipseCommand,
    line: LineCommand,
    text: TextCommand,
    image: ImageCommand,
    push_clip: Rect,
    pop_clip,
};

pub const TextureHandle = u32;

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

    pub fn addImage(
        self: *DrawList,
        texture: TextureHandle,
        rect: Rect,
        options: struct {
            uv_min: [2]f32 = .{ 0, 0 },
            uv_max: [2]f32 = .{ 1, 1 },
            tint: Color = Color.White,
        },
    ) !void {
        try self.commands.append(self.alloc, .{
            .image = .{
                .texture = texture,
                .rect = rect,
                .uv_min = options.uv_min,
                .uv_max = options.uv_max,
                .tint = options.tint,
            },
        });
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

    pub fn pushClip(self: *DrawList, rect: Rect) !void {
        try self.commands.append(self.alloc, .{ .push_clip = rect });
    }

    pub fn popClip(self: *DrawList) !void {
        try self.commands.append(self.alloc, .{ .pop_clip = {} });
    }
};
