const std = @import("std");
const eadk = @import("eadk.zig");
const resources = @import("resources.zig");
const za = @import("zalgebra");

// Système d'"arena"
// On est sur la même map
// Les ennemis spawn à des endroits aléatoires de la map
// On a une vie limité et peu ou pas de trucs pour regen
// On doit tuer le plus d'ennemis jusqu'à la mort
// Un score à la fin
// TODO: potions
// TODO: plusieurs niveaux
// TODO: compteur ennemis restants

// TODO: portes
// TODO: les ennemis ne spawn que là où on ne regarde pas
// TODO: afficher animation enemi qui meurt + cadavre (nettoyé à prochaine vague)
// TODO: quand l'arme est tirée, comparer la distance à l'ennemi avec le zBuffer, si supérieur alors on a touché un mur

const Vec2 = za.Vec2;
const Vec3 = za.Vec3;
const Vec4 = za.Vec4;

pub const APP_NAME = "NazKiller";

pub export const eadk_app_name: [APP_NAME.len:0]u8 linksection(".rodata.eadk_app_name") = APP_NAME.*;
pub export const eadk_api_level: u32 linksection(".rodata.eadk_api_level") = 0;

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    // afficher ce qui a été rendu pour meilleur déboguage
    eadk.display.swapBuffer();

    var buf: [512]u8 = undefined;
    const ra = @returnAddress() - @intFromPtr(&panic);
    const str = std.fmt.bufPrintZ(&buf, "@ 0x{x} (frame {d})", .{ ra, t }) catch unreachable;

    var i: usize = 0;
    while (true) {
        eadk.display.drawString(@as([:0]const u8, @ptrCast(msg)), .{ .x = 0, .y = 0 }, false, eadk.rgb(0), eadk.rgb(0xFFFFFF));
        eadk.display.drawString(str, .{ .x = 0, .y = 16 }, false, eadk.rgb(0), eadk.rgb(0xFFFFFF));
        eadk.display.waitForVblank();

        const kbd = eadk.keyboard.scan();
        if (kbd.isDown(.Backspace) or i > 200) {
            break;
        }
        i += 1;
    }
    @breakpoint();
    unreachable;
}

