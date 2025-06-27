// Bruneton, Eric. "Precomputed Atmospheric Scattering". EGSR 2008.
// Source: https://ebruneton.github.io/precomputed_atmospheric_scattering/atmosphere/functions.glsl.html

#define TRANSMITTANCE_TEXTURE_WIDTH     256.0
#define TRANSMITTANCE_TEXTURE_HEIGHT    64.0

#define SCATTERING_TEXTURE_R_SIZE       32.0
#define SCATTERING_TEXTURE_MU_SIZE      128.0
#define SCATTERING_TEXTURE_MU_S_SIZE    32.0
#define SCATTERING_TEXTURE_NU_SIZE      8.0

#define IRRADIANCE_TEXTURE_WIDTH        64.0
#define IRRADIANCE_TEXTURE_HEIGHT       16.0

#define COMBINED_TEXTURE_WIDTH          256.0
#define COMBINED_TEXTURE_HEIGHT         128.0
#define COMBINED_TEXTURE_DEPTH          33.0

//======// Utility functions //===================================================================//

float ClampCosine(float mu) {
    return clamp(mu, -1.0, 1.0);
}

float ClampRadius(float r) {
    return clamp(r, atmosphereModel.bottom_radius, atmosphereModel.top_radius);
}

float SafeSqrt(float a) {
    a = max(a, 0.0);
    return a * inversesqrt(a);
}

//======// Intersections //=======================================================================//

float DistanceToTopAtmosphereBoundary(
    float r,
    float mu
    ) {
        float discriminant = r * r * (mu * mu - 1.0) + atmosphere_top_radius_sq;
        return max0(-r * mu + SafeSqrt(discriminant));
}

float DistanceToBottomAtmosphereBoundary(
    float r,
    float mu
    ) {
        float discriminant = r * r * (mu * mu - 1.0) + atmosphere_bottom_radius_sq;
        return max0(-r * mu - SafeSqrt(discriminant));
}

bool RayIntersectsGround(
    float r,
    float mu
    ) {
        return mu < 0.0 && r * r * (mu * mu - 1.0) + atmosphere_bottom_radius_sq >= 0.0;
}

//======// Coord Transforms //====================================================================//

float GetTextureCoordFromUnitRange(float x, float texture_size) {
    return 0.5 / texture_size + x * oms(1.0 / texture_size);
}

float GetCombinedTextureCoordFromUnitRange(float x, float original_texture_size, float combined_texture_size) {
    return 0.5 / combined_texture_size + x * (original_texture_size / combined_texture_size - 1.0 / combined_texture_size);
}

//======// Transmittance Lookup //================================================================//

vec2 GetTransmittanceTextureUvFromRMu(
    float r,
    float mu
    ) {
        // Distance to top atmosphere boundary for a horizontal ray at ground level.
        const float H = sqrt(atmosphere_top_radius_sq - atmosphere_bottom_radius_sq);

        // Distance to the horizon.
        float rho = SafeSqrt(r * r - atmosphere_bottom_radius_sq);

        // Distance to the top atmosphere boundary for the ray (r,mu), and its minimum
        // and maximum values over all mu - obtained for (r,1) and (r,mu_horizon).
        float d = DistanceToTopAtmosphereBoundary(r, mu);
        float d_min = atmosphereModel.top_radius - r;
        float d_max = rho + H;
        float x_mu = (d - d_min) / (d_max - d_min);
        float x_r = rho / H;
        return vec2(GetCombinedTextureCoordFromUnitRange(x_mu, TRANSMITTANCE_TEXTURE_WIDTH, COMBINED_TEXTURE_WIDTH),
                    GetCombinedTextureCoordFromUnitRange(x_r, TRANSMITTANCE_TEXTURE_HEIGHT, COMBINED_TEXTURE_HEIGHT));
}

vec3 GetTransmittanceToTopAtmosphereBoundary(
    float r,
    float mu
    ) {
        vec2 uv = GetTransmittanceTextureUvFromRMu(r, mu);
        return vec3(textureLod(atmosCombinedLut, vec3(uv, 32.5 / 33.0), 0.0));
}

