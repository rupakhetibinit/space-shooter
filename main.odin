package main
import "core:fmt"
import rl "vendor:raylib"

TEXTURE_SIZE :: 16


main :: proc() {
	rl.InitWindow(800, 600, "Space shooter")
	rl.InitAudioDevice()

	lasers := [dynamic]Laser{}
	enemies := [dynamic]Enemy{}
	explosions := [dynamic]Explosion{}

	lastPositionUpdate := 0.0
	delayBeforeMoving := 0.003
	shipSpeed: f32 = 1.5
	lastLaserDrawTime := 0.0
	lastlaserShootTime := 0.0

	shipTexture := rl.LoadTexture("assets/ship.png")
	imageBackground := rl.LoadTexture("assets/bg.png")
	laserTexture := rl.LoadTexture("assets/laser.png")
	enemyTexture := rl.LoadTexture("assets/enemy.png")
	explosionTexture := rl.LoadTexture("assets/explosion.png")
	shipPosition: rl.Vector2 = {400 - 48 / 2, 500 + 48 / 2}
	sourceRec: rl.Rectangle = {0, 0, f32(enemyTexture.width / 6), f32(enemyTexture.height)}

	enemy := Enemy {
		texture               = enemyTexture,
		position              = {400, 50},
		animationTimer        = 0,
		currentAnimationFrame = 0,
	}
	// Sound loading
	laserSound := rl.LoadSound("assets/laser.wav")
	defer rl.UnloadSound(laserSound)
	explosionSound := rl.LoadSound("assets/explosion.wav")
	defer rl.UnloadSound(explosionSound)

	rl.SetTargetFPS(144)

	for !rl.WindowShouldClose() {
		rl.BeginDrawing()

		// Draw BG first
		rl.DrawTexturePro(
			imageBackground,
			{0, 0, f32(imageBackground.width), f32(imageBackground.height)},
			{0, 0, 800, 600},
			{0, 0},
			0,
			rl.WHITE,
		)

		// Draw FPS
		rl.DrawFPS(10, 10)

		// Draw Enemy
		drawAnimatedEnemy(&enemy)
		updateAnimatedEnemy(&enemy)

		// Draw Ship
		rl.DrawTexturePro(
			shipTexture,
			{16, 0, 16, 16},
			{shipPosition.x, shipPosition.y, 48, 48},
			{0, 0},
			0,
			rl.WHITE,
		)

		for &laser, i in lasers {
			updateLaser(&laser)
			drawLaser(laser)
			if (laser.position.y < 0) {
				unordered_remove(&lasers, i)
			}
		}

		for &laser in lasers {
			if (laser.hit_enemy) {
				continue
			}
			if rl.CheckCollisionRecs(
				{
					laser.position.x,
					laser.position.y,
					f32(laser.texture.width),
					f32(laser.texture.height),
				},
				{400, 50, f32(enemyTexture.width / 6) * 4, f32(enemyTexture.height) * 4},
			) {
				explosion := Explosion {
					texture  = explosionTexture,
					position = {400 - 20, 50 - f32(explosionTexture.height / 2)},
				}
				laser.hit_enemy = true
				append(&explosions, explosion)
				rl.PlaySound(explosionSound)
			}
		}

		for &explosion, i in explosions {
			drawExplosion(&explosion)
			updateExplosion(&explosion)

			if (explosion.currentAnimationFrame > 3) {
				unordered_remove(&explosions, i)
			}

		}

		rl.EndDrawing()

		if (rl.IsKeyDown(rl.KeyboardKey.SPACE)) {
			if (rl.GetTime() - lastlaserShootTime > 0.4) {
				laser := Laser {
					position = {shipPosition.x + 8, shipPosition.y - 24},
					texture  = laserTexture,
				}
				append(&lasers, laser)
				lastlaserShootTime = rl.GetTime()
				rl.PlaySound(laserSound)
			}
		}

		if rl.IsKeyDown(rl.KeyboardKey.LEFT) {
			if rl.GetTime() - lastPositionUpdate > delayBeforeMoving {
				shipPosition.x = shipPosition.x - shipSpeed
				lastPositionUpdate = rl.GetTime()
				if (shipPosition.x < 0) {
					shipPosition.x = 0
				}
			}
		}

		if (rl.IsKeyDown(rl.KeyboardKey.ESCAPE)) {
			rl.CloseWindow()
		}

		if rl.IsKeyDown(rl.KeyboardKey.RIGHT) {
			if rl.GetTime() - lastPositionUpdate > delayBeforeMoving {
				shipPosition.x = shipPosition.x + shipSpeed
				lastPositionUpdate = rl.GetTime()
				if (shipPosition.x > 800 - 48) {
					shipPosition.x = 800 - 48
				}
			}
		}
	}

	rl.CloseWindow()
}

drawLaser :: proc(laser: Laser) {
	rl.DrawTextureEx(laser.texture, {laser.position.x, laser.position.y}, 0, 2, rl.WHITE)
}

updateLaser :: proc(laser: ^Laser) {
	laser.position.y -= 1.6
}

Laser :: struct {
	texture:   rl.Texture2D,
	position:  rl.Vector2,
	hit_enemy: bool,
}

Enemy :: struct {
	texture:               rl.Texture2D,
	position:              rl.Vector2,
	lastUpdateTime:        i32,
	animationTimer:        f32,
	currentAnimationFrame: u8,
}

drawAnimatedEnemy :: proc(enemy: ^Enemy) {
	sourceRec: rl.Rectangle = {
		f32(int(enemy.texture.width / 6) * int(enemy.currentAnimationFrame)),
		0,
		f32(enemy.texture.width / 6),
		f32(enemy.texture.height),
	}

	rl.DrawTexturePro(
		enemy.texture,
		sourceRec,
		{
			enemy.position.x,
			enemy.position.y,
			f32(enemy.texture.width / 6) * 4,
			f32(enemy.texture.height) * 4,
		},
		{0, 0},
		0,
		rl.WHITE,
	)
}

updateAnimatedEnemy :: proc(enemy: ^Enemy) {
	enemy.animationTimer += rl.GetFrameTime()
	if (enemy.animationTimer > f32(1 / 8.0)) {
		enemy.animationTimer = 0
		enemy.currentAnimationFrame += 1
	}
}

Explosion :: struct {
	position:              rl.Vector2,
	texture:               rl.Texture2D,
	currentAnimationFrame: u8,
	animationTimer:        f32,
}

drawExplosion :: proc(explosion: ^Explosion) {
	sourceRec: rl.Rectangle = {
		f32(int(explosion.currentAnimationFrame) * int(explosion.texture.width / 6)),
		0,
		f32(explosion.texture.width / 6),
		f32(explosion.texture.height),
	}

	rl.DrawTexturePro(
		explosion.texture,
		sourceRec,
		rl.Rectangle {
			explosion.position.x,
			explosion.position.y,
			f32(explosion.texture.width / 6) * 6,
			f32(explosion.texture.height) * 6,
		},
		{0, 0},
		0,
		rl.WHITE,
	)
}

updateExplosion :: proc(explosion: ^Explosion) {
	explosion.animationTimer += rl.GetFrameTime()
	if (explosion.animationTimer > 0.1) {
		explosion.animationTimer = 0
		explosion.currentAnimationFrame += 1
		if (explosion.currentAnimationFrame > 6) {
			explosion.currentAnimationFrame = 0
		}
	}
}
