const std = @import("std");
const eadk = @import("eadk.zig");
const resources = @import("resources.zig");
const za = @import("zalgebra");

// TODO: système d'"arena"
// On est sur la même map
// Les ennemis spawn à des endroits aléatoires de la map
// On a une vie limité et peu ou pas de trucs pour regen
// On doit tuer le plus d'ennemis jusqu'à la mort
// Un score à la fin
// TODO: compteur ennemis restants
// TODO: images gardes qui marchent

// TODO: portes
// TODO: les ennemis ne spawn que là où on ne regarde pas
// TODO: les ennemis ne spawnent qu'à l'intérieur du niveau (flood fill boolean array)

const Vec2 = za.Vec2;
const Vec3 = za.Vec3;
const Vec4 = za.Vec4;

pub const APP_NAME = "Loupenstein 3D";

pub export const eadk_app_name: [APP_NAME.len:0]u8 linksection(".rodata.eadk_app_name") = APP_NAME.*;
pub export const eadk_api_level: u32 linksection(".rodata.eadk_api_level") = 0;

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    // afficher ce qui a été rendu pour meilleur déboguage
    eadk.display.swapBuffer();

    var buf: [512]u8 = undefined;
    const ra = @returnAddress() - @ptrToInt(panic);
    const str = std.fmt.bufPrintZ(&buf, "@ 0x{x} (frame {d})", .{ ra, t }) catch unreachable;

    var i: usize = 0;
    while (true) {
        eadk.display.drawString(@ptrCast([:0]const u8, msg), .{ .x = 0, .y = 0 }, false, eadk.rgb(0), eadk.rgb(0xFFFFFF));
        eadk.display.drawString(str, .{ .x = 0, .y = 16 }, false, eadk.rgb(0), eadk.rgb(0xFFFFFF));
        eadk.display.waitForVblank();

        const kbd = eadk.keyboard.scan();
        if (kbd.isDown(.Backspace) or i > 100) {
            break;
        }
        i += 1;
    }
    @breakpoint();
    unreachable;
}

const Camera = struct {
    position: Vec2 = Vec2.new(29, 48),
    yaw: f32 = std.math.degreesToRadians(f32, 270),

    pub fn input(self: *Camera) void {
        const forward = self.getForward().scale(0.15 * DELTA_SCALE);

        const kbd = eadk.keyboard.scan();
        if (kbd.isDown(.Up)) {
            if (worldMap[@floatToInt(usize, self.position.x() + forward.x())][@floatToInt(usize, self.position.y())] == 0) {
                self.position.data[0] += forward.x();
            }
            if (worldMap[@floatToInt(usize, self.position.x())][@floatToInt(usize, self.position.y() + forward.y())] == 0) {
                self.position.data[1] += forward.y();
            }
        }
        if (kbd.isDown(.Down)) {
            if (worldMap[@floatToInt(usize, self.position.x() - forward.x())][@floatToInt(usize, self.position.y())] == 0) {
                self.position.data[0] -= forward.x();
            }
            if (worldMap[@floatToInt(usize, self.position.x())][@floatToInt(usize, self.position.y() - forward.y())] == 0) {
                self.position.data[1] -= forward.y();
            }
        }
        if (kbd.isDown(.Left)) {
            self.yaw -= std.math.degreesToRadians(f32, 4.0 * DELTA_SCALE);
        }
        if (kbd.isDown(.Right)) {
            self.yaw += std.math.degreesToRadians(f32, 4.0 * DELTA_SCALE);
        }
    }

    pub fn getForward(self: Camera) Vec2 {
        return Vec2.new(
            std.math.cos(self.yaw),
            std.math.sin(self.yaw),
        );
    }

    pub fn getRight(self: Camera) Vec2 {
        const forward2 = self.getForward();
        const forward = Vec3.new(forward2.x(), 0, forward2.y());
        const right = forward.cross(Vec3.up()).norm();
        return Vec2.new(right.x(), right.z());
    }
};

const GameState = enum { MainMenu, Playing };

var state = GameState.MainMenu;
var camera = Camera{};
var fps: f32 = 40;
var hp: u8 = 100; // de 0 à 100

