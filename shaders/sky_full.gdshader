shader_type sky;
group_uniforms Sun;

/**
The intensity of the sun.
Simple Lambertian light contains 1/PI in its formulation. For that reason, PI usually represents a full low dynamic range.
We recommend keeping contrast between the sky and the directional light. The default value assumes a directional light of 10PI and a sky of 20PI.
*/
uniform float sun_intensity : hint_range(0.0, 314.159, 0.1) = 62.832;
uniform vec3 sun_wavelengths = vec3(0.680, 0.550, 0.480);

/*
Rayleigh scattering is the reason why sunsets are red and noons are blue.
Rayleigh happens when the particles are small enough to affect the individual wavelengths of light.
At sunrise/sunset, light coming from the sun has to traverse a much bigger distance towards the eye resulting in most of the surviving light being red because of its larger wavelength.
*/
group_uniforms Atmosphere.Rayleigh;

/**
Defines the thickness of the layer in which Rayleigh scattering happens.
A thicker layer can provide more vibrant reds at sunrise/sunset, but may stain the blue of the sky when the sun is at its zenith.
*/
uniform float rayleigh_scale_height : hint_range(0.0, 100000.0, 1.0) = 8000.0;

/**
Defines the intensity of the Rayleigh multi-bounce approximation.
After many bounces, Rayleigh becomes isotropic. We take advantage of that to "inject" some light in order to avoid pitch black planet shadows.
The injection is done naively, so it is recommended to keep this value as low as possible to prevent contrast loss.
*/
uniform float rayleigh_multi_scattering : hint_range(0.0, 1.0, 0.001 ) = 0.025;

/*
Mie scattering is responsible for the glow around the sun and phenomena such as fog and clouds.
Mie scattering happens when particles are big enough to substantially block light, therefore, the color of the remaining light is mostly unaffected.
Because Mie tends to scatter lots of light, very cloudy scenes may need more samples in order to prevent parts of the sky from becoming black.
*/
group_uniforms Atmosphere.Mie;

/**
Defines the thickness of the layer in which Mie scattering happens.
A thicker layer can create some interesting effects, but for realistic setups it is recommended to increase mie_scattering instead.
*/
uniform float mie_scale_height : hint_range(0.0, 1e5, 1.00) = 1200.0;

/**
The strength of the scattering effect. Lower values result in a clearer day. */
uniform float mie_scattering : hint_range(0.0, 1.0, 1e-7) = 5e-6;
uniform float mie_albedo : hint_range(0.0, 1.0, 0.01) = 0.9;

/**
We use a Double-Lobe Henyey-Greenstein phase function for Mie.
While Mie scatters light predominantly forward, the double lobe allows for a more natural behaviour by scattering some of the light backwards.
The value of the forward lobe.
*/
uniform float mie_g_forward : hint_range(0.0, 1.0,  0.01) = 0.85;

/** The value of the backward lobe. */
uniform float mie_g_backward : hint_range(-1.0, 0.0,  0.01) = -0.15;

/**
The weight used to interpolate between the forward and backward lobes.
This value should usually remain close to one, but lowering it can help convey denser/foggier/humid atmospheres.
*/
uniform float mie_weight : hint_range(0.0, 1.0, 0.01) = 0.85;

/**
Defines the intensity of the Mie multi-bounce approximation.
Unlike Rayleigh, Mie remains anisotropic after many bounces. In order to simulate multiple bounces, we use a secondary softer, less directional lobe.
*/
uniform float mie_multi_scattering : hint_range(0.0, 1.0, 0.01) = 0.30;

/** The multiscattering value of the forward lobe. */
uniform float multiscattering_mie_g_forward : hint_range(0.0, 1.0, 0.01) = 0.5;

/** The multiscattering value of the backward lobe. */
uniform float multiscattering_mie_g_backward : hint_range(-1.0, 0.0, 0.01) = -0.05;

/** The weight used to interpolate between the forward and backward multiscattering lobes. */
uniform float multiscattering_mie_weight : hint_range(0.0, 1.0, 0.01) = 0.75;

/*
The Ozone layer behaves as a purely absorbent medium, subtracting mostly reds and oranges. It is responsible for the electric blues of the "blue hour."
Unlike Rayleigh or Mie, we don't have a specific equation to define its behavior, so we mostly configure the center and width of the layer.
*/
group_uniforms Atmosphere.Ozone;

/* Ozone extinction coefficient */
const vec3 ozone_extinction = vec3(0.650, 1.881, 0.085) * 1e-6;

/** The center of the ozone layer */
uniform float ozone_center : hint_range(0.0, 1e5, 1.00) = 25000.0;

