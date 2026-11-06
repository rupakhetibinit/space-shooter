package main

import "core:fmt"
import "core:mem"
import rl "vendor:raylib"

editor_open, preview_mode, editor_dirty: bool
editor_sector, editor_wave, editor_selected: int
editor_tool: Enemy_Kind
editor_dragging, editor_name_edit, editor_name_replace: bool
editor_name_buffer: [33]byte
editor_name_length: int

when ODIN_OS == .JS {
    foreign import editor_js "env.o"
    foreign editor_js {
        browser_store :: proc "c" (ptr: rawptr, size: int) -> i32 ---
        browser_export :: proc "c" (ptr: rawptr, size: int) ---
        browser_pick :: proc "c" () ---
    }
}
editor_sector_data :: proc() -> ^Sector_Config { return &campaign.sectors[editor_sector] }
editor_wave_data :: proc() -> ^Wave_Config { return &editor_sector_data().waves[editor_wave] }
editor_normalize :: proc() {
    editor_sector = clamp(editor_sector,0,len(campaign.sectors)-1)
    editor_wave = clamp(editor_wave,0,len(editor_sector_data().waves)-1)
    editor_selected = clamp(editor_selected,-1,len(editor_wave_data().enemies)-1)
}
compact_edit :: proc() {
    editor_dirty = true
    data := campaign_json()
    if len(data) > 0 && load_campaign_json(string(data)) { editor_dirty = true; set_editor_status("Edited. Save locally or export JSON to keep this campaign.") }
}
append_config :: proc(items: []$T, item: T) -> []T {
    result := make([]T,len(items)+1,mem.arena_allocator(&campaign_arenas[campaign_slot]))
    copy(result,items); result[len(items)] = item
    return result
}
remove_config :: proc(items: []$T, index: int) -> []T {
    for i in index..<len(items)-1 { items[i] = items[i+1] }
    return items[:len(items)-1]
}
toggle_editor :: proc() {
    if editor_name_edit { set_editor_status("Press Enter to finish naming this sector first."); return }
    if editor_open {
        editor_open = false; reset_round()
    } else {
        ensure_campaign(); editor_open = true
        editor_sector = clamp(level-1,0,len(campaign.sectors)-1)
        editor_wave = clamp(wave-1,0,len(editor_sector_data().waves)-1)
        editor_selected = -1; editor_dragging = false
    }
}
editor_playtest :: proc() {
    reset_round()
    level = editor_sector+1; wave = editor_wave+1
    preview_mode = true; editor_open = false
    phase = .Playing; spawn_wave(); invulnerable = 1.6
}
editor_save :: proc(download: bool) {
    data := campaign_json()
    if len(data) == 0 { return }
    if len(data) > MAX_CONFIG_BYTES { set_editor_status("Campaign exceeds 256 KiB. Delete some content before saving/exporting."); return }
    when ODIN_OS == .JS {
        if download { browser_export(raw_data(data),len(data)); set_editor_status("JSON exported. Keep the downloaded file as your backup.") }
        else if browser_store(raw_data(data),len(data)) != 0 { set_editor_status("Saved in this browser. It will reload on your next visit.") }
        else { set_editor_status("Browser storage unavailable. Use Export JSON instead."); return }
    } else {
        filename: cstring = "campaign.custom.json"
        if download { filename = "campaign.export.json" }
        if !rl.SaveFileText(filename,cast([^]byte)fmt.ctprintf("%s",string(data))) { set_editor_status("Could not save campaign file."); return }
        set_editor_status(fmt.tprintf("Saved %s in the project folder.",filename))
    }
    editor_dirty = false
}
editor_import :: proc() {
    when ODIN_OS == .JS { browser_pick() }
    else {
        if !rl.FileExists("campaign.import.json") { set_editor_status("Put JSON in campaign.import.json, then click Import. Or drop a JSON file here."); return }
        text := rl.LoadFileText("campaign.import.json")
        if text != nil {
            if load_campaign_json(string(cstring(text))) { editor_sector=0; editor_wave=0; editor_selected = -1; editor_dirty = true }
            rl.UnloadFileText(text)
        }
    }
}
editor_button :: proc(rect: rl.Rectangle, label: cstring, accent := false) -> bool {
    hover := rl.CheckCollisionPointRec(rl.GetMousePosition(),rect)
    color := rl.Color{32,44,65,255}
    if hover { color = {52,72,97,255} }
    if accent { color = {126,169,87,255} }
    rl.DrawRectangleRec(rect,color)
    rl.DrawRectangleLinesEx(rect,1,{73,99,122,255})
    rl.DrawText(label,i32(rect.x)+8,i32(rect.y)+9,13,rl.WHITE)
    return !editor_name_edit && hover && rl.IsMouseButtonPressed(.LEFT)
}
editor_delete_enemy :: proc(index: int) {
    w := editor_wave_data()
    if len(w.enemies) == 1 { set_editor_status("Keep one enemy per wave. Select another kind to replace it, or delete the wave."); return }
    w.enemies = remove_config(w.enemies,index)
    editor_selected = -1; compact_edit()
}
update_editor :: proc() {
    editor_normalize()
    if editor_name_edit {
        for ch := rl.GetCharPressed(); ch != 0; ch = rl.GetCharPressed() {
            if ch >= 32 && ch <= 126 {
                if editor_name_replace { editor_name_length=0; editor_name_replace=false }
                if editor_name_length<32 { editor_name_buffer[editor_name_length] = byte(ch); editor_name_length += 1 }
            }
        }
        when ODIN_OS == .JS {
            // The browser shell suppresses Space's page-scroll default, which
            // also suppresses its character event. Read that key directly.
            if rl.IsKeyPressed(.SPACE) && editor_name_length<32 {
                if editor_name_replace { editor_name_length=0; editor_name_replace=false }
                editor_name_buffer[editor_name_length]=' '; editor_name_length+=1
            }
        }
        if rl.IsKeyPressed(.BACKSPACE) || rl.IsKeyPressedRepeat(.BACKSPACE) {
            if editor_name_replace { editor_name_length=0; editor_name_replace=false }
            else if editor_name_length>0 { editor_name_length-=1 }
        }
        if rl.IsKeyPressed(.ENTER) && editor_name_length > 0 {
            editor_sector_data().name = string(editor_name_buffer[:editor_name_length])
            compact_edit(); editor_name_edit = false
        }
        return
    }
    if rl.IsKeyPressed(.ONE) { editor_tool = .Scout }
    if rl.IsKeyPressed(.TWO) { editor_tool = .Weaver }
    if rl.IsKeyPressed(.THREE) { editor_tool = .Diver }
    if rl.IsKeyPressed(.FOUR) { editor_tool = .Tank }
    if rl.IsKeyPressed(.FIVE) { editor_tool = .Spitter }
    if rl.IsKeyPressed(.SIX) { editor_tool = .Boss }
    if rl.IsKeyPressed(.F5) { editor_playtest(); return }
    when ODIN_OS != .JS {
        if rl.IsFileDropped() {
            files := rl.LoadDroppedFiles()
            if files.count > 0 {
                text := rl.LoadFileText(files.paths[0])
                if text != nil {
                    if load_campaign_json(string(cstring(text))) { editor_sector=0; editor_wave=0; editor_selected = -1; editor_dirty = true }
                    rl.UnloadFileText(text)
                }
            }
            rl.UnloadDroppedFiles(files)
        }
    }
    mouse := rl.GetMousePosition()
    world := rl.Vector2{f32(int((mouse.x+10)/20)*20),f32(int((mouse.y-50+10)/20)*20)}
    inside := mouse.x >= 70 && mouse.x <= 730 && mouse.y >= 145 && mouse.y <= 315
    if inside && rl.IsMouseButtonPressed(.LEFT) {
        hit := -1
        for i := len(editor_wave_data().enemies)-1; i >= 0; i -= 1 {
            e := editor_wave_data().enemies[i]
            if rl.CheckCollisionPointRec(mouse,{e.x-22,e.y+28,44,44}) { hit = i; break }
        }
        if hit >= 0 { editor_selected = hit; editor_dragging = true }
        else {
            w := editor_wave_data()
            if len(w.enemies) >= 64 { set_editor_status("Wave limit: 64 enemies."); return }
            if editor_tool == .Boss {
                for spawn in w.enemies { if spawn.kind == "Boss" { set_editor_status("Only one boss per wave."); return } }
            }
            w.enemies = append_config(w.enemies,Spawn_Config{kind=kind_name(editor_tool),x=clamp(world.x,80,720),y=clamp(world.y,100,260)})
            editor_selected = len(w.enemies)-1; compact_edit()
        }
    }
    if editor_dragging && editor_selected >= 0 && rl.IsMouseButtonDown(.LEFT) {
        e := &editor_wave_data().enemies[editor_selected]
        e.x = clamp(world.x,80,720); e.y = clamp(world.y,100,260)
    }
    if editor_dragging && rl.IsMouseButtonReleased(.LEFT) { editor_dragging = false; compact_edit() }
    if inside && rl.IsMouseButtonPressed(.RIGHT) {
        for i := len(editor_wave_data().enemies)-1; i >= 0; i -= 1 {
            e := editor_wave_data().enemies[i]
            if rl.CheckCollisionPointRec(mouse,{e.x-22,e.y+28,44,44}) { editor_delete_enemy(i); break }
        }
    }
    if editor_selected >= 0 && rl.IsKeyPressed(.DELETE) { editor_delete_enemy(editor_selected) }
}

