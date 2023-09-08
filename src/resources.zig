const std = @import("std");
const bmp = @import("bmp.zig");
const eadk = @import("eadk.zig");
const EadkColor = eadk.EadkColor;

pub const wall_1 = makeImageArray(@embedFile("assets/wall_1.bmp"));
pub const wall_2 = makeImageArray(@embedFile("assets/wall_2.bmp"));
pub const wall_3 = makeImageArray(@embedFile("assets/wall_3.bmp"));
pub const wall_4 = makeImageArray(@embedFile("assets/wall_4.bmp"));
pub const wall_5 = makeImageArray(@embedFile("assets/wall_5.bmp"));
pub const pistol = makeImageArray(@embedFile("assets/pistol.bmp"));
pub const pistol_fire = makeImageArray(@embedFile("assets/pistol_fire.bmp"));
pub const guard = makeImageArray(@embedFile("assets/guard_1.bmp"));
pub const guard_run_1 = makeImageArray(@embedFile("assets/guard_run_1.bmp"));
pub const guard_run_2 = makeImageArray(@embedFile("assets/guard_run_2.bmp"));
pub const guard_run_3 = makeImageArray(@embedFile("assets/guard_run_3.bmp"));
pub const guard_run_4 = makeImageArray(@embedFile("assets/guard_run_4.bmp"));
pub const guard_kill_1 = makeImageArray(@embedFile("assets/guard_kill_1.bmp"));
pub const guard_kill_2 = makeImageArray(@embedFile("assets/guard_kill_2.bmp"));
pub const guard_kill_3 = makeImageArray(@embedFile("assets/guard_kill_3.bmp"));
pub const guard_kill_4 = makeImageArray(@embedFile("assets/guard_kill_4.bmp"));
pub const guard_shoot = makeImageArray(@embedFile("assets/guard_shoot.bmp"));
pub const guard_shooting = makeImageArray(@embedFile("assets/guard_shooting.bmp"));

pub const skeleton = makeImageArray(@embedFile("assets/skeleton.bmp"));
pub const guard_corpse = makeImageArray(@embedFile("assets/guard_corpse.bmp"));

pub const player_0 = makeImageArray(@embedFile("assets/player_0.bmp"));
pub const player_1 = makeImageArray(@embedFile("assets/player_1.bmp"));
pub const player_2 = makeImageArray(@embedFile("assets/player_2.bmp"));
pub const player_3 = makeImageArray(@embedFile("assets/player_3.bmp"));
pub const player_4 = makeImageArray(@embedFile("assets/player_4.bmp"));
pub const player_5 = makeImageArray(@embedFile("assets/player_5.bmp"));
pub const player_6 = makeImageArray(@embedFile("assets/player_6.bmp"));
pub const player_7 = makeImageArray(@embedFile("assets/player_7.bmp"));

fn MakeImageArrayReturn(comptime bmpFile: []const u8) type {
    @setEvalBranchQuota(100000);
    const image = bmp.comptimeRead(bmpFile) catch unreachable;
    return [image.height][image.width]EadkColor;
}

fn makeImageArray(comptime bmpFile: []const u8) MakeImageArrayReturn(bmpFile) {
    @setEvalBranchQuota(100000);
    const image = bmp.comptimeRead(bmpFile) catch unreachable;
    var pixels: [image.height][image.width]EadkColor = undefined;
    var y: usize = 0;
    while (y < image.height) : (y += 1) {
        var x: usize = 0;
        while (x < image.width) : (x += 1) {
            // zig fmt: off
            const rgb: u24 =
                  @as(u24, image.data[y * image.width * 3 + x * 3 + 0]) << 0  // blue
                | @as(u24, image.data[y * image.width * 3 + x * 3 + 1]) << 8  // green
                | @as(u24, image.data[y * image.width * 3 + x * 3 + 2]) << 16 // red
            ;
            // zig fmt: on
            pixels[y][x] = eadk.rgb(rgb);
        }
    }

    return pixels;
}
