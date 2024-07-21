package main
import "core:fmt"
import rl "vendor:raylib"

TEXTURE_SIZE :: 16


main :: proc() {
	rl.InitWindow(800, 600, "Space shooter")
	rl.InitAudioDevice()

	lasers := [dynamic]Laser{}
	enemies := [dynamic]Enemy{}

	lastPositionUpdate := 0.0
	delayBeforeMoving := 0.003
	shipSpeed: f32 = 1.5
	lastLaserDrawTime := 0.0
	lastlaserShootTime := 0.0

	shipTexture := rl.LoadTexture("assets/ship.png")
	imageBackground := rl.LoadTexture("assets/bg.png")
	laserTexture := rl.LoadTexture("assets/laser.png")
	enemyTexture := rl.LoadTexture("assets/enemy.png")
	shipPosition: rl.Vector2 = {400 - 48 / 2, 500 + 48 / 2}
	framesCounter := 0
	currentFrame := 0
	currentAnimationFrame := 0
	sourceRec: rl.Rectangle = {0, 0, f32(enemyTexture.width / 6), f32(enemyTexture.height)}

	// Sound loading
	laserSound := rl.LoadSound("assets/laser.wav")
	defer rl.UnloadSound(laserSound)

	rl.SetTargetFPS(144)

	for !rl.WindowShouldClose() {
		framesCounter += 1
		rl.BeginDrawing()

		for i in 1 ..= 10 {
		}

		rl.DrawTexturePro(
			imageBackground,
			{0, 0, f32(imageBackground.width), f32(imageBackground.height)},
			{0, 0, 800, 600},
			{0, 0},
			0,
			rl.WHITE,
		)
		rl.DrawFPS(10, 10)


		if (framesCounter >= (144 / 8)) {
			framesCounter = 0
			currentAnimationFrame += 1
			currentFrame += 1

			if (currentAnimationFrame > 5) {currentAnimationFrame = 0}

			sourceRec.x = f32(currentAnimationFrame * int(enemyTexture.width / 6))
		}


		rl.DrawTexturePro(
			enemyTexture,
			sourceRec,
			{400, 50, f32(enemyTexture.width / 6) * 4, f32(enemyTexture.height) * 4},
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
	texture:  rl.Texture2D,
	position: rl.Vector2,
}

Enemy :: struct {
	texture:               rl.Texture2D,
	position:              rl.Vector2,
	lastUpdateTime:        i32,
	currentAnimationFrame: u8,
}

drawAnimatedEnemy :: proc(enemy: ^Enemy) {

	// enemy.position.x = currentAnimationFrame * enemy.texture.width / 6

	//         if (framesCounter >= (144/8))
	//       {
	//           framesCounter = 0;
	//           currentFrame++;

	//           if (currentFrame > 5) currentFrame = 0;

	//           frameRec.x = (float)currentFrame*(float)scarfy.width/6;
	//       }

	// rl.DrawTexturePro(
	// 	enemyTexture,
	// 	{0, 0, f32(enemyTexture.width / 6), f32(enemyTexture.height)},
	// 	{400, 200, f32(enemyTexture.width / 6) * 4, f32(enemyTexture.height) * 4},
	// 	{0, 0},
	// 	0,
	// 	rl.WHITE,
	// )
}