const MAP_WIDTH = 57;
const MAP_HEIGHT = 57;

const DELTA_SCALE = 1.0;

pub fn loadMapFromFile(comptime file: []const u8) [MAP_WIDTH][MAP_HEIGHT]u8 {
    comptime {
        @setEvalBranchQuota(10000000);
        var map = std.mem.zeroes([MAP_WIDTH][MAP_HEIGHT]u8);
        var split = std.mem.split(u8, file, "\n");
        var y = 0;
        while (split.next()) |line| {
            if (line.len < 2) break;
            for (line) |char, x| {
                map[x][y] = std.fmt.parseUnsigned(u8, &.{char}, 10) catch unreachable;
            }
            y += 1;
        }
        return map;
    }
}

fn fill(filled: *[MAP_WIDTH][MAP_HEIGHT]bool, x: usize, y: usize) void {
    filled[x][y] = true;
    if (x > 0 and worldMap[x-1][y] == 0 and filled[x-1][y] == false) {
        fill(filled, x-1, y);
    }
    if (x < MAP_WIDTH and worldMap[x+1][y] == 0 and filled[x+1][y] == false) {
        fill(filled, x+1, y);
    }
    if (y > 0 and worldMap[x][y-1] == 0 and filled[x][y-1] == false) {
        fill(filled, x, y-1);
    }
    if (y < MAP_HEIGHT and worldMap[x][y+1] == 0 and filled[x][y+1] == false) {
        fill(filled, x, y+1);
    }
}

//const worldMap = [24][24]u8{
//    .{ 3, 3, 1, 1, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3 },
//    .{ 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3 },
//    .{ 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3 },
//    .{ 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3 },
//    .{ 3, 0, 0, 0, 0, 0, 2, 2, 2, 2, 2, 0, 0, 0, 0, 3, 0, 3, 0, 3, 0, 0, 0, 3 },
//    .{ 3, 0, 0, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3 },
//    .{ 3, 0, 0, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 0, 3, 0, 0, 0, 3, 0, 0, 0, 3 },
//    .{ 3, 0, 0, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3 },
//    .{ 3, 0, 0, 0, 0, 0, 2, 2, 0, 2, 2, 0, 0, 0, 0, 3, 0, 3, 0, 3, 0, 0, 0, 3 },
//    .{ 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3 },
//    .{ 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3 },
//    .{ 3, 0, 0, 0, 0, 0, 0, 0, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3 },
//    .{ 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 3 },
//    .{ 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 3 },
//    .{ 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 3 },
//    .{ 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 3 },
//    .{ 3, 3, 3, 3, 3, 3, 3, 3, 3, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 3 },
//    .{ 3, 3, 0, 3, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 3, 3, 3, 3, 0, 0, 3, 3 },
//    .{ 3, 3, 0, 0, 0, 0, 1, 0, 3, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 3 },
//    .{ 3, 3, 0, 3, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 3 },
//    .{ 3, 3, 0, 3, 3, 3, 3, 3, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3 },
//    .{ 3, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3 },
//    .{ 3, 3, 3, 3, 3, 3, 3, 3, 3, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 3 },
//    .{ 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3 },
//};
const worldMap = loadMapFromFile(@embedFile("level.txt"));
const potentialEnemySpawns = blk: {

    @setEvalBranchQuota(MAP_WIDTH * MAP_HEIGHT * 10);
    var array = std.mem.zeroes([MAP_WIDTH][MAP_HEIGHT]bool);
    fill(&array, 30, 47);

    // var slice: []const u8 = &.{};
    // var y = 0;
    // while (y < MAP_HEIGHT) : (y += 1) {
    //     var string: []const u8 = &.{};
    //     var x = 0;
    //     while (x < MAP_WIDTH) : (x += 1) {
    //         if (array[x][y]) {
    //             string = string ++ "x";
    //         }
    //         else {
    //             string = string ++ ".";
    //         }
    //     }
    //     slice = slice ++ string ++ "\n";
    // }
    // @compileError(slice);
    break :blk array;
};

