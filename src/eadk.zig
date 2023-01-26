const std = @import("std");

pub extern fn eadk_random() u32;
pub extern fn eadk_timing_millis() u64;
extern fn eadk_display_wait_for_vblank() void;

pub extern var eadk_external_data: [*]const u8;
pub extern var eadk_external_data_size: usize;

/// RGB565 color
pub const EadkColor = u16;
// XXX: extern struct doesn't work on stage2?
pub const EadkRect = packed struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,
};

pub const EadkPoint = packed struct {
    x: u16,
    y: u16,
};

pub const SCREEN_WIDTH = 320;
pub const SCREEN_HEIGHT = 240;
pub const SCENE_WIDTH = 320;
pub const SCENE_HEIGHT = 240 - 32;
pub const screen_rectangle = EadkRect{
    .x = 0,
    .y = 0,
    .width = SCREEN_WIDTH,
    .height = SCREEN_HEIGHT,
};

pub fn rgb(hex: u24) EadkColor {
    const red = (hex >> 16) & 0xFF;
    const green = (hex >> 8) & 0xFF;
    const blue = (hex) & 0xFF;

    const result = @intCast(u16, (red >> 3) << 11 | // 5 bits of red
        (green >> 2) << 5 | // 6 bits of green
        (blue >> 3)); // 5 bits of blue
    if (result == 0x0000 and hex != 0x000000) {
        // not true black shouldn't result in true black
        return 1 << 11 | 1 << 5 | 1;
    }
    return result;
}