/** The width of the ozone layer */
uniform float ozone_width : hint_range(0.0, 1e5, 1.00) = 30000.0;

/** Planet geometry. */
group_uniforms Planet;

/** The radius of the planet in meters. */
uniform float planet_radius = 6360000.0;

/** The height of the atmosphere from the ground in meters. */
uniform float atmosphere_height = 100000.0;

/**
Base altitude.
The ground will be this many meters below the camera when the camera is at Y = 0.
*/
uniform float base_altitude = 0.0;

/** Ground color. */
uniform vec3 ground_color = vec3(0.12, 0.11, 0.08);

/* Quality and performance settings */
group_uniforms Quality;

/**
The amount of samples along the view path (out-scattering).
Defines the volumetric resolution of the volume.
*/
uniform int view_samples : hint_range(0, 256) = 24;

/**
The amount of samples along the sun path (in-scattering).
Defines how accurately the light traverses the medium.
*/
uniform int sun_samples : hint_range(0, 256) = 8;


/* Returns the full diameter of the atmospheric sphere */
float get_atmosphere_radius(){
	return planet_radius + atmosphere_height;
}


/* Ray-Sphere intersection from Inigo Quilez (https://iquilezles.org/articles/intersectors) */
vec2 ray_sphere_intersection(vec3 ray_origin, vec3 ray_direction, float sphere_radius) {
	float b = dot(ray_origin, ray_direction);
	float c = dot(ray_origin, ray_origin) - sphere_radius * sphere_radius;
	float discriminant = b * b - c;
	
	if (discriminant < 0.0){
		return vec2(-1.0);
	}

	float root = sqrt(discriminant);
	return vec2(-b - root, -b + root);
}


/*
Returns the Rayleigh scattering coefficient based on sun wavelengths.
Rayleigh doesn't absorb light, so we use the coefficient directly.
*/
vec3 get_rayleigh_scattering(){
	return (1.0 / (sun_wavelengths * sun_wavelengths * sun_wavelengths * sun_wavelengths)) * 1e-6;
}


/*
Returns the Mie extinction coefficient.
Unlike Rayleigh, Mie does absorb light. The albedo value represents how much light is preserved (0 - Full absorption, 1 - Full scattering).
*/
float get_mie_extinction(){
	return mie_scattering / mie_albedo;
}


/*
Returns the Rayleigh phase function. This phase has a specific equation, so there is not much to configure.
*/
float get_rayleigh_phase(float cos_theta) {
	// Precomputed 3/16 PI.
	return 0.05968310365 * (1.0 + cos_theta * cos_theta);
}


/*
Simple Henyey-Greenstein. Two of these ellipsoidal functions are used for the final Mie phase calculation.
*/
float henyey_greenstein_phase(float cos_theta, float g) {
	float g2 = g * g;
	// Correct version. Precomputed 1/4 PI.
	return 0.07957747154 * (1.0 - g2) / pow(1.0 + g2 - 2.0 * g * cos_theta, 1.5);
}

/*
Double-lobe Henyey-Greenstein used for Mie. It's just a mix of forward and backward lobes.
*/
float get_mie_phase(float cos_theta, float g_backward, float g_forward, float weight) {
	float backward_phase = henyey_greenstein_phase(cos_theta, g_backward);
	float forward_phase = henyey_greenstein_phase(cos_theta, g_forward);
	return mix(backward_phase, forward_phase, weight);
}


/*
Returns the local density based on the provided scale heights.
Rayleigh on X, Mie on Y, Ozone on Z.
*/
vec3 get_optical_depth_at_point(vec3 position) {
	float altitude = length(position) - planet_radius;
	
	return vec3(
		exp(-altitude / rayleigh_scale_height),
		exp(-altitude / mie_scale_height),
		max(0.0, 1.0 - abs(altitude - ozone_center) / (ozone_width / 2.0))
	);
}


/*
Returns the transmittance along the given atmospheric path.
We use simple Lambert's law to calculate transmittance. To compensate for the exponential
nature of the atmosphere, we use the average of the start and end step densities to get a better
representation of the segment.
Rayleigh on X, Mie on Y, Ozone on Z.
*/
vec3 get_transmittance(vec3 origin, vec3 direction, float dist, int samples) {
	float step_length              = dist / float(samples);
	vec3 accumulated_optical_depth = vec3(0.0);
	vec3 optical_depth_start       = get_optical_depth_at_point(origin);
	
	for (int i = 0; i < samples; i++) {
		vec3 optical_depth_end  = get_optical_depth_at_point(origin + direction * (float(i + 1)) * step_length);
		vec3 step_optical_depth = mix(optical_depth_start, optical_depth_end, 0.5) * step_length;
		
		accumulated_optical_depth += step_optical_depth;
		optical_depth_start        = optical_depth_end;
	}
	
	return exp(-(
		get_rayleigh_scattering() * accumulated_optical_depth.x +
		get_mie_extinction()      * accumulated_optical_depth.y +
		ozone_extinction          * accumulated_optical_depth.z
		));
}