const Sprite = struct {
    texture: u8,
    x: f32,
    y: f32,
    distance: f32 = undefined,
    lastSeenPlayerPos: Vec2 = Vec2.new(0, 0),

    pub fn sortDsc(_: void, a: Sprite, b: Sprite) bool {
        return a.distance > b.distance;
    }


    pub fn sortAsc(_: void, a: Sprite, b: Sprite) bool {
        return a.distance < b.distance;
    }

    fn propagate(canSee: *[MAP_WIDTH][MAP_HEIGHT]bool, x: u8, y: u8, right: bool, down: bool) void {
        canSee[x][y] = true;
        if (!(worldMap[x+1][y] == 0 or !right) or !(worldMap[x-1][y] == 0 or right) or !(worldMap[x][y+1] == 0 or !down) or !(worldMap[x][y-1] == 0 or down)) {
            return;
        }
        if (right) {
            if (x < MAP_WIDTH and worldMap[x+1][y] == 0 and !canSee[x+1][y]) { // right
                propagate(canSee, x+1, y, right, down);
            }
        } else {
            if (x > 0 and worldMap[x-1][y] == 0 and !canSee[x-1][y]) { // left
                propagate(canSee, x-1, y, right, down);
            }
        }
        if (down) {
            if (y < MAP_HEIGHT and worldMap[x][y+1] == 0 and !canSee[x][y+1]) { // down
                propagate(canSee, x, y+1, right, down);
            }
        } else {
            if (y > 0 and worldMap[x][y-1] == 0 and !canSee[x][y-1]) { // up
                propagate(canSee, x, y-1, right, down);
            }
        }
    }

    pub fn update(self: *Sprite) void {
        // TODO: regarder en direction de l'ennemi et faire un raycast avec les murs
        // TODO: faire la même chose quand l'ennemi tire

        var canSee = std.mem.zeroes([MAP_WIDTH][MAP_HEIGHT]bool);
        const sprX = @floatToInt(u8, self.x);
        const sprY = @floatToInt(u8, self.y);

        propagate(&canSee, sprX, sprY, false, false);
        propagate(&canSee, sprX, sprY, false, true);
        propagate(&canSee, sprX, sprY, true, false);
        propagate(&canSee, sprX, sprY, true, true);

         // To left
        {
            var x = sprX;
            while (x > 0) : (x -= 1) {
                if (worldMap[x][sprY] != 0) {
                    break;
                } else {
                    canSee[x][sprY] = true;
                }
            }
        }

        // To right
        {
            var x = sprX;
            while (x < MAP_WIDTH) : (x += 1) {
                if (worldMap[x][sprY] != 0) {
                    break;
                } else {
                    canSee[x][sprY] = true;
                }
            }
        }

        // To up
        {
            var y = sprY;
            while (y > 0) : (y -= 1) {
                if (worldMap[sprX][y] != 0) {
                    break;
                } else {
                    canSee[sprX][y] = true;
                }
            }
        }

        // To down
        {
            var y = sprY;
            while (y < MAP_HEIGHT) : (y += 1) {
                if (worldMap[sprX][y] != 0) {
                    break;
                } else {
                    canSee[sprX][y] = true;
                }
            }
        }

        if (canSee[@floatToInt(usize, camera.position.x())][@floatToInt(usize, camera.position.y())]) {
            self.lastSeenPlayerPos = camera.position;
        }
        if (self.lastSeenPlayerPos.x() != 0) {
            const direction = self.lastSeenPlayerPos.sub(Vec2.new(self.x, self.y)).norm().scale(0.05 * DELTA_SCALE);
            if (self.lastSeenPlayerPos.sub(Vec2.new(self.x, self.y)).length() > 1.5) {
                if (worldMap[@floatToInt(usize, self.x + direction.x())][@floatToInt(usize, self.y)] == 0) {
                    self.x += direction.x();
                }
                if (worldMap[@floatToInt(usize, self.x)][@floatToInt(usize, self.y + direction.y())] == 0) {
                    self.y += direction.y();
                }
            }
        }
    }
};

// State for a wall to not recompute it twice
const WallState = struct {
    drawStart: u16,
    drawEnd: u16,
    textureId: u8,
    darken: bool,
    texPos: f32,
    texX: u8,
    step: f32,
};

