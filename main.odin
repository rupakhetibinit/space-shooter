package main

import "core:fmt"
import "core:math"
import rl "vendor:raylib"

HEADLESS :: #config(HEADLESS, false)
CREATOR_BUILD :: #config(CREATOR_BUILD, ODIN_OS != .JS)
Enemy_Kind :: enum {
	Scout,
	Weaver,
	Diver,
	Tank,
	Spitter,
	Boss,
}
Phase :: enum {
	Briefing,
	Playing,
	Intermission,
	Defeat,
	Victory,
}
Controls :: struct {
	move:                 rl.Vector2,
	fire, pause, restart: bool,
}
Enemy :: struct {
	kind:                                                Enemy_Kind,
	position, home:                                      rl.Vector2,
	age, cooldown, hit_flash:                            f32,
	hp, max_hp:                                          int,
	behavior_seed:                                       u32,
	shot_index, maneuver_index:                          u32,
	velocity, aim_target, dive_from, dive_to:            rl.Vector2,
	mode:                                                Enemy_Mode,
	mode_time, maneuver_timer, dive_bend, dive_duration: f32,
	aim_locked:                                          bool,
	delay:                                               f32,
}
Shot :: struct {
	position, velocity: rl.Vector2,
	friendly:           bool,
	radius:             f32,
}
Burst :: struct {
	position: rl.Vector2,
	age:      f32,
	color:    rl.Color,
}
Pickup :: struct {
	position: rl.Vector2,
}

shipTexture, imageBackground, laserTexture, enemyProjectileTexure: rl.Texture2D
enemyTexture, explosionTexture: rl.Texture2D
laserSound, explosionSound: rl.Sound
shipPosition: rl.Vector2
lasers: [dynamic]Shot
enemies: [dynamic]Enemy
explosions: [dynamic]Burst
pickups: [dynamic]Pickup
phase: Phase
paused: bool
level, wave, shields, score, kills: int
clock, phase_timer, fire_timer, invulnerable, weapon_timer: f32

when ODIN_OS != .JS {
	main :: proc() {
		init_game()
		for !rl.WindowShouldClose() {
			update_game()
			free_all(context.temp_allocator)
		}
		shutdown_game()
	}
}

init_game :: proc() {
	rl.InitWindow(800, 600, "Space Shooter - Outer Rim")
	rl.InitAudioDevice()
	shipTexture = rl.LoadTexture("assets/ship.png")
	imageBackground = rl.LoadTexture("assets/bg.png")
	laserTexture = rl.LoadTexture("assets/laser.png")
	enemyProjectileTexure = rl.LoadTexture("assets/enemy_projectile.png")
	enemyTexture = rl.LoadTexture("assets/enemy.png")
	explosionTexture = rl.LoadTexture("assets/explosion.png")
	laserSound = rl.LoadSound("assets/laser.wav")
	explosionSound = rl.LoadSound("assets/explosion.wav")
	rl.SetSoundVolume(laserSound, 0.22)
	rl.SetSoundVolume(explosionSound, 0.35)
	rl.SetTargetFPS(144)
	load_campaign_files()
	reset_round()
}

shutdown_game :: proc() {
	delete(lasers);delete(enemies);delete(explosions);delete(pickups)
	rl.UnloadSound(laserSound);rl.UnloadSound(explosionSound)
	for t in ([6]rl.Texture2D {
			shipTexture,
			imageBackground,
			laserTexture,
			enemyProjectileTexure,
			enemyTexture,
			explosionTexture,
		}) {
		rl.UnloadTexture(t)
	}
	rl.CloseAudioDevice();rl.CloseWindow()
}

reset_round :: proc() {
	ensure_campaign()
	preview_mode = false
	clear(&lasers);clear(&enemies);clear(&explosions);clear(&pickups)
	shipPosition = {380, 520}
	level = 1;wave = 1;shields = 5;score = 0;kills = 0
	clock = 0;fire_timer = 0;invulnerable = 0;weapon_timer = 0
	paused = false;phase = .Briefing;phase_timer = 2.5
}

spawn_enemy :: proc(kind: Enemy_Kind, x, y: f32, index: int) {
	hp := 1
	switch kind {
	case .Scout, .Diver:
	case .Weaver:
		hp = 2
	case .Tank:
		hp = 4
	case .Spitter:
		hp = 3
	case .Boss:
		hp = 48
	}
	enemy := Enemy {
		kind     = kind,
		position = {x, y},
		home     = {x, y},
		hp       = hp,
		max_hp   = hp,
	}
	enemy_behavior_init(&enemy, index)
	append(&enemies, enemy)
}

