package main

import "core:math"
import rl "vendor:raylib"

// One-dimensional value noise. The quintic interpolant has zero first and
// second derivatives at lattice boundaries (Perlin, 2002). This is value
// noise, not Perlin's gradient-noise algorithm.
noise_hash :: proc(input: u32) -> u32 {
	value := input
	value = value ~ (value >> 16)
	value *= 0x7feb352d
	value = value ~ (value >> 15)
	value *= 0x846ca68b
	return value ~ (value >> 16)
}

noise_unit :: proc(seed: u32, channel: u32) -> f32 {
	bits := noise_hash(seed ~ noise_hash(channel + 0x9e3779b9))
	return f32(bits >> 8) / 16777215.0
}

noise_smooth :: proc(t: f32) -> f32 {
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
}

noise_value :: proc(time: f32, seed: u32) -> f32 {
	cell := i32(math.floor(time))
	fraction := time - f32(cell)
	a := noise_unit(seed, u32(cell)) * 2.0 - 1.0
	b := noise_unit(seed, u32(cell + 1)) * 2.0 - 1.0
	return a + (b - a) * noise_smooth(fraction)
}

noise_wander :: proc(time: f32, seed: u32) -> f32 {
	broad := noise_value(time, seed)
	detail := noise_value(time * 2.03 + 17.0, seed ~ 0x68bc21eb)
	return broad * 0.78 + detail * 0.22
}

vector_limit :: proc(v: rl.Vector2, maximum: f32) -> rl.Vector2 {
	length_squared := v.x * v.x + v.y * v.y
	if length_squared > maximum * maximum && length_squared > 0 {
		return v * (maximum / math.sqrt(length_squared))
	}
	return v
}

vector_length :: proc(v: rl.Vector2) -> f32 {
	return math.sqrt(v.x * v.x + v.y * v.y)
}

curve_bezier :: proc(a, b, c, d: rl.Vector2, t: f32) -> rl.Vector2 {
	u := 1.0 - t
	return a * (u * u * u) + b * (3 * u * u * t) + c * (3 * u * t * t) + d * (t * t * t)
}