/*
Returns the final atmospheric radiance along a given path.
*/
vec3 integrate_radiance(vec3 ray_origin, vec3 ray_direction, float target_distance, int samples, vec3 sun_direction) {
	float atmosphere_radius = get_atmosphere_radius();
	
	// how similar are the ray and sun directions.
	float cos_theta = dot(ray_direction, sun_direction);
	
	// Distance to cover by each step.
	float step_length = target_distance / float(samples);
	
	// Phases.
	float rayleigh_phase             = get_rayleigh_phase(cos_theta);
	float mie_phase                  = get_mie_phase(cos_theta, mie_g_backward, mie_g_forward, mie_weight);
	float multi_scattering_mie_phase = get_mie_phase(cos_theta, multiscattering_mie_g_backward, multiscattering_mie_g_forward, multiscattering_mie_weight);
	
	// Accumulators
	vec3 accumulated_optical_depth = vec3(0.0);
	vec3 accumulated_radiance      = vec3(0.0);
	vec3 view_transmittance        = vec3(0.0);
	
	// Optical depth at the beginning of the first sample.
	vec3 optical_depth_start = get_optical_depth_at_point(ray_origin);
	bool hits_ground = false;
	
	for (int i = 0; i < samples; i++) {
		
		// Optical deph at the end of the sample.
		vec3 optical_depth_end = get_optical_depth_at_point(ray_origin + ray_direction * float(i + 1) * step_length);
		
		// Average them. Jitter changes the weight of the average.
		vec3 step_optical_depth = mix(optical_depth_start, optical_depth_end, 0.5) * step_length;
		
		// Accumulate the optical depth for this step
		accumulated_optical_depth += step_optical_depth;
		
		vec3 sample_point = ray_origin + ray_direction * (float(i) + 0.5) * step_length;
		
		// Calculate transmittance.
		view_transmittance = exp(-(
			get_rayleigh_scattering() * accumulated_optical_depth.x +
			get_mie_extinction()       * accumulated_optical_depth.y +
			ozone_extinction           * accumulated_optical_depth.z
			));
		
		vec3 sun_radiance = vec3(0.0);
		
		// Planet intersection.
		vec2 planet_hit = ray_sphere_intersection(sample_point, sun_direction, planet_radius);
		
		hits_ground = planet_hit.y > 0.0;
		
		// If the sun is NOT occluded by the planet, calculate sun radiance.
		if (!hits_ground) {
			
			// Atmosphere intersection.
			vec2 atmosphere_hit = ray_sphere_intersection(sample_point, sun_direction, atmosphere_radius);
			vec3 sun_transmittance = get_transmittance(sample_point, sun_direction, atmosphere_hit.y, sun_samples);
			vec3 scattering_coeff = (
				step_optical_depth.x * get_rayleigh_scattering() * rayleigh_phase +
				step_optical_depth.y * mie_scattering            * mie_phase
				);
			
			sun_radiance = sun_transmittance * sun_intensity * scattering_coeff;
		}
		
		// Accumulate sun radiance.
		accumulated_radiance += sun_radiance * view_transmittance;
		
		// Multi scattering approximations.
		vec3 rayleigh_ambient = step_optical_depth.x * get_rayleigh_scattering() * rayleigh_multi_scattering;
		vec3 mie_ambient = vec3(step_optical_depth.y * mie_scattering * multi_scattering_mie_phase * mie_multi_scattering);
		
		// Accumulate ambient light.
		accumulated_radiance += (rayleigh_ambient + mie_ambient) * view_transmittance;
		
		// Recycle this end point as the next iteration start point.
		optical_depth_start = optical_depth_end;
	}
	
	vec3 sun_disk = vec3(0.0);
	float planet_hit = ray_sphere_intersection(ray_origin, ray_direction, planet_radius).y;
	
	if (planet_hit < 0.0){
		sun_disk = smoothstep(0.9998, 1.0, cos_theta) * sun_intensity * view_transmittance;
	}
	return accumulated_radiance + sun_disk;
}