enemy_size :: proc(kind: Enemy_Kind) -> rl.Vector2 {
	switch kind {
	case .Scout:
		return {44, 40}
	case .Weaver:
		return {42, 40}
	case .Diver:
		return {36, 44}
	case .Tank:
		return {58, 44}
	case .Spitter:
		return {48, 42}
	case .Boss:
		return {140, 86}
	}
	return {}
}
enemy_rect :: proc(e: Enemy) -> rl.Rectangle {
	s := enemy_size(e.kind)
	return {e.position.x - s.x / 2, e.position.y - s.y / 2, s.x, s.y}
}
ship_rect :: proc() -> rl.Rectangle {
	// A forgiving hitbox inside the 40x40 sprite.
	return {shipPosition.x + 10, shipPosition.y + 9, 20, 25}
}
enemy_color :: proc(k: Enemy_Kind) -> rl.Color {
	switch k {
	case .Scout:
		return {177, 244, 103, 255}
	case .Weaver:
		return {101, 220, 255, 255}
	case .Diver:
		return {255, 125, 126, 255}
	case .Tank:
		return {247, 189, 90, 255}
	case .Spitter:
		return {205, 149, 255, 255}
	case .Boss:
		return {255, 94, 137, 255}
	}
	return rl.WHITE
}

sound :: proc(s: rl.Sound) {when !HEADLESS {rl.PlaySound(s)}}
add_burst :: proc(pos: rl.Vector2, color: rl.Color) {
	append(&explosions, Burst{position = pos, color = color})
}
hurt_player :: proc() {
	if invulnerable > 0 || phase != .Playing {return}
	shields -= 1;invulnerable = 1.0
	add_burst({shipPosition.x + 20, shipPosition.y + 20}, {101, 220, 255, 255})
	sound(explosionSound)
	if shields <= 0 {phase = .Defeat}
}
step_game :: proc(dt: f32, input: Controls) {
	if input.restart {reset_round();return}
	if input.pause && phase != .Defeat && phase != .Victory {paused = !paused}
	if paused {return}
	clock += dt
	for i := len(explosions) - 1; i >= 0; i -= 1 {
		explosions[i].age += dt
		if explosions[i].age >= 0.42 {unordered_remove(&explosions, i)}
	}
	if phase == .Briefing || phase == .Intermission {
		phase_timer -= dt
		if phase_timer <= 0 {spawn_wave();phase = .Playing}
		return
	}
	if phase != .Playing {return}
	invulnerable = max(0, invulnerable - dt)
	weapon_timer = max(0, weapon_timer - dt)
	fire_timer -= dt
	direction := input.move
	if direction.x != 0 && direction.y != 0 {direction *= 0.70710678}
	shipPosition += direction * 300 * dt
	shipPosition.x = clamp(shipPosition.x, 12, 748)
	shipPosition.y = clamp(shipPosition.y, 315, 538)
	if input.fire && fire_timer <= 0 {
		fire_timer = 0.18
		origin := shipPosition + rl.Vector2{20, -4}
		append(&lasers, Shot{position = origin, velocity = {0, -560}, friendly = true, radius = 4})
		if weapon_timer > 0 {
			for dx in ([2]f32{-110, 110}) {
				append(&lasers, Shot{position = origin, velocity = {dx, -540}, friendly = true, radius = 4})
			}
		}
		sound(laserSound)
	}
	enemy_update_all(dt)
	for i := len(lasers) - 1; i >= 0; i -= 1 {
		shot := &lasers[i]
		shot.position += shot.velocity * dt
		remove := shot.position.y < -30 || shot.position.y > 640 || shot.position.x < -30 || shot.position.x > 830
		if !remove && shot.friendly {
			for j := len(enemies) - 1; j >= 0; j -= 1 {
				e := &enemies[j]
				if e.delay > 0 {continue}
				if rl.CheckCollisionCircleRec(shot.position, shot.radius, enemy_rect(e^)) {
					remove = true;e.hp -= 1;e.hit_flash = 0.09
					if e.hp <= 0 {
						score += e.max_hp * 100;kills += 1
						add_burst(e.position, enemy_color(e.kind));sound(explosionSound)
						if kills % 8 == 0 {append(&pickups, Pickup{position = e.position})}
						unordered_remove(&enemies, j)
					}
					break
				}
			}
		} else if !remove && !shot.friendly && rl.CheckCollisionCircleRec(shot.position, shot.radius, ship_rect()) {
			remove = true;hurt_player()
		}
		if remove {unordered_remove(&lasers, i)}
	}
	for i := len(pickups) - 1; i >= 0; i -= 1 {
		pickups[i].position.y += 100 * dt
		if rl.CheckCollisionCircleRec(pickups[i].position, 16, {shipPosition.x, shipPosition.y, 40, 40}) {
			weapon_timer = 7
			score += 50
			unordered_remove(&pickups, i)
		} else if pickups[i].position.y > 630 {unordered_remove(&pickups, i)}
	}
	if phase == .Defeat {return}
	if len(enemies) == 0 {
		clear(&lasers);clear(&pickups)
		score += 250 * level
		weapon_timer = max(weapon_timer, 2)
		if preview_mode ||
		   (level == len(campaign.sectors) && wave == len(active_sector().waves)) {phase = .Victory;return}
		if wave == len(active_sector().waves) {
			wave = 1;level += 1
			shields = min(5, shields + 1)
			phase_timer = 3
		} else {wave += 1;phase_timer = 2}
		phase = .Intermission
		shipPosition = {380, 520};invulnerable = 1.0
	}
}

