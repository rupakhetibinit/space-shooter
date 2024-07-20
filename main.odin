package main
import "core:fmt"
import rl "vendor:raylib"

TEXTURE_SIZE :: 16


main :: proc() {
	rl.InitWindow(800, 600, "Space shooter")

	lasers := [dynamic]Laser{}

	lastPositionUpdate := 0.0
	delayBeforeMoving := 0.003
	shipSpeed: f32 = 1.5
	lastLaserDrawTime := 0.0
	lastlaserShootTime := 0.0

	shipTexture := rl.LoadTexture("assets/ship.png")
	imageBackground := rl.LoadTexture("assets/bg.png")
	laserTexture := rl.LoadTexture("assets/laser.png")
	shipPosition: rl.Vector2 = {400 - 48 / 2, 500 + 48 / 2}
	rl.SetTargetFPS(144)

	for !rl.WindowShouldClose() {
		fmt.println(len(lasers))
		rl.BeginDrawing()

		rl.DrawTexturePro(
			imageBackground,
			{0, 0, f32(imageBackground.width), f32(imageBackground.height)},
			{0, 0, 800, 600},
			{0, 0},
			0,
			rl.WHITE,
		)

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


		rl.EndDrawing()

		if (rl.IsKeyDown(rl.KeyboardKey.SPACE)) {
			if (rl.GetTime() - lastlaserShootTime > 0.4) {
				laser := Laser {
					position = {shipPosition.x + 8, shipPosition.y - 24},
					texture  = laserTexture,
				}
				append(&lasers, laser)
				lastlaserShootTime = rl.GetTime()
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
	texture:  rl.Texture2D,
	position: rl.Vector2,
}