/// 8 ennemis en même temps maximum
var sprites = std.BoundedArray(Sprite, 32).init(0) catch unreachable;
var wall_stripes = std.mem.zeroes([eadk.SCREEN_WIDTH]WallState);

// TODO: passer en 24x24? ne prend que 3.5KiB pour 3 textures
// voire utiliser 32x32 si il reste de la RAM après que le jeu soit fini
const TEXTURE_WIDTH = 16;
const TEXTURE_HEIGHT = 16;
const textures = [_][TEXTURE_HEIGHT][TEXTURE_WIDTH]eadk.EadkColor{
    resources.wall_1,
    resources.wall_2,
    resources.wall_3,
};
const SPR_TEX_WIDTH = 32;
const SPR_TEX_HEIGHT = 32;
const sprite_textures = [_][SPR_TEX_HEIGHT][SPR_TEX_WIDTH]eadk.EadkColor{
    resources.guard,
};
/// For how long does the pistol appears fired
var pistolFiredTime: u16 = 0;

fn draw() void {
    if (state == .MainMenu) {
        // afficher menu
        eadk.display.fillRectangle(
            .{
                .x = 0,
                .y = 0,
                .width = eadk.SCREEN_WIDTH,
                .height = eadk.SCREEN_HEIGHT,
            },
            eadk.rgb(0x000000),
        );
        return;
    }

    if (eadk.display.isUpperBuffer) {
        eadk.display.fillRectangle(.{
            .x = 0,
            .y = 0,
            .width = eadk.SCREEN_WIDTH,
            .height = eadk.SCREEN_HEIGHT / 2,
        }, eadk.rgb(0x383838));
    }
    if (!eadk.display.isUpperBuffer) {
        eadk.display.fillRectangle(.{
            .x = 0,
            .y = eadk.SCREEN_HEIGHT / 2,
            .width = eadk.SCREEN_WIDTH,
            .height = eadk.SCREEN_HEIGHT / 2,
        }, eadk.rgb(0x888888));
    }

    const planeVec = camera.getRight().scale(60.0 / 90.0); // un fov de 90°
    const planeX = planeVec.x();
    const planeY = planeVec.y();
    const dir = camera.getForward();
    const fbRect = eadk.display.getFramebufferRect();

    const w = eadk.SCREEN_WIDTH;
    const h = eadk.SCREEN_HEIGHT;

    var zBuffer: [eadk.SCREEN_WIDTH]f32 = undefined;
    var x: u16 = 0;
    while (x < w) : (x += 1) {
        if (!eadk.display.isUpperBuffer) { // calculer une seule foi
            const cameraX = @intToFloat(f32, 2 * x) / @intToFloat(f32, w) - 1.0;
            const rayDirX = dir.x() + planeX * cameraX;
            const rayDirY = dir.y() + planeY * cameraX;

            var mapX = @floatToInt(i16, camera.position.x());
            var mapY = @floatToInt(i16, camera.position.y());

            const deltaDistX = if (rayDirX == 0) std.math.inf_f32 else @fabs(1.0 / rayDirX);
            const deltaDistY = if (rayDirY == 0) std.math.inf_f32 else @fabs(1.0 / rayDirY);

            var sideDistX: f32 = 0;
            var sideDistY: f32 = 0;

            var stepX: i16 = 0;
            var stepY: i16 = 0;

            var hit = false;
            var side: usize = 0; // Nord-Sud ou Est-Ouest

            if (rayDirX < 0) {
                stepX = -1;
                sideDistX = (camera.position.x() - @floor(camera.position.x())) * deltaDistX;
            } else {
                stepX = 1;
                sideDistX = (@floor(camera.position.x()) + 1.0 - camera.position.x()) * deltaDistX;
            }

            if (rayDirY < 0) {
                stepY = -1;
                sideDistY = (camera.position.y() - @floor(camera.position.y())) * deltaDistY;
            } else {
                stepY = 1;
                sideDistY = (@floor(camera.position.y()) + 1.0 - camera.position.y()) * deltaDistY;
            }

            while (!hit) {
                if (sideDistX < sideDistY) {
                    sideDistX += deltaDistX;
                    mapX += stepX;
                    side = 0;
                } else {
                    sideDistY += deltaDistY;
                    mapY += stepY;
                    side = 1;
                }

                if (mapX >= 0 and mapY >= 0 and mapX < MAP_WIDTH and mapY < MAP_HEIGHT and worldMap[@intCast(u16, mapX)][@intCast(u16, mapY)] > 0) {
                    hit = true;
                } else if (mapX >= MAP_WIDTH or mapY >= MAP_HEIGHT) {
                    hit = true;
                } else if (mapX < 0 or mapY < 0) {
                    hit = true;
                }
            }

            const perpWallDist = if (side == 0)
                sideDistX - deltaDistX
            else
                sideDistY - deltaDistY;
            const lineHeightFloat = @intToFloat(f32, h) / perpWallDist;
            const lineHeight = @floatToInt(u16, std.math.max(0, std.math.min(h, lineHeightFloat)));
            zBuffer[x] = perpWallDist;

            const drawStart = std.math.max(0, h / 2 - lineHeight / 2);
            const drawEnd = std.math.min(
                lineHeight / 2 + h / 2,
                h - 1,
            );

            var textureId = if (mapX >= MAP_WIDTH or mapY >= MAP_HEIGHT or mapX < 0 or mapY < 0) 1 else worldMap[@intCast(u16, mapX)][@intCast(u16, mapY)] -% 1;
            if (textureId == 0xFF) { // it overflowed
                textureId = 1;
            }

            var wallX = if (side == 0)
                camera.position.y() + perpWallDist * rayDirY
            else
                camera.position.x() + perpWallDist * rayDirX;
            wallX -= @floor(wallX);

            var texX = @floatToInt(u8, wallX * @as(f32, TEXTURE_WIDTH));
            if (side == 0 and rayDirX > 0) texX = TEXTURE_WIDTH - texX - 1;
            if (side == 1 and rayDirY < 0) texX = TEXTURE_WIDTH - texX - 1;

            // TODO: changer texPos pour utiliser que des int ? faudrait changer les al gore ithmes
            const step = 1.0 * @as(f32, TEXTURE_HEIGHT) / lineHeightFloat;
            const texPos = (@intToFloat(f32, @as(isize, drawStart) - h / 2) + lineHeightFloat / 2) * step;
            wall_stripes[x] = .{
                .drawStart = drawStart,
                .drawEnd = drawEnd,
                .texX = texX,
                .texPos = texPos,
                .step = step,
                .textureId = textureId,
                .darken = side == 1,
            };
        } else {
            if (t < 5) break;
        }

        var stripe = wall_stripes[x];
        const texture = textures[stripe.textureId];
        var y: u16 = stripe.drawStart;
        const drawEnd = std.math.min(fbRect.y + fbRect.height, stripe.drawEnd);
        while (y < drawEnd) : (y += 1) {
            @setRuntimeSafety(false);
            const texY = @floatToInt(usize, stripe.texPos) % TEXTURE_HEIGHT;
            stripe.texPos += stripe.step;

            var color = texture[texY][stripe.texX];
            if (stripe.darken) {
                color = (color >> 1) & 0x7BEF;
            }
            eadk.display.setPixel(x, y, color);
        }
    }

    // Dessiner les sprites
    for (sprites.slice()) |*sprite| {
        sprite.distance = (camera.position.x() - sprite.x) * (camera.position.x() - sprite.x) + (camera.position.y() - sprite.y) * (camera.position.y() - sprite.y);
    }
    std.sort.sort(Sprite, sprites.slice(), {}, Sprite.sortDsc);
    for (sprites.constSlice()) |sprite| {
        const spriteX = sprite.x - camera.position.x();
        const spriteY = sprite.y - camera.position.y();

        const invDet = 1.0 / (planeX * dir.y() - dir.x() * planeY);
        const transformX = invDet * (dir.y() * spriteX - dir.x() * spriteY);
        const transformY = invDet * (-planeY * spriteX + planeX * spriteY);
        const spriteScreenX = @floatToInt(u16, @intToFloat(f32, w) / 2.0 * (1 + transformX / transformY));
        const spriteHeight = @floatToInt(u16, @fabs(@intToFloat(f32, h) / transformY));

        const drawStartY = std.math.max(0, h / 2 - spriteHeight / 2);
        const drawEndY = std.math.min(h / 2 + spriteHeight / 2, h - 1);

        const spriteWidth = spriteHeight;
        const drawStartX = std.math.max(0, spriteScreenX - spriteWidth / 2);
        const drawEndX = std.math.min(spriteScreenX + spriteWidth / 2, w - 1);

        var stripe = drawStartX;
        while (stripe < drawEndX) : (stripe += 1) {
            const texX = @floatToInt(u16, 256 * @intToFloat(f32, stripe - drawStartX) * SPR_TEX_WIDTH / @intToFloat(f32, spriteWidth)) / 256;
            if (transformY > 0 and stripe > 0 and stripe < w and transformY < zBuffer[stripe]) {
                var y: u16 = drawStartY;
                while (y < drawEndY) : (y += 1) {
                    const d = @as(u32, y) * 256 + @as(u32, spriteHeight) * 128 - @as(u32, h) * 128; // ???? https://lodev.org/cgtutor/raycasting3.html
                    const texY = ((d * SPR_TEX_HEIGHT) / spriteHeight) / 256;
                    const color = sprite_textures[sprite.texture][texY][texX];
                    if (color != 0x0000) {
                        eadk.display.setPixel(stripe, y, color);
                    }
                }
            }
        }
    }

    // On the bottom half of the screen
    if (!eadk.display.isUpperBuffer) {
        const isPistolFired = pistolFiredTime > 36;
        const isPistolReloading = pistolFiredTime > 0 and pistolFiredTime <= 36;
        if (isPistolFired) {
            eadk.display.fillTransparentImage(
                .{ .x = 320 / 2 - (24 * 3 / 2), .y = 240 - (29 * 3 - 10), .width = 24 * 3, .height = 29 * 3 - 10 },
                @ptrCast([*]const u16, &resources.pistol_fire),
                3,
            );
        } else {
            if (isPistolReloading) {
                eadk.display.fillTransparentImage(
                    .{ .x = 320 / 2 - (24 * 3 / 2), .y = 240 - (24 * 3 - 10), .width = 24 * 3, .height = 24 * 3 - 10 },
                    @ptrCast([*]const u16, &resources.pistol),
                    3,
                );
            } else {
                eadk.display.fillTransparentImage(
                    .{ .x = 320 / 2 - (24 * 3 / 2), .y = 240 - (24 * 3), .width = 24 * 3, .height = 24 * 3 },
                    @ptrCast([*]const u16, &resources.pistol),
                    3,
                );
            }       
        }
    }
}