vec3 GetTransmittance(
    float r,
    float mu,
    float d,
    bool ray_r_mu_intersects_ground
    ) {
        float r_d = ClampRadius(sqrt(d * d + 2.0 * r * mu * d + r * r));
        float mu_d = ClampCosine((r * mu + d) / r_d);

        if (ray_r_mu_intersects_ground) {
            return min(
                GetTransmittanceToTopAtmosphereBoundary(r_d, -mu_d) /
                GetTransmittanceToTopAtmosphereBoundary(r, -mu),
            vec3(1.0));
        } else {
            return min(
                GetTransmittanceToTopAtmosphereBoundary(r, mu) /
                GetTransmittanceToTopAtmosphereBoundary(r_d, mu_d),
            vec3(1.0));
        }
}

vec3 GetTransmittance(vec3 view_ray) {
	vec3 camera = vec3(0.0, viewerHeight, 0.0);
    // Compute the distance to the top atmosphere boundary along the view ray,
    // assuming the viewer is in space (or NaN if the view ray does not intersect
    // the atmosphere).
    float r = length(camera);
    float rmu = dot(camera, view_ray);
    float distance_to_top_atmosphere_boundary = -rmu - sqrt(rmu * rmu - r * r + atmosphere_top_radius_sq);

    // If the viewer is in space and the view ray intersects the atmosphere, move
    // the viewer to the top atmosphere boundary (along the view ray):
    if (distance_to_top_atmosphere_boundary > 0.0) {
        camera += view_ray * distance_to_top_atmosphere_boundary;
        r = atmosphereModel.top_radius;
        rmu += distance_to_top_atmosphere_boundary;
    } else if (r > atmosphereModel.top_radius) {
        // If the view ray does not intersect the atmosphere, simply return 0.
        return vec3(1.0);
    }

    // Compute the r, mu, mu_s and nu parameters needed for the texture lookups.
    float mu = rmu / r;

	return GetTransmittanceToTopAtmosphereBoundary(r, mu);
}

// vec3 GetTransmittance(vec3 ray_origin, vec3 worldDir) {
// 	float r_sq = dot(ray_origin, ray_origin);
// 	float rcp_r = inversesqrt(r_sq);
// 	float mu = dot(ray_origin, worldDir) * rcp_r;
// 	float r = r_sq * rcp_r;

// 	return GetTransmittanceToTopAtmosphereBoundary(mu, r);
// }

vec3 GetTransmittanceToSun(
    float r,
    float mu_s
    ) {
        float sin_theta_h = atmosphereModel.bottom_radius / r;
        float cos_theta_h = -SafeSqrt(1.0 - sin_theta_h * sin_theta_h);

        return GetTransmittanceToTopAtmosphereBoundary(r, mu_s) *
            smoothstep(-sin_theta_h * atmosphereModel.sun_angular_radius,
                        sin_theta_h * atmosphereModel.sun_angular_radius,
                        mu_s - cos_theta_h);
}

//======// Scattering Lookup //===================================================================//