const Camera = struct {
    position: Vec2 = Vec2.new(35, 62),
    yaw: f32 = std.math.degreesToRadians(f32, 270),
    pitch: i32 = 0,
    walkUp: bool = true,

    pub fn input(self: *Camera) void {
        const forward = self.getForward().scale(0.15 * DELTA_SCALE);

        const kbd = eadk.keyboard.scan();
        const walking = kbd.isDown(.Up) or kbd.isDown(.Down);
        if (!walking) {
            self.walkUp = true;
            self.pitch = 0;
        }
        if (kbd.isDown(.Up)) {
            if (worldMap[@as(usize, @intFromFloat(self.position.x() + forward.x()))][@as(usize, @intFromFloat(self.position.y()))] == 0) {
                self.position.data[0] += forward.x();
            }
            if (worldMap[@as(usize, @intFromFloat(self.position.x()))][@as(usize, @intFromFloat(self.position.y() + forward.y()))] == 0) {
                self.position.data[1] += forward.y();
            }
        }
        if (kbd.isDown(.Down)) {
            if (worldMap[@as(usize, @intFromFloat(self.position.x() - forward.x()))][@as(usize, @intFromFloat(self.position.y()))] == 0) {
                self.position.data[0] -= forward.x();
            }
            if (worldMap[@as(usize, @intFromFloat(self.position.x()))][@as(usize, @intFromFloat(self.position.y() - forward.y()))] == 0) {
                self.position.data[1] -= forward.y();
            }
        }

        const rotationDegrees: f32 = if (kbd.isDown(.Exe)) 2.0 else 4.0;
        if (kbd.isDown(.Left)) {
            self.yaw -= std.math.degreesToRadians(f32, rotationDegrees * DELTA_SCALE);
        }
        if (kbd.isDown(.Right)) {
            self.yaw += std.math.degreesToRadians(f32, rotationDegrees * DELTA_SCALE);
        }

        if (walking and t % 2 == 0) {
            if (self.walkUp) {
                self.pitch += 1;
                if (self.pitch > 1) self.walkUp = false;
            } else {
                self.pitch -= 1;
                if (self.pitch < -1) self.walkUp = true;
            }
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
var score: u32 = 0;
var highScore: u32 = 0;
var damageTime: u32 = 0;

const MAP_WIDTH = 64;
const MAP_HEIGHT = 64;

const DELTA_SCALE = 1.0;

const SPRITE_TRANSPARENT_COLOR = eadk.rgb(0x980088);

pub fn loadMapFromFile(comptime file: []const u8) [MAP_WIDTH][MAP_HEIGHT]u8 {
    comptime {
        @setEvalBranchQuota(10000000);
        var map = std.mem.zeroes([MAP_WIDTH][MAP_HEIGHT]u8);
        var split = std.mem.split(u8, file, "\n");
        var y = 0;
        while (split.next()) |line| {
            if (line.len < 2) break;
            for (line, 0..) |char, x| {
                map[x][y] = std.fmt.parseUnsigned(u8, &.{char}, 10) catch unreachable;
            }
            y += 1;
        }
        return map;
    }
}

fn fill(filled: *[MAP_WIDTH][MAP_HEIGHT]bool, x: usize, y: usize) void {
    filled[x][y] = true;
    if (x > 0 and worldMap[x - 1][y] == 0 and filled[x - 1][y] == false) {
        fill(filled, x - 1, y);
    }
    if (x < MAP_WIDTH and worldMap[x + 1][y] == 0 and filled[x + 1][y] == false) {
        fill(filled, x + 1, y);
    }
    if (y > 0 and worldMap[x][y - 1] == 0 and filled[x][y - 1] == false) {
        fill(filled, x, y - 1);
    }
    if (y < MAP_HEIGHT and worldMap[x][y + 1] == 0 and filled[x][y + 1] == false) {
        fill(filled, x, y + 1);
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
    fill(&array, 35, 62);

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

const Object = struct {
    texture: u8,
    x: f32,
    y: f32,
    distance: f32 = undefined,

    pub fn sortDsc(_: void, a: Object, b: Object) bool {
        return a.distance > b.distance;
    }

    pub fn sortAsc(_: void, a: Object, b: Object) bool {
        return a.distance < b.distance;
    }
};

const Sprite = struct {
    texture: u8,
    x: f32,
    y: f32,
    distance: f32 = undefined,
    lastSeenPlayerPos: Vec2 = Vec2.new(0, 0),
    shootTimer: u8 = 60,
    hp: u8 = 100,

    pub fn sortDsc(_: void, a: Sprite, b: Sprite) bool {
        return a.distance > b.distance;
    }

    pub fn sortAsc(_: void, a: Sprite, b: Sprite) bool {
        return a.distance < b.distance;
    }

    fn propagate(canSee: *[MAP_WIDTH][MAP_HEIGHT]bool, x: u8, y: u8, right: bool, down: bool) void {
        canSee[x][y] = true;
        if (!(worldMap[x + 1][y] == 0 or !right) or !(worldMap[x - 1][y] == 0 or right) or !(worldMap[x][y + 1] == 0 or !down) or !(worldMap[x][y - 1] == 0 or down)) {
            return;
        }
        if (right) {
            if (x < MAP_WIDTH and worldMap[x + 1][y] == 0 and !canSee[x + 1][y]) { // right
                propagate(canSee, x + 1, y, right, down);
            }
        } else {
            if (x > 0 and worldMap[x - 1][y] == 0 and !canSee[x - 1][y]) { // left
                propagate(canSee, x - 1, y, right, down);
            }
        }
        if (down) {
            if (y < MAP_HEIGHT and worldMap[x][y + 1] == 0 and !canSee[x][y + 1]) { // down
                propagate(canSee, x, y + 1, right, down);
            }
        } else {
            if (y > 0 and worldMap[x][y - 1] == 0 and !canSee[x][y - 1]) { // up
                propagate(canSee, x, y - 1, right, down);
            }
        }
    }

    pub fn hit(self: *Sprite, damage: u8) void {
        if (self.hp == 0) return;

        if (self.hp -| damage == 0) {
            self.shootTimer = 6;
            self.texture = 7;
        }
        self.hp -|= damage;
    }

    pub fn isDead(self: *const Sprite) bool {
        return self.hp == 0 and self.texture == 11;
    }

    pub fn update(self: *Sprite) void {
        // TODO: regarder en direction de l'ennemi et faire un raycast avec les murs
        // TODO: faire la même chose quand l'ennemi tire
        if (self.hp == 0) {
            self.shootTimer -= 1;
            if (self.shootTimer == 0) {
                self.shootTimer = 6;
                self.texture += 1;
                if (self.texture == 11) {
                    const object = Object{
                        .texture = 0,
                        .x = self.x,
                        .y = self.y,
                    };
                    objects.append(object) catch garbageCollector();
                    score += 100;
                }
            }
            return;
        }

        var canSee = std.mem.zeroes([MAP_WIDTH][MAP_HEIGHT]bool);
        const sprX = @as(u8, @intFromFloat(self.x));
        const sprY = @as(u8, @intFromFloat(self.y));

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

        if (canSee[@as(usize, @intFromFloat(camera.position.x()))][@as(usize, @intFromFloat(camera.position.y()))]) {
            self.lastSeenPlayerPos = camera.position;
        }

        var moved = false;
        var prepareShooting = false;
        if (self.lastSeenPlayerPos.x() != 0) {
            const direction = self.lastSeenPlayerPos.sub(Vec2.new(self.x, self.y)).norm().scale(0.05 * DELTA_SCALE);
            if (camera.position.sub(Vec2.new(self.x, self.y)).length() > 3.5) {
                moved = true;
                if (worldMap[@as(usize, @intFromFloat(self.x + direction.x()))][@as(usize, @intFromFloat(self.y))] == 0) {
                    self.x += direction.x();
                }
                if (worldMap[@as(usize, @intFromFloat(self.x))][@as(usize, @intFromFloat(self.y + direction.y()))] == 0) {
                    self.y += direction.y();
                }
            } else {
                prepareShooting = true;
                self.shootTimer -= 1;
                if (self.shootTimer == 0) {
                    // tirer
                    // TODO: aabb check

                    // TODO: inversement proportionnel à la distance
                    hp -|= 20;
                    damageTime = 30;

                    self.shootTimer = 60; // 1.5 secondes
                }
            }
        }

        if (moved) {
            self.texture = 1 + @as(u8, @intCast((t / 5) % 4));
            self.shootTimer = 40; // 1 seconde
        } else if (prepareShooting) {
            self.texture = 5;
            if (self.shootTimer > 55) {
                self.texture = 6;
            }
        } else {
            self.texture = 0;
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
var sprites = std.BoundedArray(Sprite, 8).init(0) catch unreachable;
/// Des objects, comme les plantes
var objects = std.BoundedArray(Object, 64).init(0) catch unreachable;
var wall_stripes = std.mem.zeroes([eadk.SCENE_WIDTH]WallState);

// TODO: passer en 24x24? ne prend que 3.5KiB pour 3 textures
// voire utiliser 32x32 si il reste de la RAM après que le jeu soit fini
const TEXTURE_WIDTH = 16;
const TEXTURE_HEIGHT = 16;
const textures = [_][TEXTURE_HEIGHT][TEXTURE_WIDTH]eadk.EadkColor{
    resources.wall_1,
    resources.wall_2,
    resources.wall_3,
    resources.wall_4,
    resources.wall_5,
};
const SPR_TEX_WIDTH = 48;
const SPR_TEX_HEIGHT = 48;
const sprite_textures = [_][SPR_TEX_HEIGHT][SPR_TEX_WIDTH]eadk.EadkColor{
    resources.guard,
    resources.guard_run_1,
    resources.guard_run_2,
    resources.guard_run_3,
    resources.guard_run_4,
    resources.guard_shoot,
    resources.guard_shooting,
    resources.guard_kill_1,
    resources.guard_kill_2,
    resources.guard_kill_3,
    resources.guard_kill_4,
};

const OBJ_TEX_WIDTH = 64;
const OBJ_TEX_HEIGHT = 64;
const object_textures = [_][OBJ_TEX_HEIGHT][OBJ_TEX_WIDTH]eadk.EadkColor{
    resources.guard_corpse,
    resources.skeleton,
};

const player_textures = [_][31][24]eadk.EadkColor{
    resources.player_0,
    resources.player_1,
    resources.player_2,
    resources.player_3,
    resources.player_4,
    resources.player_5,
    resources.player_6,
    resources.player_7,
};
/// For how long does the pistol appears fired
var pistolFiredTime: u16 = 0;

fn draw() void {
    //@setRuntimeSafety(false);

    if (state == .MainMenu) {
        // afficher menu
        eadk.display.fillRectangle(
            .{
                .x = 0,
                .y = 0,
                .width = eadk.SCENE_WIDTH,
                .height = eadk.SCENE_HEIGHT,
            },
            eadk.rgb(0x000000),
        );
        return;
    }

    if (eadk.display.isUpperBuffer) {
        eadk.display.fillRectangle(.{
            .x = 0,
            .y = 0,
            .width = eadk.SCENE_WIDTH,
            .height = eadk.SCENE_HEIGHT / 2,
        }, eadk.rgb(0x383838));
    }
    if (!eadk.display.isUpperBuffer or true) {
        eadk.display.fillRectangle(.{
            .x = 0,
            .y = eadk.SCENE_HEIGHT / 2,
            .width = eadk.SCENE_WIDTH,
            .height = eadk.SCENE_HEIGHT / 2,
        }, eadk.rgb(0x888888));
    }

    const planeVec = camera.getRight().scale(60.0 / 90.0); // un fov de 90°
    const planeX = planeVec.x();
    const planeY = planeVec.y();
    const dir = camera.getForward();
    const fbRect = eadk.display.getFramebufferRect();

    const w = eadk.SCENE_WIDTH;
    const h = eadk.SCENE_HEIGHT;

    var zBuffer: [eadk.SCENE_WIDTH]f32 = undefined;
    var x: u16 = 0;
    while (x < w) : (x += 1) {
        if (!eadk.display.isUpperBuffer) { // calculer une seule fois
            const cameraX = @as(f32, @floatFromInt(2 * x)) / @as(f32, @floatFromInt(w)) - 1.0;
            const rayDirX = dir.x() + planeX * cameraX;
            const rayDirY = dir.y() + planeY * cameraX;

            var mapX = @as(i16, @intFromFloat(camera.position.x()));
            var mapY = @as(i16, @intFromFloat(camera.position.y()));

            const deltaDistX = if (rayDirX == 0) std.math.inf(f32) else @fabs(1.0 / rayDirX);
            const deltaDistY = if (rayDirY == 0) std.math.inf(f32) else @fabs(1.0 / rayDirY);

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

                if (mapX >= 0 and mapY >= 0 and mapX < MAP_WIDTH and mapY < MAP_HEIGHT and worldMap[@as(u16, @intCast(mapX))][@as(u16, @intCast(mapY))] > 0) {
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
            const lineHeightFloat = @as(f32, @floatFromInt(h)) / perpWallDist;
            const lineHeight = @as(u16, @intFromFloat(@max(0, @min(h, lineHeightFloat))));
            zBuffer[x] = perpWallDist;

            const drawStart = @as(u16, @intCast(@max(0, @as(i16, @intCast(h / 2 - lineHeight / 2)) + camera.pitch)));
            const drawEnd = @min(
                @as(u16, @intCast(@as(i16, @intCast(lineHeight / 2 + h / 2)) + camera.pitch)),
                h - 1,
            );

            var textureId = if (mapX >= MAP_WIDTH or mapY >= MAP_HEIGHT or mapX < 0 or mapY < 0) 1 else worldMap[@as(u16, @intCast(mapX))][@as(u16, @intCast(mapY))] -% 1;
            if (textureId == 0xFF) { // it overflowed
                textureId = 1;
            }

            var wallX = if (side == 0)
                camera.position.y() + perpWallDist * rayDirY
            else
                camera.position.x() + perpWallDist * rayDirX;
            wallX -= @floor(wallX);

            var texX = std.math.lossyCast(u8, wallX * @as(f32, TEXTURE_WIDTH));
            if (side == 0 and rayDirX > 0) texX = TEXTURE_WIDTH - texX - 1;
            if (side == 1 and rayDirY < 0) texX = TEXTURE_WIDTH - texX - 1;

            // TODO: changer texPos pour utiliser que des int ? faudrait changer les al gore ithmes
            const step = 1.0 * @as(f32, TEXTURE_HEIGHT) / lineHeightFloat;
            const texPos = (@as(f32, @floatFromInt(@as(isize, drawStart) - h / 2 - camera.pitch)) + lineHeightFloat / 2) * step;
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
        const drawEnd = @min(fbRect.y + fbRect.height, stripe.drawEnd);
        while (y < drawEnd) : (y += 1) {
            @setRuntimeSafety(false);
            const texY = std.math.lossyCast(usize, stripe.texPos) % TEXTURE_HEIGHT;
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
    std.mem.sort(Sprite, sprites.slice(), {}, Sprite.sortDsc);
    for (sprites.constSlice()) |sprite| {
        const spriteX = sprite.x - camera.position.x();
        const spriteY = sprite.y - camera.position.y();

        const invDet = 1.0 / (planeX * dir.y() - dir.x() * planeY);
        const transformX = invDet * (dir.y() * spriteX - dir.x() * spriteY);
        const transformY = invDet * (-planeY * spriteX + planeX * spriteY);
        var spriteScreenX = std.math.lossyCast(i16, @min(@as(f32, @floatFromInt(w)) / 2.0 * (1 + transformX / transformY), 0x7FFF));
        var spriteHeight = std.math.lossyCast(u16, @fabs(@as(f32, @floatFromInt(h)) / transformY));

        const screenY = h / 2;
        const drawStartY = screenY -| spriteHeight / 2;
        const drawEndY = @min(screenY + spriteHeight / 2, h - 1);

        const spriteWidth = spriteHeight;
        const drawStartX = spriteScreenX -| @as(i16, @intCast(spriteWidth / 2));
        const drawEndX = std.math.lossyCast(u16, @min(spriteScreenX +| @as(i16, @intCast(spriteWidth / 2)), w - 1));

        var stripe = drawStartX;
        while (stripe < drawEndX) : (stripe += 1) {
            const texX = std.math.lossyCast(u16, 256 * @as(f32, @floatFromInt(stripe - drawStartX)) * SPR_TEX_WIDTH / @as(f32, @floatFromInt(spriteWidth))) / 256;
            if (transformY > 0 and stripe > 0 and stripe < w and transformY < zBuffer[@as(u16, @intCast(stripe))]) {
                var y: u16 = drawStartY;
                while (y < drawEndY) : (y += 1) {
                    const d = @as(u32, y) * 256 + @as(u32, spriteHeight) * 128 - @as(u32, h) * 128; // ???? https://lodev.org/cgtutor/raycasting3.html
                    const texY = ((d * SPR_TEX_HEIGHT) / spriteHeight) / 256;
                    const color = sprite_textures[sprite.texture][texY][texX];
                    if (color != SPRITE_TRANSPARENT_COLOR) {
                        eadk.display.setPixel(@as(u16, @intCast(stripe)), y, color);
                    }
                }
            }
        }
    }

    // Dessiner les objets
    for (objects.slice()) |*object| {
        object.distance = (camera.position.x() - object.x) * (camera.position.x() - object.x) + (camera.position.y() - object.y) * (camera.position.y() - object.y);
    }
    std.mem.sort(Object, objects.slice(), {}, Object.sortDsc);
    for (objects.constSlice()) |sprite| {
        const spriteX = sprite.x - camera.position.x();
        const spriteY = sprite.y - camera.position.y();

        const invDet = 1.0 / (planeX * dir.y() - dir.x() * planeY);
        const transformX = invDet * (dir.y() * spriteX - dir.x() * spriteY);
        const transformY = invDet * (-planeY * spriteX + planeX * spriteY);
        var spriteScreenX = std.math.lossyCast(i16, @min(@as(f32, @floatFromInt(w)) / 2.0 * (1 + transformX / transformY), 0x7FFF));
        var spriteHeight = std.math.lossyCast(u16, @fabs(@as(f32, @floatFromInt(h)) / transformY));

        const screenY = h / 2;
        const drawStartY = screenY -| spriteHeight / 2;
        const drawEndY = @min(screenY + spriteHeight / 2, h - 1);

        const spriteWidth = spriteHeight;
        const drawStartX = spriteScreenX -| @as(i16, @intCast(spriteWidth / 2));
        const drawEndX = std.math.lossyCast(u16, @min(spriteScreenX +| @as(i16, @intCast(spriteWidth / 2)), w - 1));

        var stripe = drawStartX;
        while (stripe < drawEndX) : (stripe += 1) {
            const texX = std.math.lossyCast(u16, 256 * @as(f32, @floatFromInt(stripe - drawStartX)) * OBJ_TEX_WIDTH / @as(f32, @floatFromInt(spriteWidth))) / 256;
            if (transformY > 0 and stripe > 0 and stripe < w and transformY < zBuffer[@as(u16, @intCast(stripe))]) {
                var y: u16 = drawStartY;
                while (y < drawEndY) : (y += 1) {
                    const d = @as(u32, y) * 256 + @as(u32, spriteHeight) * 128 - @as(u32, h) * 128; // ???? https://lodev.org/cgtutor/raycasting3.html
                    const texY = ((d * OBJ_TEX_HEIGHT) / spriteHeight) / 256;
                    const color = object_textures[sprite.texture][texY][texX];
                    if (color != SPRITE_TRANSPARENT_COLOR) {
                        eadk.display.setPixel(@as(u16, @intCast(stripe)), y, color);
                    }
                }
            }
        }
    }

    // On the bottom half of the screen
    if (!eadk.display.isUpperBuffer) {
        const isPistolFired = pistolFiredTime > 36;
        const isPistolReloading = pistolFiredTime > 0 and pistolFiredTime <= 36;
        const SCALE = 2;
        if (isPistolFired) {
            eadk.display.fillTransparentImage(
                .{ .x = eadk.SCENE_WIDTH / 2 - (24 * SCALE / 2), .y = eadk.SCENE_HEIGHT - (29 * SCALE - 10), .width = 24 * SCALE, .height = 29 * SCALE - 10 },
                @as([*]const u16, @ptrCast(&resources.pistol_fire)),
                SCALE,
            );
        } else {
            if (isPistolReloading) {
                eadk.display.fillTransparentImage(
                    .{ .x = eadk.SCENE_WIDTH / 2 - (24 * SCALE / 2), .y = eadk.SCENE_HEIGHT - (24 * SCALE - 10), .width = 24 * SCALE, .height = 24 * SCALE - 10 },
                    @as([*]const u16, @ptrCast(&resources.pistol)),
                    SCALE,
                );
            } else {
                eadk.display.fillTransparentImage(
                    .{ .x = eadk.SCENE_WIDTH / 2 - (24 * SCALE / 2), .y = eadk.SCENE_HEIGHT - (24 * SCALE), .width = 24 * SCALE, .height = 24 * SCALE },
                    @as([*]const u16, @ptrCast(&resources.pistol)),
                    SCALE,
                );
            }
        }

        // HUD
        eadk.display.fillRectangle(.{
            .x = 0,
            .y = eadk.SCENE_HEIGHT,
            .width = eadk.SCREEN_WIDTH,
            .height = eadk.SCREEN_HEIGHT - eadk.SCENE_HEIGHT,
        }, eadk.rgb(0x404040));

        const player_texture = std.math.clamp((100 - hp) / (100 / 8), 0, 7);
        eadk.display.fillRectangle(.{ .x = eadk.SCREEN_WIDTH / 2 - (32 / 2), .y = eadk.SCREEN_HEIGHT - 32, .width = 32, .height = 32 }, eadk.rgb(0x484848));
        eadk.display.fillTransparentImage(
            .{ .x = eadk.SCREEN_WIDTH / 2 - (24 / 2), .y = eadk.SCREEN_HEIGHT - 31, .width = 24, .height = 31 },
            @as([*]const u16, @ptrCast(&player_textures[player_texture])),
            1,
        );
    }

    if (hp == 0) {
        state = .MainMenu;
    }

    if (damageTime > 0) {
        //eadk.display.fillRectangle(.{
        //    .x = 0,
        //    .y = 0,
        //    .width = eadk.SCENE_WIDTH,
        //    .height = eadk.SCENE_HEIGHT,
        //}, eadk.rgb(0xFF0000));

        var pos: usize = 0;
        const b = eadk.rgb(0xFF0000);
        const bR = eadk.getRed(b);
        const bG = eadk.getGreen(b);
        const bB = eadk.getBlue(b);

        const lt = @as(f32, @floatFromInt(damageTime)) / 30.0;
        while (pos < eadk.display.FRAMEBUFFER_WIDTH * eadk.display.FRAMEBUFFER_HEIGHT) : (pos += 1) {
            const a = eadk.display.framebuffer[pos];
            const aR = eadk.getRed(a);
            const aG = eadk.getGreen(a);
            const aB = eadk.getBlue(a);

            eadk.display.framebuffer[pos] = eadk.colorFromComponents(
                @as(u5, @intFromFloat(@as(f32, @floatFromInt(aR)) * (1 - lt) + @as(f32, @floatFromInt(bR)) * lt)),
                @as(u6, @intFromFloat(@as(f32, @floatFromInt(aG)) * (1 - lt) + @as(f32, @floatFromInt(bG)) * lt)),
                @as(u5, @intFromFloat(@as(f32, @floatFromInt(aB)) * (1 - lt) + @as(f32, @floatFromInt(bB)) * lt)),
            );
        }
        damageTime -= 1;
    }
}

fn rayAabb(origin: Vec2, direction: Vec2, aabb: [2]Vec2) f32 {
    var lo = -std.math.inf(f32);
    var hi = std.math.inf(f32);

    comptime var i = 0;
    inline while (i < 2) : (i += 1) {
        var dimLo = (aabb[0].data[i] - origin.data[i]) / direction.data[i];
        var dimHi = (aabb[1].data[i] - origin.data[i]) / direction.data[i];

        if (dimLo > dimHi) {
            std.mem.swap(f32, &dimLo, &dimHi);
        }

        if (dimHi < lo or dimLo > hi) {
            return std.math.inf(f32);
        }

        lo = @max(lo, dimLo);
        hi = @min(hi, dimHi);
    }

    return if (lo > hi) std.math.inf(f32) else lo;
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
                .x = @as(f32, @floatFromInt(x)) + 0.5,
                .y = @as(f32, @floatFromInt(y)) + 0.5,
            };
            sprites.append(sprite) catch return;
            break;
        }
    }
}

/// Collects garbages (like corpses) from the objects array
fn garbageCollector() void {
    for (objects.slice(), 0..) |*object, i| {
        if (object.texture == 0) { // corpse
            _ = objects.swapRemove(i);
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
        // HIGH SCORE
        if (score > highScore) {
            highScore = score;
        }

        if (state == .Playing) {
            camera.input();
            if (sprites.slice().len == 0) {
                var idx: usize = 0;
                while (idx < 32) : (idx += 1) {
                    spawnEnemy(random);
                }
            }
            for (sprites.slice(), 0..) |*sprite, i| {
                sprite.update();
                if (sprite.isDead()) {
                    _ = sprites.swapRemove(i);
                }
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
            if (hp < 100) {
                // if (t % 40 == 0) hp += 1; // TODO: des potions de soin plutôt?
            }

            //const msg = std.fmt.bufPrintZ(&buf, "{d}fps", .{@floatToInt(u16, fps)}) catch unreachable;
            //eadk.display.drawString(msg, .{ .x = 0, .y = 0 }, false, eadk.rgb(0xFFFFFF), eadk.rgb(0x000000));
            eadk.display.drawString(
                std.fmt.bufPrintZ(&buf, "Score: {d} / {d}", .{ score, score / 800 * 800 + 800 }) catch unreachable,
                .{ .x = 0, .y = 0 },
                false,
                eadk.rgb(0xFFFFFF),
                eadk.rgb(0x000000),
            );
        }

        if (state == .MainMenu) {
            eadk.display.drawString("NazKiller", .{ .x = 0, .y = 0 }, true, eadk.rgb(0xFFFFFF), eadk.rgb(0x000000));
            eadk.display.drawString("(c) Zen1th", .{ .x = 0, .y = 20 }, false, eadk.rgb(0x888888), eadk.rgb(0x000000));
            eadk.display.drawString("> Press EXE to play", .{ .x = 0, .y = 220 }, true, eadk.rgb(0xFFFFFF), eadk.rgb(0x00000));
            eadk.display.drawString(
                std.fmt.bufPrintZ(&buf, "High Score: {}", .{highScore}) catch unreachable,
                .{ .x = 0, .y = 40 },
                false,
                eadk.rgb(0xFFFFFF),
                eadk.rgb(0x000000),
            );

            if (kbd.isDown(.Exe)) {
                state = .Playing;
                t = 0;
                hp = 100;
                camera = .{};
                score = 0;
                damageTime = 0;
                sprites.resize(0) catch unreachable;
            }
        } else {
            pistolFiredTime -|= 1;
            if (kbd.isDown(.OK) and pistolFiredTime == 0) {
                pistolFiredTime = 40; // 1.0 s
                std.mem.sort(Sprite, sprites.slice(), {}, Sprite.sortAsc);
                for (sprites.slice()) |*sprite| {
                    const aabb: [2]Vec2 = .{
                        Vec2.new(sprite.x - 0.5, sprite.y - 0.5),
                        Vec2.new(sprite.x + 0.5, sprite.y + 0.5),
                    };
                    if (rayAabbIntersection(camera.position, camera.getForward(), aabb)) {
                        sprite.hit(100);
                        break;
                    }
                }
            }
        }
        if (kbd.isDown(.Back)) {
            break;
        }

        const end = eadk.eadk_timing_millis();
        const frameFps = 1.0 / (@as(f32, @floatFromInt(@as(u32, @intCast(end - start)))) / 1000);
        fps = fps * 0.9 + frameFps * 0.1; // faire interpolation linéaire vers la valeur fps
        if (frameFps > 40) eadk.display.waitForVblank();
    }
}

export fn main() void {
    eadk_main();
}

comptime {
    _ = @import("c.zig");
}
