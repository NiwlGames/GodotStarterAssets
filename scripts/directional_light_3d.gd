@tool
extends DirectionalLight3D

## Max light intensity. PI is the maximun strenght we can have without going HDR.
@export var max_intensity: float = PI * 10;

## Gradient texture to be sampled for the sun color(from sunset to zenith).
@export var color_texture: GradientTexture1D

## Noise to be sampled for intensity variance. Simulates clouds passing by.
@export var variance_texture: FastNoiseLite

func _process(_delta: float) -> void:
	
	# Store the texture into an image object.
	var gradient: Image = color_texture.get_image()
	
	# Dot product between the light direction and the zenith.
	var sun_dot: float = max(basis.z.dot(Vector3.UP), 0)
	
	# Color sample
	light_color = gradient.get_pixel(int(sun_dot * (gradient.get_size().x - 1)), 0)
	
	# Light fade
	light_energy = lerp(0.0, max_intensity, sun_dot)
