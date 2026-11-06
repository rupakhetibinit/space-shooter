package main

import rl "vendor:raylib"

Enemy_Mode :: enum {
    Patrol,
    Windup,
    Dive,
    Return,
}

Motion_Profile :: struct {
    radius: rl.Vector2,
    frequency: f32,
    speed: f32,
    acceleration: f32,
}

ATTACK_WARNING :: f32(0.70)
DIVE_WARNING :: f32(0.85)
ENEMY_STEP :: f32(1.0 / 120.0)

motion_profile :: proc(kind: Enemy_Kind) -> Motion_Profile {
    switch kind {
    case .Scout:
        return {{48, 19}, 0.34, 75, 210}
    case .Weaver:
        return {{86, 35}, 0.46, 120, 320}
    case .Diver:
        return {{60, 22}, 0.40, 110, 300}
    case .Tank:
        return {{30, 12}, 0.23, 45, 110}
    case .Spitter:
        return {{62, 27}, 0.34, 85, 230}
    case .Boss:
        return {{210, 28}, 0.20, 125, 210}
    }
    return {}
}

sector_variation :: proc() -> f32 {
    value := active_sector().variation
    if value == 0 {
        return 0.75 // Older version-1 campaign files keep working.
    }
    return value
}

enemy_behavior_init :: proc(e: ^Enemy, index: int) {
    campaign_seed := campaign.seed
    if campaign_seed == 0 {
        campaign_seed = 1337
    }
    e.behavior_seed = noise_hash(campaign_seed ~ u32(level)*0x85ebca6b ~ u32(wave)*0xc2b2ae35 ~ u32(index+1))
    e.cooldown = 1.25 + noise_unit(e.behavior_seed, 1)*1.35
    e.maneuver_timer = 2.0 + noise_unit(e.behavior_seed, 2)*2.5
    e.velocity = {}
    e.mode = .Patrol
    e.aim_locked = false
}

enemy_patrol_target :: proc(e: ^Enemy) -> rl.Vector2 {
    profile := motion_profile(e.kind)
    t := e.age * active_sector().motion_scale * profile.frequency
    variation := sector_variation()
    phase := noise_unit(e.behavior_seed, 3)*32.0
    x := noise_wander(t + phase, e.behavior_seed)
    y := noise_wander(t + phase + 43.7, e.behavior_seed ~ 0xa511e9b3)
    // Anchor-relative noise cannot accumulate into an unbounded random walk.
    target := e.home + rl.Vector2{x*profile.radius.x, y*profile.radius.y}*variation
    size := enemy_size(e.kind)
    target.x = clamp(target.x, size.x/2+14, 786-size.x/2)
    target.y = clamp(target.y, 82+size.y/2, 285-size.y/2)
    return target
}

enemy_steer :: proc(e: ^Enemy, target: rl.Vector2, separation: rl.Vector2, dt: f32) {
    profile := motion_profile(e.kind)
    scale := active_sector().motion_scale
    speed := profile.speed * scale
    acceleration := profile.acceleration * scale * scale
    if e.aim_locked {
        speed *= 0.45 // Settle while the player reads the attack tell.
    }
    desired_velocity := vector_limit((target-e.position)*(3.0*scale) + separation, speed)
    steering := vector_limit((desired_velocity-e.velocity)*(5.0*scale), acceleration)
    e.velocity = vector_limit(e.velocity + steering*dt, speed)
    e.position += e.velocity*dt
}

enemy_separation :: proc(index: int, positions: []rl.Vector2) -> rl.Vector2 {
    e := &enemies[index]
    if e.kind == .Boss || e.mode != .Patrol {
        return {}
    }
    force: rl.Vector2
    for other, j in positions {
        if j == index || enemies[j].delay > 0 || enemies[j].kind == .Boss || enemies[j].mode != .Patrol {
            continue
        }
        difference := positions[index] - other
        distance := vector_length(difference)
        if distance > 0.01 && distance < 58 {
            force += difference * ((58-distance)/distance)
        }
    }
    return vector_limit(force*1.5, 42)
}