vec4 GetScatteringTextureUvwzFromRMuMuSNu(
    float r,
    float mu,
    float mu_s,
    float nu,
    bool ray_r_mu_intersects_ground
    ) {
        // Distance to top atmosphere boundary for a horizontal ray at ground level.
        float H = sqrt(atmosphere_top_radius_sq - atmosphere_bottom_radius_sq);

        // Distance to the horizon.
        float rho = SafeSqrt(r * r - atmosphere_bottom_radius_sq);
        float u_r = GetCombinedTextureCoordFromUnitRange(rho / H, SCATTERING_TEXTURE_R_SIZE, COMBINED_TEXTURE_DEPTH);

        // Discriminant of the quadratic equation for the intersections of the ray
        // (r,mu) with the ground (see RayIntersectsGround).
        float r_mu = r * mu;
        float discriminant = r_mu * r_mu - r * r + atmosphere_bottom_radius_sq;
        float u_mu;

        if (ray_r_mu_intersects_ground) {
            // Distance to the ground for the ray (r,mu), and its minimum and maximum
            // values over all mu - obtained for (r,-1) and (r,mu_horizon).
            float d = -r_mu - SafeSqrt(discriminant);
            float d_min = r - atmosphereModel.bottom_radius;
            float d_max = rho;
            u_mu = 0.5 - 0.5 * GetTextureCoordFromUnitRange(d_max == d_min ? 0.0 : (d - d_min) / (d_max - d_min), SCATTERING_TEXTURE_MU_SIZE * 0.5);
        } else {
            // Distance to the top atmosphere boundary for the ray (r,mu), and its
            // minimum and maximum values over all mu - obtained for (r,1) and
            // (r,mu_horizon).
            float d = -r_mu + SafeSqrt(discriminant + H * H);
            float d_min = atmosphereModel.top_radius - r;
            float d_max = rho + H;
            u_mu = 0.5 + 0.5 * GetTextureCoordFromUnitRange((d - d_min) / (d_max - d_min), SCATTERING_TEXTURE_MU_SIZE * 0.5);
        }

        float d = DistanceToTopAtmosphereBoundary(atmosphereModel.bottom_radius, mu_s);
        float d_min = atmosphereModel.top_radius - atmosphereModel.bottom_radius;
        float d_max = H;
        float a = (d - d_min) / (d_max - d_min);
        float D = DistanceToTopAtmosphereBoundary(atmosphereModel.bottom_radius, atmosphereModel.mu_s_min);
        float A = (D - d_min) / (d_max - d_min);
        // An ad-hoc function equal to 0 for mu_s = mu_s_min (because then d = D and
        // thus a = A), equal to 1 for mu_s = 1 (because then d = d_min and thus
        // a = 0), and with a large slope around mu_s = 0, to get more texture 
        // samples near the horizon.
        float u_mu_s = GetTextureCoordFromUnitRange(max0(1.0 - a / A) / (1.0 + a), SCATTERING_TEXTURE_MU_S_SIZE);
        float u_nu = nu * 0.5 + 0.5;
        return vec4(u_nu, u_mu_s, u_mu, u_r);
}

vec3 GetExtrapolatedSingleMieScattering(
    vec4 scattering
    ) {
        // Algebraically this can never be negative, but rounding errors can produce
        // that effect for sufficiently short view rays.
        if (scattering.r <= 0.0) {
            return vec3(0.0);
        }
        return scattering.rgb * scattering.a / scattering.r *
            (atmosphereModel.rayleigh_scattering.r / atmosphereModel.mie_scattering.r) *
            (atmosphereModel.mie_scattering / atmosphereModel.rayleigh_scattering);
}

vec3 GetCombinedScattering(
    float r,
    float mu,
    float mu_s,
    float nu,
    bool ray_r_mu_intersects_ground,
    out vec3 single_mie_scattering
    ) {
        vec4 uvwz = GetScatteringTextureUvwzFromRMuMuSNu(r, mu, mu_s, nu, ray_r_mu_intersects_ground);
        float tex_coord_x = uvwz.x * (SCATTERING_TEXTURE_NU_SIZE - 1.0);
        float tex_x = floor(tex_coord_x);
        float lerp = tex_coord_x - tex_x;
        vec3 uvw0 = vec3((tex_x + uvwz.y) / SCATTERING_TEXTURE_NU_SIZE, uvwz.z, uvwz.w);
        vec3 uvw1 = vec3((tex_x + 1.0 + uvwz.y) / SCATTERING_TEXTURE_NU_SIZE, uvwz.z, uvwz.w);

        vec4 combined_scattering = textureLod(atmosCombinedLut, uvw0, 0.0) * oms(lerp) + textureLod(atmosCombinedLut, uvw1, 0.0) * lerp;

        vec3 scattering = vec3(combined_scattering);
        single_mie_scattering = GetExtrapolatedSingleMieScattering(combined_scattering);

        return scattering;
}

//======// Irradiance Lookup //===================================================================//