update_game :: proc() {
	when CREATOR_BUILD {
		if !editor_name_edit && rl.IsKeyPressed(.E) {toggle_editor()}
		if editor_open {update_editor();draw_editor();return}
	}
	input: Controls
	if rl.IsKeyDown(.LEFT) || rl.IsKeyDown(.A) {input.move.x -= 1}
	if rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.D) {input.move.x += 1}
	if rl.IsKeyDown(.UP) || rl.IsKeyDown(.W) {input.move.y -= 1}
	if rl.IsKeyDown(.DOWN) || rl.IsKeyDown(.S) {input.move.y += 1}
	input.fire = rl.IsKeyDown(.SPACE)
	input.restart = rl.IsKeyPressed(.R)
	input.pause = rl.IsKeyPressed(.P)
	step_game(min(rl.GetFrameTime(), 0.05), input)
	draw_game()
}

center_text :: proc(text: cstring, y, size: i32, color: rl.Color) {
	rl.DrawText(text, (800 - rl.MeasureText(text, size)) / 2, y, size, color)
}

draw_enemy :: proc(e: Enemy) {
	s := enemy_size(e.kind)
	c := enemy_color(e.kind)
	if e.hit_flash > 0 {c = rl.WHITE}
	x := i32(e.position.x);y := i32(e.position.y)
	dark := rl.Color{30, 33, 52, 255}
	if e.kind == .Scout {
		frame := int(e.age * 8) % 6
		rl.DrawTexturePro(
			enemyTexture,
			{f32(frame * int(enemyTexture.width / 6)), 0, f32(enemyTexture.width / 6), f32(enemyTexture.height)},
			{e.position.x - s.x / 2, e.position.y - s.y / 2, s.x, s.y},
			{0, 0},
			0,
			c,
		)
	} else {
		// Pixel silhouettes give each enemy a readable identity, not just a tint.
		switch e.kind {
		case .Weaver:
			rl.DrawRectangle(x - 21, y - 4, 42, 20, c);rl.DrawRectangle(x - 15, y - 16, 30, 28, c)
			rl.DrawRectangle(x - 27, y + 8, 8, 16, c);rl.DrawRectangle(x + 19, y + 8, 8, 16, c)
			rl.DrawRectangle(x - 9, y - 6, 6, 8, dark);rl.DrawRectangle(x + 3, y - 6, 6, 8, dark)
		case .Diver:
			rl.DrawTriangle({f32(x - 18), f32(y - 20)}, {f32(x), f32(y + 22)}, {f32(x + 18), f32(y - 20)}, c)
			rl.DrawRectangle(x - 5, y - 12, 10, 20, dark)
			rl.DrawRectangle(x - 3, y + 7, 6, 7, rl.WHITE)
		case .Tank:
			rl.DrawRectangle(x - 29, y - 12, 58, 30, c);rl.DrawRectangle(x - 21, y - 22, 42, 12, c)
			rl.DrawRectangle(x - 25, y + 15, 12, 9, dark);rl.DrawRectangle(x + 13, y + 15, 12, 9, dark)
			rl.DrawRectangle(x - 16, y - 7, 32, 12, dark);rl.DrawRectangle(x - 7, y - 4, 14, 6, rl.WHITE)
			rl.DrawRectangle(x - 5, y + 16, 10, 14, c)
		case .Spitter:
			rl.DrawPoly(e.position, 6, 26, 30, c)
			rl.DrawRectangle(x - 16, y - 8, 32, 13, dark)
			for dx in ([3]i32{-14, 0, 14}) {rl.DrawRectangle(x + dx - 3, y + 12, 6, 14, c)}
			rl.DrawCircle(x, y - 1, 5, rl.WHITE)
		case .Boss:
			rl.DrawRectangle(x - 70, y - 18, 140, 44, c)
			rl.DrawRectangle(x - 48, y - 39, 96, 22, c)
			rl.DrawRectangle(x - 62, y + 23, 25, 20, c);rl.DrawRectangle(x + 37, y + 23, 25, 20, c)
			rl.DrawRectangle(x - 40, y - 16, 80, 35, dark)
			rl.DrawCircle(x, y, 17, rl.Color{255, 230, 156, 255})
			rl.DrawCircle(x, y, 9, c)
			for dx in ([2]i32{-55, 55}) {rl.DrawRectangle(x + dx - 5, y - 8, 10, 10, rl.WHITE)}
		case .Scout:
		}
	}
	enemy_draw_intent(e)
	if e.max_hp > 1 && e.kind != .Boss {
		rl.DrawRectangle(x - i32(s.x / 2), y - i32(s.y / 2) - 8, i32(s.x), 3, {45, 49, 69, 255})
		rl.DrawRectangle(x - i32(s.x / 2), y - i32(s.y / 2) - 8, i32(s.x * f32(e.hp) / f32(e.max_hp)), 3, c)
	}
}