enemy_begin_dive :: proc(e: ^Enemy) {
    e.mode = .Windup
    e.mode_time = 0
    e.dive_from = e.position
    // Commit now. Neither the warning nor the dive tracks later player input.
    offset := (noise_unit(e.behavior_seed, 30+e.maneuver_index)*2.0-1.0)*38.0
    e.dive_to = {clamp(shipPosition.x+20+offset, 45, 755), clamp(shipPosition.y+20, 360, 520)}
    e.dive_bend = (noise_unit(e.behavior_seed, 70+e.maneuver_index)*2.0-1.0)*90.0
    e.dive_duration = 2.0 + noise_unit(e.behavior_seed, 90+e.maneuver_index)*0.35
    e.aim_locked = false
}

enemy_move :: proc(e: ^Enemy, separation: rl.Vector2, dt: f32) {
    target := enemy_patrol_target(e)
    switch e.mode {
    case .Patrol:
        enemy_steer(e, target, separation, dt)
        if e.kind == .Diver {
            e.maneuver_timer -= dt
            if e.maneuver_timer <= 0 {
                enemy_begin_dive(e)
            }
        }
    case .Windup:
        e.mode_time += dt
        enemy_steer(e, e.dive_from, {}, dt)
        if e.mode_time >= DIVE_WARNING {
            e.mode = .Dive
            e.mode_time = 0
            e.dive_from = e.position
        }
    case .Dive:
        e.mode_time += dt
        t := clamp(e.mode_time/e.dive_duration, 0, 1)
        p1 := e.dive_from + rl.Vector2{e.dive_bend, 145}
        p2 := e.dive_to + rl.Vector2{-e.dive_bend*0.4, -110}
        previous := e.position
        e.position = curve_bezier(e.dive_from, p1, p2, e.dive_to, noise_smooth(t))
        if dt > 0 {
            e.velocity = (e.position-previous)/dt
        }
        if t >= 1 {
            e.mode = .Return
            e.mode_time = 0
            e.velocity = {}
        }
    case .Return:
        e.mode_time += dt
        enemy_steer(e, target, {}, dt)
        if vector_length(target-e.position) < 18 || e.mode_time > 4.5 {
            e.mode = .Patrol
            e.maneuver_index += 1
            e.maneuver_timer = 2.4 + noise_unit(e.behavior_seed, 120+e.maneuver_index)*2.6
            e.cooldown = max(e.cooldown, ATTACK_WARNING+0.4)
        }
    }
}

enemy_fire_interval :: proc(e: ^Enemy) -> f32 {
    base: f32 = 2.8
    switch e.kind {
    case .Scout: base = 3.0
    case .Weaver: base = 2.8
    case .Diver: base = 3.2
    case .Tank: base = 3.5
    case .Spitter: base = 3.0
    case .Boss:
        base = 1.7
        if e.hp <= e.max_hp/2 {
            base = 1.25
        }
    }
    variation := min(sector_variation(), 1.5)
    jitter := (noise_unit(e.behavior_seed, 200+e.shot_index)*2.0-1.0)*0.18*variation
    interval := base*active_sector().fire_interval*(1.0+jitter)
    // Every shot still has a full warning, even at maximum editor difficulty.
    return max(ATTACK_WARNING+0.25, interval)
}

enemy_add_shot :: proc(origin, velocity: rl.Vector2, radius: f32) {
    shot := Shot{
        position = origin,
        velocity = velocity,
        radius = radius,
        friendly = false,
    }
    append(&lasers, shot)
}