vec3 GetIrradiance(
    float r,
    float mu_s
    ) {
        float x_r = (r - atmosphereModel.bottom_radius) / (atmosphereModel.top_radius - atmosphereModel.bottom_radius);
        float x_mu_s = mu_s * 0.5 + 0.5;
        vec2 uv = vec2(GetCombinedTextureCoordFromUnitRange(x_mu_s, IRRADIANCE_TEXTURE_WIDTH, COMBINED_TEXTURE_WIDTH),
                       GetCombinedTextureCoordFromUnitRange(x_r, IRRADIANCE_TEXTURE_HEIGHT, COMBINED_TEXTURE_HEIGHT) + TRANSMITTANCE_TEXTURE_HEIGHT / COMBINED_TEXTURE_HEIGHT);

        return vec3(textureLod(atmosCombinedLut, vec3(uv, 32.5 / 33.0), 0.0));
}

//======// Rendering //===========================================================================//

vec3 GetSkyRadiance(
    vec3 view_ray,
    vec3 sun_direction,
    out vec3 transmittance
    ) {
		vec3 camera = vec3(0.0, viewerHeight, 0.0);
        // Compute the distance to the top atmosphere boundary along the view ray,
        // assuming the viewer is in space (or NaN if the view ray does not intersect
        // the atmosphere).
        float r = length(camera);
        float rmu = dot(camera, view_ray);
        float distance_to_top_atmosphere_boundary = -rmu - sqrt(rmu * rmu - r * r + atmosphere_top_radius_sq);

        // If the viewer is in space and the view ray intersects the atmosphere, move
        // the viewer to the top atmosphere boundary (along the view ray):
        if (distance_to_top_atmosphere_boundary > 0.0) {
            camera += view_ray * distance_to_top_atmosphere_boundary;
            r = atmosphereModel.top_radius;
            rmu += distance_to_top_atmosphere_boundary;
        } else if (r > atmosphereModel.top_radius) {
            // If the view ray does not intersect the atmosphere, simply return 0.
            transmittance = vec3(1.0);
            return vec3(0.0);
        }

        // Compute the r, mu, mu_s and nu parameters needed for the texture lookups.
        float mu = rmu / r;
        float mu_s = dot(camera, sun_direction) / r;
        float nu = dot(view_ray, sun_direction);

        bool ray_r_mu_intersects_ground = RayIntersectsGround(r, mu);

        transmittance = ray_r_mu_intersects_ground ? vec3(0.0) : GetTransmittanceToTopAtmosphereBoundary(r, mu);

        vec3 sun_single_mie_scattering;
        vec3 sun_scattering;

        vec3 moon_single_mie_scattering;
        vec3 moon_scattering;

        vec3 ground = vec3(0.0);
        #ifdef PLANET_GROUND
            if (ray_r_mu_intersects_ground) {
                vec3 planet_surface = camera + view_ray * DistanceToBottomAtmosphereBoundary(r, mu);

                float r = length(planet_surface);
                float mu_s = dot(planet_surface, sun_direction) / r;

                vec3 sky_irradiance = GetIrradiance(r, mu_s) + GetIrradiance(r, -mu_s) * moonlightMult;
                vec3 sun_irradiance = atmosphereModel.solar_irradiance * GetTransmittanceToSun(r, mu_s);

                float d = distance(camera, planet_surface);
                vec3 surface_transmittance = GetTransmittance(r, mu, d, ray_r_mu_intersects_ground);

                ground = mix(sky_irradiance, sun_irradiance * 0.5, wetness * 0.6) * atmosphereModel.ground_albedo * surface_transmittance;
            }
        #else
            ray_r_mu_intersects_ground = false;
        #endif

        sun_scattering = GetCombinedScattering(r, mu, mu_s, nu, ray_r_mu_intersects_ground, sun_single_mie_scattering);
        moon_scattering = GetCombinedScattering(r, mu, -mu_s, -nu, ray_r_mu_intersects_ground, moon_single_mie_scattering);

        vec3 rayleigh = sun_scattering * RayleighPhase(nu)
                     + moon_scattering * RayleighPhase(-nu) * moonlightMult;

        vec3 mie = sun_single_mie_scattering * CornetteShanksPhase(nu, mie_phase_g)
                + moon_single_mie_scattering * CornetteShanksPhase(-nu, mie_phase_g) * moonlightMult;

        rayleigh = mix(rayleigh, vec3(luminance(rayleigh)), wetness * 0.6);

        return rayleigh + mie + ground;
}

