package tests

import game ".."
import "core:math"
import "core:testing"

// Run with: ./test-game.ps1
// One sequential scenario because the game state is shared by the frame loop.
@(test)
campaign_rules :: proc(t: ^testing.T) {
	when !game.HEADLESS {testing.expect(t, false, "Use -define:HEADLESS=true for gameplay tests");return}
	defer {delete(game.lasers);delete(game.enemies);delete(game.explosions);delete(game.pickups)}
	game.reset_round()
	testing.expect_value(t, game.phase, .Briefing)
	game.step_game(3, {})
	testing.expect_value(t, len(game.enemies), 6)
	testing.expect_value(t, game.phase, .Playing)
	x := game.shipPosition.x
	game.step_game(0.1, {move = {1, 0}, fire = true})
	testing.expect_value(t, game.shipPosition.x, x + 30)
	testing.expect_value(t, len(game.lasers), 1)
	game.step_game(0.1, {pause = true})
	frozen_clock := game.clock
	game.step_game(0.5, {move = {1, 0}, fire = true})
	testing.expect_value(t, game.clock, frozen_clock)
	game.step_game(0, {pause = true})
	clear(&game.lasers)
	append(&game.lasers, game.Shot{position = {game.shipPosition.x + 20, game.shipPosition.y + 20}, radius = 6})
	game.step_game(0, {})
	testing.expect_value(t, game.shields, 4)
	append(&game.lasers, game.Shot{position = {game.shipPosition.x + 20, game.shipPosition.y + 20}, radius = 6})
	game.step_game(0, {})
	testing.expect_value(t, game.shields, 4) // grace period prevents repeated hits
	append(&game.pickups, game.Pickup{position = game.shipPosition + {20, 20}})
	game.step_game(0, {})
	testing.expect_value(t, game.weapon_timer, f32(7))
	clear(&game.lasers);game.fire_timer = 0
	game.step_game(0, {fire = true})
	testing.expect_value(t, len(game.lasers), 3)

	// Complete all configured waves through the actual projectile collision path.
	seen: [game.Enemy_Kind]bool
	wave_count := 0
	for game.phase != .Victory && wave_count < 40 {
		if game.phase == .Intermission {game.step_game(4, {})}
		testing.expect_value(t, game.phase, .Playing)
		current_level := game.level
		current_wave := game.wave
		for len(game.enemies) > 0 {
			game.step_game(0, {})
			target := game.enemies[0]
			if target.delay > 0 {
				game.invulnerable = 999
				game.step_game(0.25, {})
				continue
			}
			seen[target.kind] = true
			clear(&game.lasers)
			append(&game.lasers, game.Shot{position = target.position, friendly = true, radius = 4})
			before := 0
			for e in game.enemies {before += e.hp}
			game.step_game(0, {})
			after := 0
			for e in game.enemies {after += e.hp}
			testing.expect_value(t, after, before - 1)
		}
		wave_count += 1
		if current_wave == len(game.campaign.sectors[current_level - 1].waves) &&
		   current_level < len(game.campaign.sectors) {
			testing.expect_value(t, game.level, current_level + 1)
			testing.expect_value(t, game.wave, 1)
		}
	}
	testing.expect_value(t, wave_count, 31)
	testing.expect_value(t, game.phase, .Victory)
	testing.expect(t, game.score > 10000)
	for kind in game.Enemy_Kind {testing.expect(t, seen[kind])}

	// Boss becomes more dangerous below half health.
	game.reset_round();clear(&game.enemies)
	game.level = 5;game.wave = 2;game.spawn_wave()
	boss := &game.enemies[0]
	clear(&game.lasers);game.fire_enemy(boss)
	testing.expect_value(t, len(game.lasers), 5)
	clear(&game.lasers);boss.hp = 24;game.fire_enemy(boss)
	testing.expect_value(t, len(game.lasers), 9)

	// A last hit ends the run; R restores an entirely fresh campaign.
	game.phase = .Playing;game.shields = 1;game.invulnerable = 0
	game.hurt_player()
	testing.expect_value(t, game.phase, .Defeat)
	game.step_game(0, {restart = true})
	testing.expect_value(t, game.phase, .Briefing)
	testing.expect_value(t, game.shields, 5)
	testing.expect_value(t, game.score, 0)
	testing.expect_value(t, game.level, 1)
	testing.expect_value(t, len(game.enemies), 0)

	// Config loading is transactional: malformed imports retain valid levels.
	testing.expect_value(t, len(game.campaign.sectors), 12)
	testing.expect(t, !game.load_campaign_json(`{"version":99,"sectors":[]}`))
	testing.expect_value(t, len(game.campaign.sectors), 12)
	testing.expect(t, !game.load_campaign_json(`{"version":1`))
	testing.expect_value(t, len(game.campaign.sectors), 12)
	encoded := game.campaign_json()
	testing.expect(t, game.load_campaign_json(string(encoded)))
	testing.expect_value(t, len(game.campaign.sectors), 12)

	custom := `{"version":1,"sectors":[{"name":"TEST","tip":"Custom wave","bullet_speed":1,"fire_interval":1,"motion_scale":1,"waves":[{"enemies":[{"kind":"Tank","x":400,"y":160,"hp":7,"delay":2}]}]}]}`
	testing.expect(t, game.load_campaign_json(custom))
	game.reset_round();game.step_game(3, {})
	testing.expect_value(t, len(game.enemies), 1)
	testing.expect_value(t, game.enemies[0].hp, 7)
	clear(&game.lasers)
	append(&game.lasers, game.Shot{position = {400, 160}, friendly = true, radius = 4})
	game.step_game(0, {})
	testing.expect_value(t, game.enemies[0].hp, 7) // pending enemies cannot be hit
	game.step_game(1, {})
	testing.expect(t, math.abs(game.enemies[0].delay - 1) < 0.0001)
	testing.expect(
		t,
		!game.load_campaign_json(
			`{"version":1,"sectors":[{"name":"X","bullet_speed":1,"fire_interval":1,"motion_scale":1,"waves":[{"enemies":[{"kind":"Typo","x":400,"y":160}]}]}]}`,
		),
	)
	testing.expect_value(t, len(game.campaign.sectors), 1)
	testing.expect_value(t, game.campaign.sectors[0].name, "TEST")
	// Editor cloning is deep after compaction; the original stays independent.
	game.editor_sector = 0;game.editor_wave = 0
	sector := &game.campaign.sectors[0]
	sector.waves = game.append_config(sector.waves, sector.waves[0])
	game.compact_edit()
	game.campaign.sectors[0].waves[1].enemies[0].hp = 9
	testing.expect_value(t, game.campaign.sectors[0].waves[0].enemies[0].hp, 7)
	testing.expect(t, game.load_campaign_json(string(game.DEFAULT_CAMPAIGN)))
	verify_behavior_rules(t)
}