fn rayAabb(origin: Vec2, direction: Vec2, aabb: [2]Vec2) f32 {
    var lo = -std.math.inf_f32;
    var hi =  std.math.inf_f32;

    comptime var i = 0;
    inline while (i < 2) : (i += 1) {
        var dimLo = (aabb[0].data[i] - origin.data[i]) / direction.data[i];
        var dimHi = (aabb[1].data[i] - origin.data[i]) / direction.data[i];

        if (dimLo > dimHi) {
            std.mem.swap(f32, &dimLo, &dimHi);
        }

        if (dimHi < lo or dimLo > hi) {
            return std.math.inf_f32;
        }

        lo = std.math.max(lo, dimLo);
        hi = std.math.min(hi, dimHi);
    }

    return if (lo > hi) std.math.inf_f32 else lo;
}

fn rayAabbIntersection(origin: Vec2, direction: Vec2, aabb: [2]Vec2) bool {
    return !std.math.isInf(rayAabb(origin, direction, aabb));
}

fn spawnEnemy(random: std.rand.Random) void {
    while (true) {
        var x: u8 = random.uintLessThanBiased(u8, worldMap.len);
        var y: u8 = random.uintLessThanBiased(u8, worldMap.len);
        if (worldMap[x][y] == 0 and potentialEnemySpawns[x][y]) {
            const sprite = Sprite{
                .texture = 0,
                .x = @intToFloat(f32, x) + 0.5,
                .y = @intToFloat(f32, y) + 0.5,
            };
            sprites.append(sprite) catch return;
            break;
        }
    }
}