/*
Main integrator for the sky.
Renders the atmosphere, the sun disk and the planet.
*/
void sky() {
	vec3 final_color = vec3(0.0);
	
	// If there is no sun everyone is dead and we can go home :D.
	if (LIGHT0_ENABLED) {
		vec3 sun_direction = LIGHT0_DIRECTION;
		
		float atmosphere_radius = get_atmosphere_radius();
		
		// Position clamped to prevent entering the "low precision zone"
		vec3 ray_origin = vec3(0.0, planet_radius + clamp(POSITION.y + base_altitude, 0.5, atmosphere_height), 0.0);
		vec3 ray_direction = EYEDIR;
		
		// Atmosphere intersection.
		vec2 atmosphere_hit = ray_sphere_intersection(ray_origin, ray_direction, atmosphere_radius);
		
		// Ground intersection.
		vec2 ground_hit = ray_sphere_intersection(ray_origin, ray_direction, planet_radius);	
		bool hits_ground = ground_hit.y > 0.0;
		
		// Clamp the atmosphere to the ocean.
		float atmosphere_distance = hits_ground ? ground_hit.x : atmosphere_hit.y;
		
		// Use half the samples for view to ground, and the other half from ground back to sky.
		int samples = hits_ground ? view_samples / 2 : view_samples;
		
		// atmosphere radiance.
		vec3 atmosphere_radiance = integrate_radiance(ray_origin, ray_direction, atmosphere_distance, samples, sun_direction);
		
		final_color = atmosphere_radiance;
		
		vec3 sun_transmittance = vec3(0.0);
		
		// ground color.
		if (hits_ground) {
			vec3 ground_point = ray_origin + ray_direction * atmosphere_distance;
			vec3 ground_normal = normalize(ground_point);
			
			// how similar are the ray and sun directions.
			float cos_theta = dot(ray_direction, sun_direction);
			
			float ground_to_atmosphere_distance = ray_sphere_intersection(ground_point, ground_normal, atmosphere_radius).y;
			
			// Distance to cover by each step.
			float step_length = ground_to_atmosphere_distance / float(samples);
			
			// Accumulators
			vec3 accumulated_optical_depth = vec3(0.0);
			vec3 accumulated_radiance = vec3(0.0);
			
			//Optical depth at the beginning of the first sample.
			vec3 optical_depth_start = get_optical_depth_at_point(ground_point);
			
			float multi_scattering_mie_phase = get_mie_phase(cos_theta, multiscattering_mie_g_backward, multiscattering_mie_g_forward, multiscattering_mie_weight);
			
			for (int i = 0; i < samples; i++) {
				// Optical deph at the end of the sample.
				vec3 optical_depth_end = get_optical_depth_at_point(ground_point + ground_normal * float(i + 1) * step_length);
				
				// Average them. Jitter changes the weight of the average.
				vec3 step_optical_depth = mix(optical_depth_start, optical_depth_end, 0.5) * step_length;
				
				// Accumulate the optical depth for this step
				accumulated_optical_depth += step_optical_depth;
				
				// I'm not quite sure the jitter belongs here too.
				vec3 sample_point = ground_point + ground_normal * (float(i) + 0.5) * step_length;
				
				// Calculate transmittance.
				vec3 transmittance = exp(-(
					get_rayleigh_scattering() * accumulated_optical_depth.x +
					get_mie_extinction()       * accumulated_optical_depth.y +
					ozone_extinction           * accumulated_optical_depth.z
					));
				
				// Multi scattering approximations.
				vec3 rayleigh_ambient = step_optical_depth.x * get_rayleigh_scattering() * rayleigh_multi_scattering;
				
				//NOTE: Mie multi scattering is not isotropic. If we add it to the planet, we could see the sun through it.
				
				// Accumulate ambient light.
				accumulated_radiance += rayleigh_ambient * transmittance;
				
				// Recycle this end point as the next iteration start point.
				optical_depth_start = optical_depth_end;
			}
			
			// Simple lighting model for the planet.
			float direct_light = max(dot(ground_normal, sun_direction), 0.0);
			
			if (direct_light > 0.0){
				float ground_to_sun_distance = ray_sphere_intersection(ground_point, sun_direction, atmosphere_radius).y;
				sun_transmittance = get_transmittance(ground_point, sun_direction, ground_to_sun_distance, sun_samples);
			}
			
			//HACK: An ambient level high enough to illuminate the ground will blow the sky. So we make the same unit affect the ground harder.
			vec3 ground_albedo = ground_color * (direct_light * sun_intensity * sun_transmittance + accumulated_radiance *  75.) * 1.0/PI;
			vec3 transmittance_to_eye = get_transmittance(ray_origin, ray_direction, atmosphere_distance, view_samples);
			
			final_color += ground_albedo * transmittance_to_eye;
		}
	}
	COLOR = final_color;
}