sample_behavior :: proc(h: f32, frames, index: int) -> game.Enemy {
	game.reset_round()
	game.phase = .Playing
	game.spawn_enemy(.Weaver, 400, 160, index)
	game.enemies[0].cooldown = 100
	for i in 0 ..< frames {
		game.enemy_update_all(h)
	}
	return game.enemies[0]
}

verify_behavior_rules :: proc(t: ^testing.T) {
	// Value noise is bounded, deterministic and smooth at lattice boundaries.
	for i in -5000 ..< 5000 {
		x := f32(i) * 0.0137
		value := game.noise_wander(x, 1234)
		testing.expect(t, value >= -1 && value <= 1)
		testing.expect_value(t, value, game.noise_wander(x, 1234))
	}
	epsilon: f32 = 0.001
	for i in -10 ..< 10 {
		x := f32(i)
		center := game.noise_value(x, 1234)
		left := (center - game.noise_value(x - epsilon, 1234)) / epsilon
		right := (game.noise_value(x + epsilon, 1234) - center) / epsilon
		testing.expect(t, math.abs(left - right) < 0.01)
	}
	slow := sample_behavior(1.0 / 30.0, 300, 0)
	fast := sample_behavior(1.0 / 120.0, 1200, 0)
	testing.expect(t, game.vector_length(slow.position - fast.position) < 0.15)
	testing.expect(t, game.vector_length(slow.velocity - fast.velocity) < 0.3)
	repeat := sample_behavior(1.0 / 30.0, 300, 0)
	testing.expect_value(t, slow.position, repeat.position)
	different := sample_behavior(1.0 / 30.0, 300, 1)
	testing.expect(t, game.vector_length(slow.position - different.position) > 3)
	testing.expect(t, game.vector_length(slow.velocity) <= game.motion_profile(.Weaver).speed + 0.01)

	// The aim stays fixed through the warning even if the player changes lane.
	game.reset_round()
	game.phase = .Playing
	game.spawn_enemy(.Weaver, 400, 140, 0)
	e := &game.enemies[0]
	e.cooldown = 0.5
	game.enemy_update_weapon(e, 0)
	target := e.aim_target
	testing.expect(t, e.aim_locked)
	testing.expect_value(t, e.cooldown, game.ATTACK_WARNING)
	game.shipPosition.x = 700
	game.enemy_update_weapon(e, 0.3)
	testing.expect_value(t, e.aim_target, target)
	testing.expect_value(t, len(game.lasers), 0)
	game.enemy_update_weapon(e, 0.41)
	testing.expect_value(t, len(game.lasers), 1)
	testing.expect(t, math.abs(game.lasers[0].velocity.x) < 0.001)
	testing.expect(t, e.cooldown >= game.ATTACK_WARNING + 0.25)

	// Dive destination is locked before the windup and stays fixed thereafter.
	game.reset_round()
	game.phase = .Playing
	game.spawn_enemy(.Diver, 400, 140, 0)
	e = &game.enemies[0]
	game.enemy_begin_dive(e)
	destination := e.dive_to
	game.shipPosition.x = 30
	game.enemy_update_all(0.5)
	testing.expect_value(t, e.mode, .Windup)
	testing.expect_value(t, e.dive_to, destination)
	testing.expect(t, e.position.y < 200)
	game.enemy_update_all(0.4)
	testing.expect_value(t, e.mode, .Dive)
	game.enemy_update_all(e.dive_duration + 0.05)
	testing.expect_value(t, e.mode, .Return)
	testing.expect(t, game.vector_length(e.position - destination) < 20)
	testing.expect_value(t, e.dive_to, destination)

	// Stress maximum editor tuning and arena-edge spawns.
	game.reset_round()
	game.phase = .Playing
	game.active_sector().motion_scale = 2
	game.active_sector().variation = 1.5
	for kind in game.Enemy_Kind {
		game.spawn_enemy(kind, 80, 100, int(kind))
	}
	for frame in 0 ..< 600 {
		game.invulnerable = 999
		game.enemy_update_all(1.0 / 60.0)
		for enemy in game.enemies {
			size := game.enemy_size(enemy.kind)
			testing.expect(t, enemy.position.x >= size.x / 2 + 3.9 && enemy.position.x <= 796.1 - size.x / 2)
			testing.expect(t, enemy.position.y >= 70 + size.y / 2 - 0.1 && enemy.position.y <= 550.1 - size.y / 2)
			testing.expect(t, !math.is_nan(enemy.position.x) && !math.is_nan(enemy.position.y))
		}
	}
	testing.expect(t, game.load_campaign_json(string(game.DEFAULT_CAMPAIGN)))
}
