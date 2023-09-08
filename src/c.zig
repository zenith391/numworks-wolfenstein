const std = @import("std");

fn generateConstantTable(from: f32, to: f32, comptime precision: usize, func: *const fn (f32) f32) [precision]f32 {
    var table: [precision]f32 = undefined;
    @setEvalBranchQuota(precision * 10);

    var idx: usize = 0;
    var x: f32 = from;
    const increment = (to - from) / @as(f32, @floatFromInt(table.len));
    while (x < to) : (x += increment) {
        table[idx] = func(x);
        idx += 1;
    }

    return table;
}

const COS_PRECISION = 100;
const cos_table = generateConstantTable(0, 2 * std.math.pi, COS_PRECISION, zigCos);
fn zigCos(x: f32) f32 {
    return std.math.cos(x);
}

fn lerp(a: f32, b: f32, t: f32) f32 {
    return a * (1 - t) + b * t;
}

export fn cosf(theta: f32) f32 {
    const x = @mod(theta, 2 * std.math.pi);
    const range = 2.0 * std.math.pi - 0.0;
    const idx = @as(usize, @intFromFloat(x / range * (COS_PRECISION - 1)));
    if (idx != COS_PRECISION - 1) {
        const t = x / range * COS_PRECISION - @floor(x / range * COS_PRECISION);
        return lerp(cos_table[idx], cos_table[idx + 1], t);
    }
    return cos_table[idx];
}

export fn sinf(theta: f32) f32 {
    return cosf(theta - std.math.pi / 2.0);
}

const tan_table = generateConstantTable(0, std.math.pi, COS_PRECISION, zigTan);
fn zigTan(x: f32) f32 {
    return std.math.tan(x);
}
export fn tanf(theta: f32) f32 {
    const x = @mod(theta, std.math.pi);
    const range = 1.0 * std.math.pi - 0.0;
    const idx = @as(usize, @intFromFloat(x / range * (COS_PRECISION - 1)));
    if (idx != COS_PRECISION - 1) {
        const t = x / range * COS_PRECISION - @floor(x / range * COS_PRECISION);
        return lerp(tan_table[idx], tan_table[idx + 1], t);
    }
    return tan_table[idx];
}

export fn fmodf(x: f32, y: f32) f32 {
    return x - @floor(x / y) * y;
}

// volatile is used to prevent LLVM optimizations
export fn memset(dest: ?[*]volatile u8, c: u8, len: usize) ?[*]volatile u8 {
    @setRuntimeSafety(false);

    if (len != 0) {
        var d = dest.?;
        var n = len;
        while (true) {
            d[0] = c;
            n -= 1;
            if (n == 0) break;
            d += 1;
        }
    }

    return dest;
}

fn memcpy(noalias dest: ?[*]volatile u8, noalias src: ?[*]const u8, len: usize) ?[*]volatile u8 {
    @setRuntimeSafety(false);

    if (len != 0) {
        var d = dest.?;
        var s = src.?;
        var n = len;
        while (true) {
            d[0] = s[0];
            n -= 1;
            if (n == 0) break;
            d += 1;
            s += 1;
        }
    }

    return dest;
}

fn memmove(dest: ?[*]volatile u8, src: ?[*]const u8, n: usize) ?[*]volatile u8 {
    @setRuntimeSafety(false);

    if (@intFromPtr(dest) < @intFromPtr(src)) {
        var index: usize = 0;
        while (index != n) : (index += 1) {
            dest.?[index] = src.?[index];
        }
    } else {
        var index = n;
        while (index != 0) {
            index -= 1;
            dest.?[index] = src.?[index];
        }
    }

    return dest;
}

export fn __aeabi_memcpy(dest: [*]u8, src: [*]u8, n: usize) callconv(.AAPCS) void {
    _ = memcpy(dest, src, n);
}
export fn __aeabi_memcpy4(dest: [*]u8, src: [*]u8, n: usize) callconv(.AAPCS) void {
    _ = memcpy(dest, src, n);
}
export fn __aeabi_memcpy8(dest: [*]u8, src: [*]u8, n: usize) callconv(.AAPCS) void {
    _ = memcpy(dest, src, n);
}

export fn __aeabi_memset(dest: [*c]volatile u8, len: usize, c: c_int) [*c]volatile u8 {
    if (len == 0) {
        return dest;
    }
    for (dest[0..len]) |*b| b.* = @as(u8, @intCast(c));
    return dest;
}
export fn __aeabi_memset4(dest: [*c]volatile u8, len: usize, c: c_int) [*c]volatile u8 {
    if (len == 0) {
        return dest;
    }
    for (dest[0..len]) |*b| b.* = @as(u8, @intCast(c));
    return dest;
}
export fn __aeabi_memset8(dest: [*c]volatile u8, len: usize, c: c_int) [*c]volatile u8 {
    if (len == 0) {
        return dest;
    }
    for (dest[0..len]) |*b| b.* = @as(u8, @intCast(c));
    return dest;
}

export fn __aeabi_memclr(dest: [*c]volatile u8, len: usize) [*c]volatile u8 {
    return __aeabi_memset(dest, len, 0);
}
export fn __aeabi_memclr4(str: [*]volatile u8, n: usize) callconv(.AAPCS) [*c]volatile u8 {
    _ = @call(.always_inline, __aeabi_memset, .{ str, n, 0 });
    return str;
}

export fn __aeabi_memmove(dest: [*]u8, src: [*]u8, n: usize) callconv(.AAPCS) void {
    _ = memmove(dest, src, n);
}
export fn __aeabi_memmove4(dest: [*]u8, src: [*]u8, n: usize) callconv(.AAPCS) void {
    _ = memmove(dest, src, n);
}
export fn __aeabi_memmove8(dest: [*]u8, src: [*]u8, n: usize) callconv(.AAPCS) void {
    _ = memmove(dest, src, n);
}