vec3 GetSkyRadiance(
    vec3 view_ray,
    vec3 sun_direction
    ) {
		vec3 camera = vec3(0.0, viewerHeight, 0.0);
        // Compute the distance to the top atmosphere boundary along the view ray,
        // assuming the viewer is in space (or NaN if the view ray does not intersect
        // the atmosphere).
        float r = length(camera);
        float rmu = dot(camera, view_ray);
        float distance_to_top_atmosphere_boundary = -rmu - sqrt(rmu * rmu - r * r + atmosphere_top_radius_sq);

        // If the viewer is in space and the view ray intersects the atmosphere, move
        // the viewer to the top atmosphere boundary (along the view ray):
        if (distance_to_top_atmosphere_boundary > 0.0) {
            camera += view_ray * distance_to_top_atmosphere_boundary;
            r = atmosphereModel.top_radius;
            rmu += distance_to_top_atmosphere_boundary;
        } else if (r > atmosphereModel.top_radius) {
            // If the view ray does not intersect the atmosphere, simply return 0.
            return vec3(0.0);
        }

        // Compute the r, mu, mu_s and nu parameters needed for the texture lookups.
        float mu = rmu / r;
        float mu_s = dot(camera, sun_direction) / r;
        float nu = dot(view_ray, sun_direction);

        vec3 sun_single_mie_scattering;
        vec3 sun_scattering;

        vec3 moon_single_mie_scattering;
        vec3 moon_scattering;

        vec3 ground = vec3(0.0);
        #ifdef PLANET_GROUND
            bool ray_r_mu_intersects_ground = RayIntersectsGround(r, mu);

            if (ray_r_mu_intersects_ground) {
                vec3 planet_surface = camera + view_ray * DistanceToBottomAtmosphereBoundary(r, mu);

                float r = length(planet_surface);
                float mu_s = dot(planet_surface, sun_direction) / r;

                vec3 sky_irradiance = GetIrradiance(r, mu_s) + GetIrradiance(r, -mu_s) * moonlightMult;
                vec3 sun_irradiance = atmosphereModel.solar_irradiance * GetTransmittanceToSun(r, mu_s);

                float d = distance(camera, planet_surface);
                vec3 surface_transmittance = GetTransmittance(r, mu, d, ray_r_mu_intersects_ground);

                ground = mix(sky_irradiance, sun_irradiance * 0.5, wetness * 0.6) * atmosphereModel.ground_albedo * surface_transmittance;
            }
        #else
            bool ray_r_mu_intersects_ground = false;
        #endif

        sun_scattering = GetCombinedScattering(r, mu, mu_s, nu, ray_r_mu_intersects_ground, sun_single_mie_scattering);
        moon_scattering = GetCombinedScattering(r, mu, -mu_s, -nu, ray_r_mu_intersects_ground, moon_single_mie_scattering);

        vec3 rayleigh = sun_scattering * RayleighPhase(nu)
                     + moon_scattering * RayleighPhase(-nu) * moonlightMult;

        vec3 mie = sun_single_mie_scattering * CornetteShanksPhase(nu, mie_phase_g)
                + moon_single_mie_scattering * CornetteShanksPhase(-nu, mie_phase_g) * moonlightMult;

        rayleigh = mix(rayleigh, vec3(luminance(rayleigh)), wetness * 0.6);

        return rayleigh + mie + ground;
}