extern fn eadk_display_pull_rect(rect: EadkRect, pixels: [*]const EadkColor) void;
extern fn eadk_display_push_rect(rect: EadkRect, pixels: [*]const EadkColor) void;
pub extern fn eadk_display_push_rect_uniform(rect: EadkRect, color: EadkColor) void;
extern fn eadk_display_draw_string(char: [*:0]const u8, point: EadkPoint, large_font: bool, text_color: EadkColor, background_color: EadkColor) void;
pub const display = struct {
    // in total, 97 100 bytes free for framebuffer
    // this uses 76 800 bytes
    pub const FRAMEBUFFER_WIDTH = 320;
    pub const FRAMEBUFFER_HEIGHT = 120;
    var framebuffer: [FRAMEBUFFER_WIDTH * FRAMEBUFFER_HEIGHT]EadkColor = undefined;
    pub var isUpperBuffer = false;

    // Pour dessiner, deux buffers sont utilisés, un pour le haut (320x140)
    // et un pour le bas (320x100). Cela nécessite de dessiner la scène 2 fois
    // ce qui n'est pas grave car le gain de performance réalisé par l'ajout d'un
    // framebuffer surpase largement cette pénalité.

    pub fn waitForVblank() void {
        eadk_display_wait_for_vblank();
    }

    pub fn getFramebufferRect() EadkRect {
        return .{
            .x = 0,
            .y = if (isUpperBuffer) 0 else FRAMEBUFFER_HEIGHT,
            .width = FRAMEBUFFER_WIDTH,
            .height = FRAMEBUFFER_HEIGHT,
        };
    }

    pub fn swapBuffer() void {
        if (isUpperBuffer) {
            fillImage(.{ .x = 0, .y = 0, .width = FRAMEBUFFER_WIDTH, .height = FRAMEBUFFER_HEIGHT }, &framebuffer);
        } else {
            fillImage(.{ .x = 0, .y = FRAMEBUFFER_HEIGHT, .width = FRAMEBUFFER_WIDTH, .height = SCREEN_HEIGHT - FRAMEBUFFER_HEIGHT }, &framebuffer);
        }
    }

    pub fn clearBuffer() void {
        std.mem.set(EadkColor, &framebuffer, 0);
    }

    pub fn fillImage(rect: EadkRect, pixels: [*]const EadkColor) void {
        eadk_display_push_rect(rect, pixels);
    }

    /// This will also scale the image to 2x size
    pub fn fillTransparentImage(rect: EadkRect, pixels: [*]const EadkColor, scale: u16) void {
        var y: u16 = 0;
        while (y < rect.height / scale) : (y += 1) {
            var x: u16 = 0;
            while (x < rect.width / scale) : (x += 1) {
                const color = pixels[y * rect.width / scale + x];
                if (color != 0x0000) {
                    //setPixel(rect.x + x, rect.y + y, color);
                    fillRectangle(.{ .x = rect.x + x * scale, .y = rect.y + y * scale, .width = scale, .height = scale }, color);
                }
            }
        }
    }

    pub fn fillRectangle(rect: EadkRect, color: EadkColor) void {
        //eadk_display_push_rect_uniform(rect, color);
        var y: u16 = rect.y;
        while (y < rect.y + rect.height) : (y += 1) {
            drawHorizontalLine(rect.x, rect.x + rect.width, y, color);
        }
    }

    pub inline fn setPixel(x: u16, y: u16, color: EadkColor) void {
        if (isUpperBuffer and x < FRAMEBUFFER_WIDTH and y < FRAMEBUFFER_HEIGHT) {
            framebuffer[y * FRAMEBUFFER_WIDTH + x] = color;
        } else if (!isUpperBuffer and x < FRAMEBUFFER_WIDTH and y >= FRAMEBUFFER_HEIGHT) {
            framebuffer[(y - FRAMEBUFFER_HEIGHT) * FRAMEBUFFER_WIDTH + x] = color;
        }
    }

    pub fn drawHorizontalLine(x1: u16, x2: u16, y: u16, color: EadkColor) void {
        const nullable_ptr = if (isUpperBuffer and y < FRAMEBUFFER_HEIGHT)
            @ptrCast([*]EadkColor, &framebuffer[y * FRAMEBUFFER_WIDTH])
        else if (!isUpperBuffer and y >= FRAMEBUFFER_HEIGHT)
            @ptrCast([*]EadkColor, &framebuffer[(y - FRAMEBUFFER_HEIGHT) * FRAMEBUFFER_WIDTH])
        else
            null;
        if (nullable_ptr) |ptr| {
            std.mem.set(EadkColor, ptr[x1..x2], color);
        }
    }

    pub fn drawVerticalLine(x: u16, y1: u16, y2: u16, color: EadkColor) void {
        var y: u16 = y1;
        while (y < y2) : (y += 1) {
            setPixel(x, y, color);
        }
    }

    pub fn drawLine(in_x1: u16, in_y1: u16, in_x2: u16, in_y2: u16, color: EadkColor) void {
        @setRuntimeSafety(false);
        var x1 = in_x1;
        var x2 = in_x2;
        var y1 = in_y1;
        var y2 = in_y2;
        var steep = false;
        if (std.math.absInt(@intCast(i16, x1) - @intCast(i16, x2)) catch unreachable <
            std.math.absInt(@intCast(i16, y1) - @intCast(i16, y2)) catch unreachable)
        {
            // toujours plus horizontal que vertical (pente réduite)
            std.mem.swap(u16, &x1, &y1);
            std.mem.swap(u16, &x2, &y2);
            steep = true;
        }
        if (x1 > x2) { // toujours de gauche à droite
            std.mem.swap(u16, &x1, &x2);
            std.mem.swap(u16, &y1, &y2);
        }

        var x: u16 = x1;
        const length = @intToFloat(f32, x2 - x1);
        const height = @intToFloat(f32, y2) - @intToFloat(f32, y1);
        while (x <= x2) : (x += 1) {
            const t = @intToFloat(f32, x - x1) / length;
            const y = @intCast(u16, @intCast(i16, y1) + @floatToInt(i16, height * t));
            if (steep) {
                setPixel(y, x, color);
            } else {
                setPixel(x, y, color);
            }
        }
    }

    fn clampX(coord: f32) u16 {
        @setRuntimeSafety(false);
        return @floatToInt(u16, std.math.clamp(coord, 0, SCREEN_WIDTH));
    }

    fn clampY(coord: f32) u16 {
        @setRuntimeSafety(false);
        return @floatToInt(u16, std.math.clamp(coord, 0, SCREEN_HEIGHT));
    }

    pub fn drawTriangle(x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32, color: EadkColor) void {
        drawLine(clampX(x1), clampY(y1), clampX(x2), clampY(y2), color); // de 1 à 2
        drawLine(clampX(x2), clampY(y2), clampX(x3), clampY(y3), color); // de 2 à 3
        drawLine(clampX(x3), clampY(y3), clampX(x1), clampY(y1), color); // de 3 à 1
    }

    pub fn drawString(char: [*:0]const u8, point: EadkPoint, large_font: bool, text_color: EadkColor, background_color: EadkColor) void {
        eadk_display_draw_string(char, point, large_font, text_color, background_color);
    }
};

extern fn eadk_keyboard_scan() u64;
pub const keyboard = struct {
    pub const Key = enum(u8) {
        Left,
        Up,
        Down,
        Right,
        OK,
        Back,
        Home,
        OnOff = 8,
        Shift = 12,
        Alpha,
        XNT,
        Var,
        Toolbox,
        Backspace,
        Exp,
        Ln,
        Log,
        Imaginary,
        Comma,
        Power,
        Sine,
        Cosine,
        Tangent,
        Pi,
        Sqrt,
        Square,
        Seven,
        Eight,
        Nine,
        LeftParenthesis,
        RightParenthesis,
        Four = 35,
        Five,
        Six,
        Multiplication,
        Division,
        One = 42,
        Two,
        Three,
        Plus,
        Minus,
        Zero = 48,
        Dot,
        EE,
        Ans,
        Exe,
    };

    pub const KeyboardState = struct {
        bitfield: u64,

        pub fn isDown(self: KeyboardState, key: Key) bool {
            const shift = @intCast(u6, @enumToInt(key));
            return (self.bitfield >> shift) & 1 == 1;
        }
    };

    pub fn scan() KeyboardState {
        return KeyboardState{ .bitfield = eadk_keyboard_scan() };
    }
};
