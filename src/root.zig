pub const cg = @import("coregraphics");
const std = @import("std");

pub const RendererState = struct {
    renderer: CGRenderer,
    draw_list: DrawList,

    pub fn init(alloc: std.mem.Allocator) !RendererState {
        return .{
            .renderer = .{},
            .draw_list = try DrawList.init(alloc),
        };
    }

    pub fn deinit(self: *RendererState) void {
        self.draw_list.deinit();
    }

    pub fn render(
        self: *RendererState,
        context: cg.CGContextRef,
    ) !void {
        try self.renderer.render(context, &self.draw_list);
    }
};

pub const Vec2 = struct {
    x: f64,
    y: f64,
};
pub fn vec2(x: f64, y: f64) Vec2 {
    return Vec2{ .x = x, .y = y };
}

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
};

pub const DrawList = struct {
    commands: std.ArrayList(DrawCommand),
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) !DrawList {
        return DrawList{
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
        try self.commands.append(self.alloc, DrawCommand{ .rect = .{
            .rect = rect,
            .paint = paint,
        } });
    }

    pub fn addEllipse(self: *DrawList, rect: Rect, paint: Paint) !void {
        try self.commands.append(self.alloc, DrawCommand{ .ellipse = .{
            .rect = rect,
            .paint = paint,
        } });
    }

    pub fn addLine(self: *DrawList, start: Vec2, end: Vec2, stroke: Stroke) !void {
        try self.commands.append(self.alloc, DrawCommand{ .line = .{
            .start = start,
            .end = end,
            .stroke = stroke,
        } });
    }

    pub fn addCircle(self: *DrawList, center: Vec2, radius: f64, paint: Paint) !void {
        const rect = Rect.init(center.x - radius, center.y - radius, radius * 2, radius * 2);
        try self.addEllipse(rect, paint);
    }
};

pub const CGRenderer = struct {
    pub fn render(_: *CGRenderer, context: cg.CGContextRef, draw_list: *const DrawList) !void {
        cg.CGContextSaveGState(context);
        defer cg.CGContextRestoreGState(context);

        for (draw_list.commands.items) |command| {
            switch (command) {
                .rect => |rect| drawRect(context, rect),
                .ellipse => |ellipse| drawEllipse(context, ellipse),
                .line => |line| drawLine(context, line),
            }
        }
    }

    fn drawLine(context: cg.CGContextRef, line_command: LineCommand) void {
        const start = line_command.start;
        const end = line_command.end;
        const stroke = line_command.stroke;

        cg.CGContextSetRGBStrokeColor(
            context,
            stroke.color.r,
            stroke.color.g,
            stroke.color.b,
            stroke.color.a,
        );
        cg.CGContextSetLineWidth(context, stroke.width);
        cg.CGContextMoveToPoint(context, start.x, start.y);
        cg.CGContextAddLineToPoint(context, end.x, end.y);
        cg.CGContextStrokePath(context);
    }

    fn drawEllipse(context: cg.CGContextRef, ellipse_command: EllipseCommand) void {
        const rect = ellipse_command.rect;
        const paint = ellipse_command.paint;

        if (paint.fill) |fill_color| {
            cg.CGContextSetRGBFillColor(
                context,
                fill_color.r,
                fill_color.g,
                fill_color.b,
                fill_color.a,
            );
            cg.CGContextAddEllipseInRect(context, toCGRect(rect));
            cg.CGContextFillPath(context);
        }

        if (paint.stroke) |stroke_color| {
            cg.CGContextSetRGBStrokeColor(
                context,
                stroke_color.r,
                stroke_color.g,
                stroke_color.b,
                stroke_color.a,
            );
            cg.CGContextSetLineWidth(context, paint.stroke_width);
            cg.CGContextAddEllipseInRect(context, toCGRect(rect));
            cg.CGContextStrokePath(context);
        }
    }

    fn drawRect(context: cg.CGContextRef, rect_command: RectCommand) void {
        const rect = rect_command.rect;
        const paint = rect_command.paint;

        if (paint.fill) |fill_color| {
            cg.CGContextSetRGBFillColor(
                context,
                fill_color.r,
                fill_color.g,
                fill_color.b,
                fill_color.a,
            );
            cg.CGContextFillRect(context, toCGRect(rect));
        }

        if (paint.stroke) |stroke_color| {
            cg.CGContextSetRGBStrokeColor(
                context,
                stroke_color.r,
                stroke_color.g,
                stroke_color.b,
                stroke_color.a,
            );
            cg.CGContextSetLineWidth(context, paint.stroke_width);
            cg.CGContextStrokeRect(context, toCGRect(rect));
        }
    }

    fn toCGRect(self: Rect) cg.CGRect {
        return cg.CGRect{
            .origin = cg.CGPoint{ .x = self.pos.x, .y = self.pos.y },
            .size = cg.CGSize{ .width = self.size.x, .height = self.size.y },
        };
    }
};

pub const Rect = struct {
    pos: Vec2,
    size: Vec2,

    pub fn init(x: f64, y: f64, width: f64, height: f64) Rect {
        return Rect{
            .pos = Vec2{ .x = x, .y = y },
            .size = Vec2{ .x = width, .y = height },
        };
    }

    pub fn contains(self: Rect, point: Vec2) bool {
        return point.x > self.pos.x and point.x < self.pos.x + self.size.x and
            point.y > self.pos.y and point.y < self.pos.y + self.size.y;
    }
};

pub const Color = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,

    /// The components are expected to be in the range [0.0, 1.0].
    pub fn rgba(r: f32, g: f32, b: f32, a: f32) Color {
        return Color{
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
        return Color{ .r = r / 255.0, .g = g / 255.0, .b = b / 255.0, .a = 1.0 };
    }
};

// const CGPathDrawingMode = enum(i32) {
//     path_fill,
//     path_eofill,
//     path_stroke,
//     path_fill_stroke,
//     path_eofill_stroke,
// };