draw_game :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground({7, 10, 23, 255})
	// Existing star art scrolls under a second, slower procedural star layer.
	offset := f32(int(clock * 18) % 600)
	tint := rl.Color{155, 168, 210, 150}
	rl.DrawTexturePro(
		imageBackground,
		{0, 0, f32(imageBackground.width), f32(imageBackground.height)},
		{0, offset, 800, 600},
		{0, 0},
		0,
		tint,
	)
	rl.DrawTexturePro(
		imageBackground,
		{0, 0, f32(imageBackground.width), f32(imageBackground.height)},
		{0, offset - 600, 800, 600},
		{0, 0},
		0,
		tint,
	)
	for i in 0 ..< 45 {
		x := i32((i * 137 + 29) % 800)
		y := i32((f32(i * 73) + clock * f32(14 + i % 3 * 14))) % 600
		rl.DrawRectangle(x, y, 2, 2, {116, 140, 192, 160})
	}
	rl.DrawLine(12, 565, 788, 565, {50, 63, 86, 255})
	for e in enemies {if e.delay <= 0 {draw_enemy(e)}}
	for shot in lasers {
		if shot.friendly {
			rl.DrawRectangle(i32(shot.position.x) - 2, i32(shot.position.y) - 8, 4, 16, {138, 255, 225, 255})
		} else {
			rl.DrawCircleV(shot.position, shot.radius + 2, {111, 40, 61, 255})
			rl.DrawCircleV(shot.position, shot.radius, {255, 146, 148, 255})
			rl.DrawCircleV(shot.position, 2, {255, 240, 206, 255})
		}
	}
	for pickup in pickups {
		rl.DrawPoly(pickup.position, 4, 15, 45, {110, 243, 224, 255})
		rl.DrawText("+", i32(pickup.position.x) - 5, i32(pickup.position.y) - 8, 18, {13, 37, 47, 255})
	}
	if invulnerable <= 0 || int(clock * 12) % 2 == 0 {
		rl.DrawTexturePro(shipTexture, {16, 0, 16, 16}, {shipPosition.x, shipPosition.y, 40, 40}, {0, 0}, 0, rl.WHITE)
		flame := 8 + math.sin(clock * 35) * 4
		rl.DrawTriangle(
			{shipPosition.x + 15, shipPosition.y + 36},
			{shipPosition.x + 20, shipPosition.y + 40 + flame},
			{shipPosition.x + 25, shipPosition.y + 36},
			{101, 220, 255, 230},
		)
	}
	if invulnerable > 0 {
		rl.DrawCircleLines(i32(shipPosition.x + 20), i32(shipPosition.y + 20), 28, {115, 222, 255, 130})
	}
	for burst in explosions {
		frame := min(5, int(burst.age * 14))
		rl.DrawTexturePro(
			explosionTexture,
			{
				f32(frame * int(explosionTexture.width / 6)),
				0,
				f32(explosionTexture.width / 6),
				f32(explosionTexture.height),
			},
			{burst.position.x - 30, burst.position.y - 30, 60, 60},
			{0, 0},
			0,
			burst.color,
		)
	}
	// Heads-up display stays on solid panels for contrast against the starfield.
	rl.DrawRectangle(0, 0, 800, 52, {12, 18, 33, 245})
	rl.DrawText(sector_name(level), 18, 12, 20, {174, 204, 231, 255})
	rl.DrawText(fmt.ctprintf("WAVE %d / %d", wave, len(active_sector().waves)), 320, 15, 16, {147, 169, 194, 255})
	rl.DrawText(fmt.ctprintf("%06d", score), 664, 12, 24, {216, 246, 161, 255})
	rl.DrawRectangle(0, 566, 800, 34, {12, 18, 33, 245})
	rl.DrawText("SHIELD", 16, 578, 12, {147, 169, 194, 255})
	for i in 0 ..< 5 {
		c := rl.Color{41, 52, 71, 255}
		if i < shields {c = {109, 222, 233, 255}}
		rl.DrawRectangle(i32(73 + i * 17), 576, 12, 13, c)
	}
	when CREATOR_BUILD {
		rl.DrawText("WASD move  SPACE fire  P pause  R reset  E editor", 268, 578, 12, {147, 169, 194, 255})
	} else {
		rl.DrawText("WASD move   SPACE fire   P pause   R restart", 295, 578, 12, {147, 169, 194, 255})
	}
	pending := 0
	arrival: f32 = 30
	for e in enemies {if e.delay > 0 {pending += 1;arrival = min(arrival, e.delay)}}
	if pending >
	   0 {rl.DrawText(fmt.ctprintf("INCOMING %d / %.1fs", pending, arrival), 600, 78, 12, {247, 189, 90, 255})}
	if weapon_timer > 0 {
		rl.DrawText(fmt.ctprintf("TRIPLE SHOT  %.0fs", weapon_timer), 18, 57, 14, {110, 243, 224, 255})
	}
	for e in enemies {
		if e.kind == .Boss && e.delay <= 0 {
			rl.DrawRectangle(200, 62, 400, 10, {53, 36, 55, 255})
			rl.DrawRectangle(200, 62, i32(400 * f32(e.hp) / f32(e.max_hp)), 10, {255, 94, 137, 255})
			center_text("HIVE MATRIARCH", 79, 14, {255, 174, 191, 255})
		}
	}
	if phase == .Briefing || phase == .Intermission {
		rl.DrawRectangle(55, 216, 690, 164, {10, 17, 32, 235})
		center_text(sector_name(level), 243, 28, {216, 246, 161, 255})
		center_text(sector_tip(level), 287, 16, {185, 205, 226, 255})
		center_text(fmt.ctprintf("WAVE %d   /   LAUNCH IN %d", wave, int(math.ceil(phase_timer))), 332, 18, rl.WHITE)
	}
	if phase == .Defeat || phase == .Victory || paused {
		rl.DrawRectangle(0, 52, 800, 514, {6, 11, 22, 210})
		title: cstring = "PAUSED"
		subtitle: cstring = "Press P to return to flight"
		if phase == .Defeat {title = "SIGNAL LOST";subtitle = "Press R for a new run"}
		if phase == .Victory {title = "OUTER RIM SECURED";subtitle = "Campaign cleared. Press R to fly again."}
		if preview_mode &&
		   phase == .Victory {title = "WAVE TEST COMPLETE";subtitle = "Press E to return to the editor."}
		center_text(title, 235, 34, {216, 246, 161, 255})
		center_text(fmt.ctprintf("SCORE %06d   /   %d HOSTILES DESTROYED", score, kills), 294, 18, rl.WHITE)
		center_text(subtitle, 337, 18, {172, 196, 222, 255})
	}
	rl.EndDrawing()
}