draw_editor :: proc() {
    rl.BeginDrawing(); rl.ClearBackground({9,15,28,255})
    rl.DrawText("MISSION BUILDER",16,14,24,{203,240,153,255})
    if editor_button({634,8,150,32},"PLAY CAMPAIGN",true) { editor_open=false; reset_round() }
    if editor_button({16,49,28,31},"<") { editor_sector=max(0,editor_sector-1); editor_wave=0; editor_selected = -1 }
    if editor_button({48,49,28,31},">") { editor_sector=min(len(campaign.sectors)-1,editor_sector+1); editor_wave=0; editor_selected = -1 }
    if editor_name_edit {
        rl.DrawRectangle(84,49,280,31,{48,65,84,255})
        rl.DrawText(fmt.ctprintf("%s_",string(editor_name_buffer[:editor_name_length])),92,58,14,rl.WHITE)
    } else if editor_button({84,49,280,31},fmt.ctprintf("%02d / %s",editor_sector+1,editor_sector_data().name)) {
        editor_name_edit = true; editor_name_replace = true; editor_name_length = copy(editor_name_buffer[:],transmute([]byte)editor_sector_data().name)
    }
    if editor_button({375,49,118,31},"CLONE SECTOR") {
        if len(campaign.sectors) < 32 {
            item := editor_sector_data()^; item.name = "NEW SECTOR"
            campaign.sectors = append_config(campaign.sectors,item)
            editor_sector = len(campaign.sectors)-1; editor_wave=0; editor_selected = -1; compact_edit()
        } else { set_editor_status("Campaign limit: 32 sectors.") }
    }
    rl.DrawText(fmt.ctprintf("%d SECTORS",len(campaign.sectors)),515,59,14,{139,165,190,255})
    if editor_button({16,90,28,31},"<") { editor_wave=max(0,editor_wave-1); editor_selected = -1 }
    if editor_button({48,90,28,31},">") { editor_wave=min(len(editor_sector_data().waves)-1,editor_wave+1); editor_selected = -1 }
    rl.DrawText(fmt.ctprintf("WAVE %d / %d",editor_wave+1,len(editor_sector_data().waves)),88,100,16,rl.WHITE)
    if editor_button({232,90,105,31},"NEW WAVE") {
        sector := editor_sector_data()
        if len(sector.waves)<8 {
            spawns := make([]Spawn_Config,1,mem.arena_allocator(&campaign_arenas[campaign_slot]))
            spawns[0] = {kind="Scout",x=400,y=160}
            sector.waves = append_config(sector.waves,Wave_Config{enemies=spawns})
            editor_wave=len(sector.waves)-1; editor_selected=0; compact_edit()
        } else { set_editor_status("Sector limit: 8 waves.") }
    }
    if editor_button({345,90,105,31},"CLONE WAVE") {
        sector := editor_sector_data()
        if len(sector.waves)<8 {
            sector.waves = append_config(sector.waves,editor_wave_data()^)
            editor_wave=len(sector.waves)-1; editor_selected = -1; compact_edit()
        } else { set_editor_status("Sector limit: 8 waves.") }
    }
    if editor_button({458,90,110,31},"DELETE WAVE") {
        sector := editor_sector_data()
        if len(sector.waves)>1 {
            sector.waves=remove_config(sector.waves,editor_wave); editor_wave=0; editor_selected = -1; compact_edit()
        } else { set_editor_status("Keep at least one wave in a sector.") }
    }
    if editor_button({634,90,150,31},"PLAYTEST / F5",true) { editor_playtest() }
    rl.DrawRectangle(60,128,680,208,{14,24,42,255})
    for x := 80; x <= 720; x += 20 { rl.DrawLine(i32(x),150,i32(x),310,{26,40,59,255}) }
    for y := 150; y <= 310; y += 20 { rl.DrawLine(60,i32(y),740,i32(y),{26,40,59,255}) }
    for spawn,i in editor_wave_data().enemies {
        kind,_ := kind_from_name(spawn.kind)
        e := Enemy{kind=kind,position={0,0},hp=1,max_hp=1,cooldown=1}
        rl.BeginMode2D(rl.Camera2D{offset={spawn.x,spawn.y+50},zoom=0.65})
        draw_enemy(e)
        rl.EndMode2D()
        if i == editor_selected { rl.DrawRectangleLinesEx({spawn.x-29,spawn.y+21,58,58},2,{220,249,161,255}) }
        if spawn.delay>0 { rl.DrawText(fmt.ctprintf("%.1fs",spawn.delay),i32(spawn.x)-15,i32(spawn.y)+76,11,{190,211,230,255}) }
    }
    rl.DrawText(fmt.ctprintf("%d ENEMIES  /  CLICK PLACE / DRAG MOVE / RIGHT CLICK ERASE",len(editor_wave_data().enemies)),78,324,12,{139,165,190,255})
    for kind in Enemy_Kind {
        idx := int(kind)
        label := fmt.ctprintf("%d %s",idx+1,kind_name(kind))
        if editor_button({f32(16+idx*130),348,122,32},label,kind==editor_tool) { editor_tool=kind }
    }
    if editor_selected >= 0 {
        spawn := &editor_wave_data().enemies[editor_selected]
        rl.DrawText(fmt.ctprintf("SELECTED %s",spawn.kind),16,401,14,{203,240,153,255})
        rl.DrawText(fmt.ctprintf("HP %d",spawn.hp),215,401,13,rl.WHITE)
        if editor_button({346,390,28,31},"-") { spawn.hp=max(0,spawn.hp-1); compact_edit() }
        if editor_button({378,390,28,31},"+") { spawn.hp=min(200,spawn.hp+1); compact_edit() }
        // Reacquire after compaction; previous slices belonged to the old arena.
        spawn = &editor_wave_data().enemies[editor_selected]
        rl.DrawText(fmt.ctprintf("DELAY %.1fs",spawn.delay),435,401,13,rl.WHITE)
        if editor_button({549,390,28,31},"-") { spawn.delay=max(0,spawn.delay-0.5); compact_edit() }
        spawn = &editor_wave_data().enemies[editor_selected]
        if editor_button({581,390,28,31},"+") { spawn.delay=min(30,spawn.delay+0.5); compact_edit() }
        if editor_button({634,390,150,31},"DELETE ENEMY") { editor_delete_enemy(editor_selected) }
    } else { rl.DrawText("Select an enemy to edit HP and arrival time.",16,401,14,{139,165,190,255}) }
    for i in 0..<3 {
        sector := editor_sector_data()
        factor := &sector.bullet_speed
        label: cstring = "BULLETS"
        if i==1 { factor=&sector.fire_interval; label="FIRE GAP" }
        if i==2 { factor=&sector.motion_scale; label="MOTION" }
        x := f32(16+i*263)
        rl.DrawText(fmt.ctprintf("%s %.2fx",label,factor^),i32(x),440,12,rl.WHITE)
        minimum: f32 = 0.5
        if i==2 { minimum=0.25 }
        if editor_button({x+177,429,28,31},"-") { factor^=max(minimum,factor^-0.05); compact_edit() }
        // Buttons don't overlap; only one can mutate on this frame.
        if editor_button({x+209,429,28,31},"+") { factor^=min(2,factor^+0.05); compact_edit() }
    }
    sector := editor_sector_data()
    amount := sector.variation
    if amount == 0 { amount = 0.75 }
    rl.DrawText(fmt.ctprintf("VARIATION %.2f",amount),16,470,12,{203,240,153,255})
    if editor_button({193,462,28,22},"-") { sector.variation=max(0.01,amount-0.1); compact_edit() }
    if editor_button({225,462,28,22},"+") { editor_sector_data().variation=min(1.5,amount+0.1); compact_edit() }
    rl.DrawText("steady <-> loose",282,470,12,{139,165,190,255})
    if editor_button({590,462,194,22},"NEW ROUTE SEED") {
        campaign.seed=noise_hash(campaign.seed+1)
        compact_edit()
        set_editor_status(fmt.tprintf("Route seed %d. Playtest to preview the new paths.",campaign.seed))
    }
    rl.DrawText(fmt.ctprintf("%s",string(editor_status_buffer[:min(editor_status_length,101)])),16,486,12,{174,204,231,255})
    if editor_name_edit { rl.DrawText("Type to replace the name, then press ENTER.",16,508,13,{203,240,153,255}) }
    if editor_button({16,532,140,34},"SAVE LOCALLY",true) { editor_save(false) }
    if editor_button({168,532,140,34},"EXPORT JSON") { editor_save(true) }
    if editor_button({320,532,140,34},"IMPORT JSON") { editor_import() }
    if editor_button({472,532,140,34},"DELETE SECTOR") {
        if len(campaign.sectors)>1 {
            campaign.sectors=remove_config(campaign.sectors,editor_sector); editor_sector=0;editor_wave=0;editor_selected = -1; compact_edit()
        } else { set_editor_status("Keep at least one sector.") }
    }
    rl.DrawText("E: return to campaign  /  F5: test current wave  /  1-6: palette",16,582,12,{139,165,190,255})
    if editor_dirty { rl.DrawText("UNSAVED",689,583,12,{247,189,90,255}) }
    rl.EndDrawing()
}
