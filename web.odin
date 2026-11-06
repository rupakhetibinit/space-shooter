#+build js, wasm32
package main

import "core:mem"
import "base:runtime"

// Emscripten owns the shared WebAssembly heap. Keep Odin allocations on it too.
foreign import em "env.o"
foreign em {
    malloc :: proc "c" (size: uintptr) -> rawptr ---
    free :: proc "c" (ptr: rawptr) ---
}

web_context: runtime.Context
web_temp: mem.Arena
web_temp_buffer: [1024*1024]byte

web_allocator :: proc(data: rawptr, mode: mem.Allocator_Mode, size, alignment: int,
                      old: rawptr, old_size: int, loc := #caller_location) -> ([]byte, mem.Allocator_Error) {
    switch mode {
    case .Alloc, .Alloc_Non_Zeroed, .Resize, .Resize_Non_Zeroed:
        if size == 0 {
            if old != nil { free((^rawptr)(uintptr(old)-size_of(rawptr))^) }
            return nil, nil
        }
        a := max(alignment, size_of(rawptr))
        base := malloc(uintptr(size + a - 1 + size_of(rawptr)))
        if base == nil { return nil, .Out_Of_Memory }
        addr := (uintptr(base) + uintptr(size_of(rawptr)+a-1)) & ~uintptr(a-1)
        (^rawptr)(addr-size_of(rawptr))^ = base
        bytes := mem.byte_slice(rawptr(addr), size)
        if mode == .Alloc || mode == .Resize { mem.zero(raw_data(bytes), len(bytes)) }
        if old != nil {
            copy(bytes, mem.byte_slice(old, min(size, old_size)))
            free((^rawptr)(uintptr(old)-size_of(rawptr))^)
        }
        return bytes, nil
    case .Free:
        if old != nil { free((^rawptr)(uintptr(old)-size_of(rawptr))^) }
        return nil, nil
    case .Query_Features:
        if old != nil {
            (^mem.Allocator_Mode_Set)(old)^ = {.Alloc, .Alloc_Non_Zeroed, .Resize, .Resize_Non_Zeroed, .Free, .Query_Features}
        }
        return nil, nil
    case .Free_All, .Query_Info:
        return nil, .Mode_Not_Implemented
    }
    return nil, .Mode_Not_Implemented
}

@(export)
web_start :: proc "c" () {
    context = runtime.default_context()
    context.allocator = {web_allocator, nil}
    mem.arena_init(&web_temp, web_temp_buffer[:])
    context.temp_allocator = mem.arena_allocator(&web_temp)
    web_context = context
    init_game()
}

@(export)
web_frame :: proc "c" () {
    context = web_context
    update_game()
    free_all(context.temp_allocator)
}

// Small read-only probes for browser smoke tests.
@(export)
web_ship_x :: proc "c" () -> f32 { return shipPosition.x }
@(export)
web_enemy_count :: proc "c" () -> i32 { return i32(len(enemies)) }



@(export)
web_level :: proc "c" () -> i32 { return i32(level) }
@(export)
web_wave :: proc "c" () -> i32 { return i32(wave) }
@(export)
web_shields :: proc "c" () -> i32 { return i32(shields) }
@(export)
web_score :: proc "c" () -> i32 { return i32(score) }
@(export)
web_phase :: proc "c" () -> i32 { return i32(phase) }
@(export)
web_paused :: proc "c" () -> i32 { if paused { return 1 }; return 0 }


// Explicit QA builds only: render every encounter in a real browser without
// shipping level skips or invincibility in the release.
when #config(WEB_QA, false) {
    @(export)
    web_qa_sector :: proc "c" (sector, round: i32) {
        context = web_context
        reset_round()
        level = clamp(int(sector),1,len(campaign.sectors))
        wave = clamp(int(round),1,len(active_sector().waves))
        phase = .Playing
        spawn_wave()
        invulnerable = 3600
    }
    @(export)
    web_qa_hit :: proc "c" () {
        context = web_context
        invulnerable = 0
        append(&lasers, Shot{position=shipPosition+{20,20},radius=6})
        step_game(0,{})
    }

}

web_campaign_input: [MAX_CONFIG_BYTES]byte
@(export)
web_campaign_buffer :: proc "c" () -> rawptr { return raw_data(web_campaign_input[:]) }
@(export)
web_campaign_import :: proc "c" (size: i32) -> i32 {
    context = web_context
    editor_open = true; editor_name_edit = false; editor_dragging = false
    if size < 0 || int(size) > MAX_CONFIG_BYTES { set_editor_status("Campaign too large: maximum 256 KiB."); return 0 }
    if !load_campaign_json(string(web_campaign_input[:int(size)])) { return 0 }
    editor_sector=0; editor_wave=0; editor_selected = -1; editor_dirty=true
    return 1
}
@(export)
web_campaign_play :: proc "c" () { context=web_context; editor_open=false; reset_round() }
@(export)
web_editor_toggle :: proc "c" () { context=web_context; toggle_editor() }
@(export)
web_campaign_export :: proc "c" () { context=web_context; editor_save(true) }
@(export)
web_campaign_save :: proc "c" () { context=web_context; editor_save(false) }
@(export)
web_editor_open :: proc "c" () -> i32 { if editor_open { return 1 }; return 0 }
@(export)
web_sector_count :: proc "c" () -> i32 { return i32(len(campaign.sectors)) }
@(export)
web_current_wave_count :: proc "c" () -> i32 { context = web_context; return i32(len(active_sector().waves)) }

// Read-only diagnostics used by the browser motion checks.
@(export)
web_enemy_x :: proc "c" (index: i32) -> f32 {
    if index < 0 || int(index) >= len(enemies) { return -1 }
    return enemies[int(index)].position.x
}
@(export)
web_enemy_y :: proc "c" (index: i32) -> f32 {
    if index < 0 || int(index) >= len(enemies) { return -1 }
    return enemies[int(index)].position.y
}
@(export)
web_enemy_mode :: proc "c" (index: i32) -> i32 {
    if index < 0 || int(index) >= len(enemies) { return -1 }
    return i32(enemies[int(index)].mode)
}
@(export)
web_enemy_warning :: proc "c" (index: i32) -> i32 {
    if index < 0 || int(index) >= len(enemies) { return 0 }
    if enemies[int(index)].aim_locked { return 1 }
    return 0
}