var t: u32 = 0;
fn eadk_main() void {
    var prng = std.rand.DefaultPrng.init(eadk.eadk_random());
    const random = prng.random();

    while (true) : (t += 1) {
        const start = eadk.eadk_timing_millis();

        const kbd = eadk.keyboard.scan();

        if (state == .Playing) {
            camera.input();
            if (sprites.slice().len == 0) {
                var idx: usize = 0;
                while (idx < 32) : (idx += 1) {
                    spawnEnemy(random);
                }
            }
            for (sprites.slice()) |*sprite| {
                sprite.update();
            }

            // Dessiner le haut
            eadk.display.isUpperBuffer = true;
            eadk.display.clearBuffer();
            draw();
            eadk.display.swapBuffer();

            // Puis, dessiner le bas
            eadk.display.isUpperBuffer = false;
            eadk.display.clearBuffer();
            draw();
            eadk.display.swapBuffer();
        } else {
            eadk.eadk_display_push_rect_uniform(.{ .x = 0, .y = 0, .width = eadk.SCREEN_WIDTH, .height = eadk.SCREEN_HEIGHT }, eadk.rgb(0x000000));
        }

        var buf: [100]u8 = undefined;
        if (state == .Playing) {
            const msg = std.fmt.bufPrintZ(&buf, "{d}fps", .{@floatToInt(u16, fps)}) catch unreachable;
            eadk.display.drawString(msg, .{ .x = 0, .y = 0 }, false, eadk.rgb(0xFFFFFF), eadk.rgb(0x000000));
            eadk.display.drawString(
                std.fmt.bufPrintZ(&buf, "PV: {d}/100", .{hp}) catch unreachable,
                .{ .x = 0, .y = 12 },
                false,
                eadk.rgb(0xFFFFFF),
                eadk.rgb(0x000000),
            );
            eadk.display.drawString(
                std.fmt.bufPrintZ(&buf, "{d},{d}", .{ @floatToInt(i8, camera.position.x()), @floatToInt(i8, camera.position.y()) }) catch unreachable,
                .{ .x = 0, .y = 24 },
                false,
                eadk.rgb(0xFFFFFF),
                eadk.rgb(0x000000),
            );
        }

        if (state == .MainMenu) {
            eadk.display.drawString("Loupstein", .{ .x = 0, .y = 0 }, true, eadk.rgb(0xFFFFFF), eadk.rgb(0x000000));
            eadk.display.drawString("(c) Zen1th", .{ .x = 0, .y = 20 }, false, eadk.rgb(0x888888), eadk.rgb(0x000000));
            eadk.display.drawString("> Press EXE to play", .{ .x = 0, .y = 220 }, true, eadk.rgb(0xFFFFFF), eadk.rgb(0x00000));
            if (kbd.isDown(.Exe)) {
                state = .Playing;
                t = 0;
            }
        } else {
            pistolFiredTime -|= 1;
            if (kbd.isDown(.OK) and pistolFiredTime == 0) {
                pistolFiredTime = 40; // 1.0 s
                std.sort.sort(Sprite, sprites.slice(), {}, Sprite.sortAsc);
                for (sprites.constSlice()) |sprite, i| {
                    const aabb: [2]Vec2 = .{
                        Vec2.new(sprite.x - 0.5, sprite.y - 0.5),
                        Vec2.new(sprite.x + 0.5, sprite.y + 0.5),
                    };
                    if (rayAabbIntersection(camera.position, camera.getForward(), aabb)) {
                        _ = sprites.swapRemove(i);
                        break;
                    }
                }
            }
        }
        if (kbd.isDown(.Back)) {
            break;
        }

        const end = eadk.eadk_timing_millis();
        const frameFps = 1.0 / (@intToFloat(f32, @intCast(u32, end - start)) / 1000);
        fps = fps * 0.9 + frameFps * 0.1; // faire interpolation linéaire vers la valeur fps
        eadk.display.waitForVblank();
    }
}

export fn main() void {
    eadk_main();
}

comptime {
    _ = @import("c.zig");
}
