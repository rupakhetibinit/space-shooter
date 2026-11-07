package validate_cli

import game "../.."
import "core:fmt"
import "core:os"

main :: proc() {
	path := "assets/campaign.json"
	if len(os.args) > 1 {path = os.args[1]}
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {fmt.eprintln("Cannot read campaign:", path);os.exit(1)}
	defer delete(data)
	if !game.load_campaign_json(string(data)) {
		fmt.eprintln(string(game.editor_status_buffer[:game.editor_status_length]))
		os.exit(1)
	}
	waves, total := 0, 0
	for sector in game.campaign.sectors {
		waves += len(sector.waves)
		for wave in sector.waves {total += len(wave.enemies)}
	}
	fmt.printf("Valid campaign: %d sectors, %d waves, %d enemy spawns.\n", len(game.campaign.sectors), waves, total)
}
