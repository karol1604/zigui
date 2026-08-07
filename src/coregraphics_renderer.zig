pub const cg = @import("coregraphics");
const std = @import("std");
const draw = @import("draw.zig");

const Rect = draw.Rect;
const RectCommand = draw.RectCommand;
const EllipseCommand = draw.EllipseCommand;
const LineCommand = draw.LineCommand;
const TextCommand = draw.TextCommand;
const DrawList = draw.DrawList;

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

pub const CGRenderer = struct {
    pub fn render(_: *CGRenderer, context: cg.CGContextRef, draw_list: *const DrawList) !void {
        cg.CGContextSaveGState(context);
        defer cg.CGContextRestoreGState(context);

        for (draw_list.commands.items) |command| {
            switch (command) {
                .rect => |rect| drawRect(context, rect),
                .ellipse => |ellipse| drawEllipse(context, ellipse),
                .line => |line| drawLine(context, line),
                .text => |text| drawString(context, text.text),
            }
        }
    }

    fn drawString(context: cg.CGContextRef, _: []const u8) void {
        cg.CGContextSaveGState(context);
        defer cg.CGContextRestoreGState(context);

        const font_ref = cg.CTFontCreateWithName(cg.CFSTR("Helvetica"), 36, null);
        const keys = &[_]cg.CFStringRef{
            cg.kCTFontAttributeName,
        };
        const vals = &[_]cg.CFTypeRef{
            font_ref,
        };
        const attrs = cg.CFDictionaryCreate(
            null,
            @ptrCast(@constCast(keys)),
            @ptrCast(@constCast(vals)),
            1,
            &cg.kCFTypeDictionaryKeyCallBacks,
            &cg.kCFTypeDictionaryValueCallBacks,
        );

        const cf_str = cg.CFAttributedStringCreate(null, cg.CFSTR("hello"), attrs);
        const line = cg.CTLineCreateWithAttributedString(cf_str);

        cg.CGContextSetTextMatrix(
            context,
            cg.CGAffineTransformMakeScale(1, -1),
        );
        cg.CGContextSetTextPosition(context, 10, 30);
        cg.CTLineDraw(line, context);

        cg.CFRelease(line);
        cg.CFRelease(cf_str);
        cg.CFRelease(attrs);
        cg.CFRelease(font_ref);
    }

    fn drawLine(context: cg.CGContextRef, line_command: LineCommand) void {
        const start = line_command.start;
        const end = line_command.end;
        const stroke = line_command.stroke;

        cg.CGContextBeginPath(context);
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

    fn toCGRect(rect: Rect) cg.CGRect {
        return .{
            .origin = .{ .x = rect.pos.x, .y = rect.pos.y },
            .size = .{ .width = rect.size.x, .height = rect.size.y },
        };
    }
};
