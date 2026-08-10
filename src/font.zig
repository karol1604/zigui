const std = @import("std");
const draw = @import("draw.zig");
const cg = @import("coregraphics");

pub const Glyph = struct {
    uv_min: [2]f32,
    uv_max: [2]f32,
    advance: f32,
};

pub const Atlas = struct {
    width: usize,
    height: usize,
    pixels: []u8,
    bytes_per_row: usize,
};

pub const Font = struct {
    ct_font: cg.CTFontRef,
    glyphs: [95]?Glyph,
    ascent: f32,
    descent: f32,
    leading: f32,
    cell_width: f32,
    cell_height: f32,
    pen_x_in_cell: f32,
    baseline_in_cell: f32,
    atlas: Atlas,
};

pub const FontManager = struct {
    alloc: std.mem.Allocator,
    fonts: std.ArrayList(Font),

    pub fn init(alloc: std.mem.Allocator) FontManager {
        return .{
            .alloc = alloc,
            .fonts = .empty,
        };
    }

    pub fn deinit(self: *FontManager) void {
        for (self.fonts.items) |font| {
            cg.CFRelease(font.ct_font);
            self.alloc.free(font.atlas.pixels);
        }
        self.fonts.deinit(self.alloc);
    }

    fn cfString(s: []const u8) !cg.CFStringRef {
        return cg.CFStringCreateWithBytes(
            null,
            s.ptr,
            @intCast(s.len),
            cg.kCFStringEncodingUTF8,
            0,
        ) orelse error.CreateCFStringFailed;
    }

    pub fn createFont(self: *FontManager, font_name: []const u8, font_size: usize) !draw.FontHandle {
        var font: Font = undefined;
        const cf_font_name = try cfString(font_name);
        defer cg.CFRelease(cf_font_name);

        const ct_font = cg.CTFontCreateWithName(
            cf_font_name,
            @floatFromInt(font_size),
            null,
        );
        errdefer cg.CFRelease(ct_font);
        font.ct_font = ct_font;

        const ascent: f32 = @floatCast(cg.CTFontGetAscent(ct_font));
        const descent: f32 = @floatCast(cg.CTFontGetDescent(ct_font));
        const leading: f32 = @floatCast(cg.CTFontGetLeading(ct_font));
        font.ascent = ascent;
        font.descent = descent;
        font.leading = leading;

        const padding: f32 = 8;
        font.pen_x_in_cell = padding;
        font.baseline_in_cell = padding + font.ascent;

        // TODO: get actual bounding boxes from font
        const cell_width = 64;
        const cell_height = 64;
        const columns = 16;
        const rows = 8;
        font.cell_width = cell_width;
        font.cell_height = cell_height;

        const atlas_width = cell_width * columns;
        const atlas_height = cell_height * rows;

        const coverage = try self.alloc.alloc(u8, atlas_width * atlas_height);
        defer self.alloc.free(coverage);
        @memset(coverage, 0);

        const color_space = cg.CGColorSpaceCreateDeviceGray() orelse
            return error.CreateColorSpaceFailed;
        defer cg.CGColorSpaceRelease(color_space);

        const context = cg.CGBitmapContextCreate(
            coverage.ptr,
            atlas_width,
            atlas_height,
            8,
            atlas_width,
            color_space,
            @bitCast(@as(c_int, cg.kCGImageAlphaNone)),
        ) orelse return error.CreateBitmapContextFailed;
        defer cg.CGContextRelease(context);

        cg.CGContextSetGrayFillColor(context, 1, 1);

        // printable ascii for now
        var glyphs: [95]?Glyph = [_]?Glyph{null} ** 95;
        for (32..127) |c| {
            const char: cg.UniChar = @intCast(c);
            var glyph: cg.CGGlyph = 0;
            const found = cg.CTFontGetGlyphsForCharacters(
                ct_font,
                &char,
                &glyph,
                1,
            );
            if (!found) {
                std.log.warn("Glyph not found for character: {any}", .{c});
                continue;
            }

            var advance: cg.CGSize = undefined;
            _ = cg.CTFontGetAdvancesForGlyphs(
                ct_font,
                cg.kCTFontOrientationHorizontal,
                &glyph,
                &advance,
                1,
            );

            const advance_x: f32 = @floatCast(advance.width);

            const glyph_idx = c - 32;
            const column = glyph_idx % columns;
            const row = glyph_idx / columns;

            const cell_x = column * cell_width;
            const cell_y = row * cell_height;

            // NOTE: flip the y-axis for atlas
            const texture_row = rows - 1 - row;
            const texture_cell_y = texture_row * cell_height;

            const uv_min = [2]f32{
                @as(f32, @floatFromInt(cell_x)) /
                    @as(f32, @floatFromInt(atlas_width)),

                @as(f32, @floatFromInt(texture_cell_y)) /
                    @as(f32, @floatFromInt(atlas_height)),
            };

            const uv_max = [2]f32{
                @as(f32, @floatFromInt(cell_x + cell_width)) /
                    @as(f32, @floatFromInt(atlas_width)),

                @as(f32, @floatFromInt(texture_cell_y + cell_height)) /
                    @as(f32, @floatFromInt(atlas_height)),
            };
            glyphs[glyph_idx] = Glyph{
                .uv_min = uv_min,
                .uv_max = uv_max,
                .advance = advance_x,
            };

            const glyph_position = cg.CGPoint{
                .x = @as(f64, @floatFromInt(cell_x)) +
                    font.pen_x_in_cell,
                .y = @as(f64, @floatFromInt(cell_y + cell_height)) -
                    font.baseline_in_cell,
            };

            // NOTE: this is so glyphs do not bleed into each other in the atlas texture
            cg.CGContextSaveGState(context);
            cg.CGContextClipToRect(context, .{
                .origin = .{
                    .x = @floatFromInt(cell_x),
                    .y = @floatFromInt(cell_y),
                },
                .size = .{
                    .width = @floatFromInt(cell_width),
                    .height = @floatFromInt(cell_height),
                },
            });

            cg.CTFontDrawGlyphs(
                ct_font,
                &glyph,
                &glyph_position,
                1,
                context,
            );

            cg.CGContextRestoreGState(context);
        }

        font.glyphs = glyphs;

        const rgba = try self.alloc.alloc(u8, atlas_width * atlas_height * 4);
        errdefer self.alloc.free(rgba);

        for (coverage, 0..) |alpha, i| {
            rgba[i * 4 + 0] = 255;
            rgba[i * 4 + 1] = 255;
            rgba[i * 4 + 2] = 255;
            rgba[i * 4 + 3] = alpha;
        }

        font.atlas = Atlas{
            .width = atlas_width,
            .height = atlas_height,
            .pixels = rgba,
            .bytes_per_row = atlas_width * 4,
        };

        const font_idx = self.fonts.items.len;
        try self.fonts.append(self.alloc, font);

        return @intCast(font_idx);
    }

    pub fn getFont(self: *const FontManager, font_handle: draw.FontHandle) !*const Font {
        if (font_handle >= self.fonts.items.len) {
            return error.InvalidFontHandle;
        }
        return &self.fonts.items[font_handle];
    }
};