vec3 GetSkyRadianceToPoint(
    //vec3 camera,
    vec3 point,
    vec3 sun_direction,
    out vec3 transmittance
    ) {
		vec3 camera = vec3(0.0, viewerHeight, 0.0);
        // Compute the distance to the top atmosphere boundary along the view ray,
        // assuming the viewer is in space (or NaN if the view ray does not intersect
        // the atmosphere).
        vec3 view_ray = normalize(point);
        float r = length(camera);
        float rmu = dot(camera, view_ray);
        float distance_to_top_atmosphere_boundary = -rmu - sqrt(rmu * rmu - r * r + atmosphere_top_radius_sq);

        // If the viewer is in space and the view ray intersects the atmosphere, move
        // the viewer to the top atmosphere boundary (along the view ray):
        if (distance_to_top_atmosphere_boundary > 0.0) {
            camera += view_ray * distance_to_top_atmosphere_boundary;
            r = atmosphereModel.top_radius;
            rmu += distance_to_top_atmosphere_boundary;
        }

        // Compute the r, mu, mu_s and nu parameters for the first texture lookup.
        float mu = rmu / r;
        float mu_s = dot(camera, sun_direction) / r;
        float nu = dot(view_ray, sun_direction);
        float d = length(point);
        bool ray_r_mu_intersects_ground = RayIntersectsGround(r, mu);

        transmittance = GetTransmittance(r, mu, d, ray_r_mu_intersects_ground);

        vec3 sun_single_mie_scattering;
        vec3 sun_scattering = GetCombinedScattering(r, mu, mu_s, nu, ray_r_mu_intersects_ground, sun_single_mie_scattering);
        vec3 moon_single_mie_scattering;
        vec3 moon_scattering = GetCombinedScattering(r, mu, -mu_s, -nu, ray_r_mu_intersects_ground, moon_single_mie_scattering);

        // Compute the r, mu, mu_s and nu parameters for the second texture lookup.
        // If shadow_length is not 0 (case of light shafts), we want to ignore the
        // scattering along the last shadow_length meters of the view ray, which we
        // do by subtracting shadow_length from d (this way scattering_p is equal to
        // the S|x_s=x_0-lv term in Eq. (17) of our paper).
        float r_p = ClampRadius(sqrt(d * d + 2.0 * r * mu * d + r * r));
        float mu_p = (r * mu + d) / r_p;
        float mu_s_p = (r * mu_s + d * nu) / r_p;
        float mu_s_p_m = (r * -mu_s + d * -nu) / r_p;

        vec3 sun_single_mie_scattering_p;
        vec3 sun_scattering_p = GetCombinedScattering(r_p, mu_p, mu_s_p, nu, ray_r_mu_intersects_ground, sun_single_mie_scattering_p);
        vec3 moon_single_mie_scattering_p;
        vec3 moon_scattering_p = GetCombinedScattering(r_p, mu_p, mu_s_p_m, -nu, ray_r_mu_intersects_ground, moon_single_mie_scattering_p);

        sun_scattering -= transmittance * sun_scattering_p;
        sun_single_mie_scattering -= transmittance * sun_single_mie_scattering_p;
        moon_scattering = moon_scattering - transmittance * moon_scattering_p;
        moon_single_mie_scattering -= transmittance * moon_single_mie_scattering_p;

        // Hack to avoid rendering artifacts when the sun is below the horizon.
        sun_single_mie_scattering *= smoothstep(0.0, 0.01, mu_s);
        moon_single_mie_scattering *= smoothstep(0.0, 0.01, -mu_s);

        vec3 rayleigh = sun_scattering * RayleighPhase(nu)
                     + moon_scattering * RayleighPhase(-nu) * moonlightMult;

        vec3 mie = sun_single_mie_scattering * CornetteShanksPhase(nu, mie_phase_g)
                + moon_single_mie_scattering * CornetteShanksPhase(-nu, mie_phase_g) * moonlightMult;

        rayleigh = mix(rayleigh, vec3(luminance(rayleigh)), wetness * 0.6);

        return rayleigh + mie;
}

vec3 GetSunAndSkyIrradiance(
    vec3 point,
    vec3 sun_direction,
    out vec3 sun_irradiance,
    out vec3 moon_irradiance
    ) {
        float r = length(point);
        float mu_s = dot(point, sun_direction) / r;

        sun_irradiance = atmosphereModel.solar_irradiance * GetTransmittanceToSun(r, mu_s);
        moon_irradiance = atmosphereModel.solar_irradiance * GetTransmittanceToSun(r, -mu_s) * moonlightMult;

        vec3 sky_irradiance = GetIrradiance(r, mu_s) + GetIrradiance(r, -mu_s) * moonlightMult;

        float NoP = point.y / r;
        float diff = (1.0 - NoP) * rTAU + NoP + 1.0;

        return sky_irradiance * diff;
}