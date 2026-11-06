package main

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import rl "vendor:raylib"

Spawn_Config :: struct { kind: string, x, y: f32, hp: int, delay: f32 }
Wave_Config :: struct { enemies: []Spawn_Config }
Sector_Config :: struct {
    name, tip: string,
    bullet_speed, fire_interval, motion_scale: f32,
    variation: f32,
    waves: []Wave_Config,
}
Campaign_Config :: struct { version: int, seed: u32, sectors: []Sector_Config }
DEFAULT_CAMPAIGN :: #load("assets/campaign.json")
MAX_CONFIG_BYTES :: 256*1024
campaign: Campaign_Config
campaign_arenas: [2]mem.Arena
campaign_storage: [2][8*1024*1024]byte
campaign_slot: int
campaign_ready: bool
editor_status_buffer: [240]byte
editor_status_length: int

set_editor_status :: proc(text: string) {
    editor_status_length = copy(editor_status_buffer[:],transmute([]byte)text)
}
kind_from_name :: proc(name: string) -> (Enemy_Kind, bool) {
    switch name {
    case "Scout": return .Scout,true
    case "Weaver": return .Weaver,true
    case "Diver": return .Diver,true
    case "Tank": return .Tank,true
    case "Spitter": return .Spitter,true
    case "Boss": return .Boss,true
    }
    return .Scout,false
}
kind_name :: proc(k: Enemy_Kind) -> string {
    switch k {
    case .Scout: return "Scout"
    case .Weaver: return "Weaver"
    case .Diver: return "Diver"
    case .Tank: return "Tank"
    case .Spitter: return "Spitter"
    case .Boss: return "Boss"
    }
    return "Scout"
}
validate_campaign :: proc(c: Campaign_Config) -> string {
    if c.version != 1 { return "Unsupported version: use version 1." }
    if len(c.sectors) < 1 || len(c.sectors) > 32 { return "Use 1 to 32 sectors." }
    for sector, si in c.sectors {
        if len(sector.name) < 1 || len(sector.name) > 32 { return fmt.tprintf("Sector %d: name must be 1-32 characters.",si+1) }
        if len(sector.tip) > 85 { return fmt.tprintf("Sector %d: tip is too long (maximum 85).",si+1) }
        // ASCII prevents invisible/control characters and fits raylib's built-in font.
        for ch in sector.name { if ch < 32 || ch > 126 { return "Sector names must use printable ASCII." } }
        for ch in sector.tip { if ch < 32 || ch > 126 { return "Sector tips must use printable ASCII." } }
        if sector.bullet_speed < 0.5 || sector.bullet_speed > 2 ||
           sector.fire_interval < 0.5 || sector.fire_interval > 2 ||
           sector.motion_scale < 0.25 || sector.motion_scale > 2 { return fmt.tprintf("Sector %d: speed/fire/motion multipliers out of range.",si+1) }
        if sector.variation < 0 || sector.variation > 1.5 { return "Variation must be 0-1.5 (0 means default)." }
        if len(sector.waves) < 1 || len(sector.waves) > 8 { return fmt.tprintf("Sector %d: use 1 to 8 waves.",si+1) }
        for wave, wi in sector.waves {
            if len(wave.enemies) < 1 || len(wave.enemies) > 64 { return fmt.tprintf("Sector %d wave %d: use 1 to 64 enemies.",si+1,wi+1) }
            bosses := 0
            for spawn, ei in wave.enemies {
                kind,ok := kind_from_name(spawn.kind)
                if !ok { return fmt.tprintf("Sector %d wave %d enemy %d: unknown kind.",si+1,wi+1,ei+1) }
                if kind == .Boss { bosses += 1 }
                if spawn.x < 80 || spawn.x > 720 || spawn.y < 100 || spawn.y > 260 ||
                   spawn.hp < 0 || spawn.hp > 200 || spawn.delay < 0 || spawn.delay > 30 {
                    return fmt.tprintf("Sector %d wave %d enemy %d: invalid position, HP or delay.",si+1,wi+1,ei+1)
                }
            }
            if bosses > 1 { return "Use at most one boss per wave." }
        }
    }
    return ""
}

load_campaign_json :: proc(text: string) -> bool {
    if len(text) > MAX_CONFIG_BYTES { set_editor_status("Campaign too large: maximum 256 KiB."); return false }
    target := (campaign_slot+1)%2
    mem.arena_init(&campaign_arenas[target],campaign_storage[target][:])
    allocator := mem.arena_allocator(&campaign_arenas[target])
    next: Campaign_Config
    err := json.unmarshal_string(text,&next,allocator=allocator)
    if err != nil { set_editor_status(fmt.tprintf("Invalid JSON: %v",err)); return false }
    error := validate_campaign(next)
    if len(error) != 0 { set_editor_status(error); return false }
    // Commit only once parsing and validation succeeded. The old arena remains
    // alive until the next load, so failed imports never damage live levels.
    campaign = next; campaign_slot = target; campaign_ready = true
    set_editor_status("Campaign loaded. E: editor. Export JSON to keep a portable copy.")
    return true
}
ensure_campaign :: proc() {
    if !campaign_ready { assert(load_campaign_json(string(DEFAULT_CAMPAIGN))) }
}
load_campaign_files :: proc() {
    ensure_campaign()
    if rl.FileExists("assets/campaign.json") {
        text := rl.LoadFileText("assets/campaign.json")
        if text != nil { load_campaign_json(string(cstring(text))); rl.UnloadFileText(text) }
    }
    when ODIN_OS != .JS {
        if rl.FileExists("campaign.custom.json") {
            text := rl.LoadFileText("campaign.custom.json")
            if text != nil { load_campaign_json(string(cstring(text))); rl.UnloadFileText(text) }
        }
    }
}
campaign_json :: proc() -> []byte {
    data,err := json.marshal(campaign,{pretty=true,use_spaces=true},allocator=context.temp_allocator)
    if err != nil { set_editor_status("Could not serialize campaign."); return nil }
    return data
}
active_sector :: proc() -> ^Sector_Config {
    return &campaign.sectors[clamp(level-1,0,len(campaign.sectors)-1)]
}
sector_name :: proc(n: int) -> cstring {
    ensure_campaign()
    return fmt.ctprintf("%02d / %s",n,campaign.sectors[clamp(n-1,0,len(campaign.sectors)-1)].name)
}
sector_tip :: proc(n: int) -> cstring {
    return fmt.ctprintf("%s",campaign.sectors[clamp(n-1,0,len(campaign.sectors)-1)].tip)
}
spawn_wave :: proc() {
    ensure_campaign()
    clear(&enemies); clear(&lasers); clear(&pickups)
    sector := active_sector()
    for spawn,i in sector.waves[wave-1].enemies {
        kind,_ := kind_from_name(spawn.kind)
        spawn_enemy(kind,spawn.x,spawn.y,i)
        e := &enemies[len(enemies)-1]
        e.delay = spawn.delay
        if spawn.hp > 0 { e.hp = spawn.hp; e.max_hp = spawn.hp }
    }
}