fire_enemy :: proc(e: ^Enemy) {
    size := enemy_size(e.kind)
    origin := e.position + rl.Vector2{0, size.y/2}
    speed := f32(135+min(level,5)*12)*active_sector().bullet_speed

    switch e.kind {
    case .Scout:
        enemy_add_shot(origin, {0, speed}, 5)

    case .Weaver, .Tank, .Diver:
        target := shipPosition + rl.Vector2{20, 20}
        if e.aim_locked {
            target = e.aim_target
        }
        direction := target-origin
        length := vector_length(direction)
        if length > 0 {
            direction /= length
        } else {
            direction = {0, 1}
        }
        enemy_add_shot(origin, direction*speed, 6)

    case .Spitter:
        drift := noise_wander(e.age*0.3, e.behavior_seed)*16
        for column in -1..=1 {
            enemy_add_shot(origin, {f32(column)*70+drift, speed}, 5)
        }

    case .Boss:
        count := 5
        enraged := e.hp <= e.max_hp/2
        if enraged {
            count = 7
        }
        drift := noise_wander(e.age*0.2, e.behavior_seed)*18
        for column in 0..<count {
            enemy_add_shot(origin, {f32(column-count/2)*48+drift, speed}, 6)
        }
        if enraged {
            enemy_add_shot(origin+{-54, -20}, {0, 245}, 5)
            enemy_add_shot(origin+{54, -20}, {0, 245}, 5)
        }
    }
}

enemy_update_weapon :: proc(e: ^Enemy, dt: f32) {
    if e.mode != .Patrol {
        return
    }
    e.cooldown -= dt
    if !e.aim_locked && e.cooldown <= ATTACK_WARNING {
        e.aim_target = shipPosition + rl.Vector2{20,20}
        e.aim_locked = true
        // Never shorten a tell when a large frame crosses its start.
        e.cooldown = ATTACK_WARNING
    }
    if e.aim_locked && e.cooldown <= 0 {
        fire_enemy(e)
        e.shot_index += 1
        e.aim_locked = false
        e.cooldown = enemy_fire_interval(e)
    }
}

enemy_update_all :: proc(dt: f32) {
    remaining := dt
    for remaining > 0 {
        h := min(remaining, ENEMY_STEP)
        remaining -= h
        // Read a snapshot, so separation is independent of array update order.
        snapshot: [64]rl.Vector2
        for e, i in enemies {
            snapshot[i] = e.position
        }
        for &e, i in enemies {
            if e.delay > 0 {
                e.delay = max(0, e.delay-h)
                continue
            }
            e.age += h
            e.hit_flash = max(0, e.hit_flash-h)
            separation := enemy_separation(i, snapshot[:len(enemies)])
            enemy_move(&e, separation, h)
            enemy_update_weapon(&e, h)
            size := enemy_size(e.kind)
            e.position.x = clamp(e.position.x, size.x/2+4, 796-size.x/2)
            e.position.y = clamp(e.position.y, 70+size.y/2, 550-size.y/2)
            if rl.CheckCollisionRecs(ship_rect(), enemy_rect(e)) {
                hurt_player()
            }
        }
    }
}

// Intent rendering is separate from simulation: drawing never consumes RNG.
enemy_draw_intent :: proc(e: Enemy) {
    if e.mode == .Windup {
        alpha := u8(90+130*clamp(e.mode_time/DIVE_WARNING, 0, 1))
        rl.DrawLineEx(e.position, e.dive_to, 1.5, {255,125,126,alpha})
        rl.DrawCircleLines(i32(e.dive_to.x), i32(e.dive_to.y), 19, {255,125,126,alpha})
        rl.DrawCircleLines(i32(e.position.x), i32(e.position.y), 29, {255,205,170,255})
    }
    if !e.aim_locked {
        return
    }
    progress := clamp(1-e.cooldown/ATTACK_WARNING, 0, 1)
    size := enemy_size(e.kind)
    origin := e.position + rl.Vector2{0,size.y/2}
    color := rl.Color{255,211,143,u8(80+150*progress)}
    rl.DrawCircleLines(i32(e.position.x), i32(e.position.y), size.x*0.65+(1-progress)*9, color)
    if e.kind == .Weaver || e.kind == .Tank || e.kind == .Diver {
        // Broken guide line: a warning marker, not a damaging laser.
        for i in 0..<10 {
            a := f32(i)/10.0
            b := min(1,a+0.045)
            rl.DrawLineEx(origin+(e.aim_target-origin)*a, origin+(e.aim_target-origin)*b, 1, color)
        }
        rl.DrawCircleLines(i32(e.aim_target.x), i32(e.aim_target.y), 10, color)
    }
}
