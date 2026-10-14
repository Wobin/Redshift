-- ─────────────────────────────────────────────
-- Redshift wave module
-- ─────────────────────────────────────────────

local mod = get_mod("Redshift")

local World = World
local Vector3 = Vector3
local Quaternion = Quaternion
local math_floor = math.floor
local math_max = math.max
local math_min = math.min

local HIDDEN_LENGTH = 0.01
local DOT_WIDTH = 0.05
local DOT_DEPTH = 0.5
local MAX_DOTS = 24

local INDOOR_BEAM = "content/fx/particles/enemies/sniper_laser_sight"
local OUTDOOR_BEAM = "content/fx/particles/enemies/renegade_sniper/renegade_sniper_beam_outdoors"

local PYRO_CLOUD = "polychromatic_jet_1"
local PYRO_VARIABLE = "lighting_far_range"
local PYRO_STOCK_VALUE = 1000
local PYRO_HUE_STEPS = 1024
local PYRO_SATURATION_STEPS = 15
local PYRO_MIN_BRIGHTNESS_STEP = 1
local PYRO_STOCK_BRIGHTNESS_STEP = 8
local PYRO_MAX_BRIGHTNESS_STEP = 15
local PYRO_CODE_DIVISOR = 16384

local DEFAULT_BEAM_COLOUR = { 255, 255, 0, 0 }
local DEFAULT_DOT_COLOUR = { 255, 0, 255, 0 }

local wave = {}

local settings = {
	dot_length = 1,
	dot_gap = 0.5,
	dot_speed = 7,
	beam_thickness = 0.25,
	recolour = false,
	beam_value = PYRO_STOCK_VALUE,
	beam_r = 1,
	beam_g = 0,
	beam_b = 0,
	dot_value = PYRO_STOCK_VALUE,
}

local function rgb_to_hsv(r, g, b)
	local max = math_max(r, g, b)
	local min = math_min(r, g, b)
	local delta = max - min
	local hue = 0
	if delta > 0 then
		if max == r then
			hue = ((g - b) / delta) % 6
		elseif max == g then
			hue = (b - r) / delta + 2
		else
			hue = (r - g) / delta + 4
		end
		hue = hue / 6
	end
	local saturation = max > 0 and delta / max or 0
	return hue, saturation, max
end

local function encode(hue, saturation, value)
	local hue_step = math_floor(hue * PYRO_HUE_STEPS) % PYRO_HUE_STEPS
	local saturation_step = math_floor(saturation * PYRO_SATURATION_STEPS + 0.5)
	local brightness_step = math_floor(value * PYRO_STOCK_BRIGHTNESS_STEP + 0.5)
	if brightness_step < PYRO_MIN_BRIGHTNESS_STEP then
		brightness_step = PYRO_MIN_BRIGHTNESS_STEP
	elseif brightness_step > PYRO_MAX_BRIGHTNESS_STEP then
		brightness_step = PYRO_MAX_BRIGHTNESS_STEP
	end
	return PYRO_STOCK_VALUE + saturation_step + (hue_step * 16 + brightness_step) / PYRO_CODE_DIVISOR
end

local function colour_value(setting_id, default)
	local colour = mod:get(setting_id)
	if type(colour) ~= "table" then
		colour = default
	end
	local r, g, b = (colour[2] or 0) / 255, (colour[3] or 0) / 255, (colour[4] or 0) / 255
	return encode(rgb_to_hsv(r, g, b)), r, g, b
end

function wave.refresh_settings()
	settings.dot_length = mod:get("dot_length") or 1
	settings.dot_gap = mod:get("dot_gap") or 0.5
	settings.dot_speed = mod:get("dot_speed") or 7
	settings.beam_thickness = (mod:get("beam_thickness") or 25) / 100
	settings.recolour = mod:get("recolour") == true
	settings.beam_value, settings.beam_r, settings.beam_g, settings.beam_b = colour_value("beam_colour", DEFAULT_BEAM_COLOUR)
	settings.dot_value = colour_value("dot_colour", DEFAULT_DOT_COLOUR)
end

local function tint(world, id, value)
	if not World.are_particles_playing(world, id) then
		return
	end
	if not World.has_particles_material(world, id, PYRO_CLOUD) then
		return
	end
	World.set_particles_material_scalar(world, id, PYRO_CLOUD, PYRO_VARIABLE, value)
end

local FLASH_LERP_VARIABLE = "lerp_color_a"
local FLASH_TINT_VARIABLE = "material_variable_76952f42_25134716_0e97137b"
local FLASH_CLOUDS = { "polychromatic_jet_1", "polychromatic_jet_2" }

local SPAWN_TINTS = {
	["content/fx/particles/enemies/renegade_sniper/renegade_sniper_beam"] = { scalar = true },
	["content/fx/particles/enemies/renegade_sniper/renegade_sniper_muzzle_flash"] = { variable = FLASH_LERP_VARIABLE, clouds = 2 },
	["content/fx/particles/enemies/renegade_sniper/renegade_sniper_beam_emitter"] = { variable = FLASH_TINT_VARIABLE, clouds = 1 },
	["content/fx/particles/enemies/sniper_scope_flash"] = { variable = FLASH_TINT_VARIABLE, clouds = 2 },
}

function wave.tint_spawn(world, effect_name, id)
	if not settings.recolour then
		return
	end
	local spec = SPAWN_TINTS[effect_name]
	if not spec then
		return
	end
	if spec.scalar then
		tint(world, id, settings.beam_value)
		return
	end
	if not World.are_particles_playing(world, id) then
		return
	end
	local colour = Vector3(settings.beam_r, settings.beam_g, settings.beam_b)
	for i = 1, spec.clouds do
		local cloud = FLASH_CLOUDS[i]
		if World.has_particles_material(world, id, cloud) then
			World.set_particles_material_vector3(world, id, cloud, spec.variable, colour)
		end
	end
end

local instances = setmetatable({}, { __mode = "k" })
local broken = false

local function beam_asset()
	local ok, mission = pcall(function()
		return Managers.state.mission:mission()
	end)
	if ok and mission and mission.zone_id == "dust" then
		return OUTDOOR_BEAM
	end
	return INDOOR_BEAM
end

local function destroy_dots(entry)
	local dots = entry.dots
	for i = 1, #dots do
		pcall(World.destroy_particles, entry.world, dots[i])
		dots[i] = nil
	end
end

function wave.update(orig_update, template_data, template_context, dt, t)
	if broken then
		orig_update(template_data, template_context, dt, t)
		return
	end
	local entry = instances[template_data]
	if not entry then
		entry = { phase = 0, dots = {}, effect_name = beam_asset(), world = template_context.world }
		instances[template_data] = entry
	end

	local particle_id = template_data.particle_id
	local variable_index = template_data.variable_index
	local muzzle_pos = nil
	local beam_rot = nil
	local beam_length = nil

	local orig_move = World.move_particles
	local orig_set = World.set_particles_variable
	World.move_particles = function(world, id, position, rotation)
		if id == particle_id then
			muzzle_pos = position
			beam_rot = rotation
		end
		return orig_move(world, id, position, rotation)
	end
	World.set_particles_variable = function(world, id, index, value)
		if id == particle_id and index == variable_index then
			beam_length = value.y
			local thickness = settings.beam_thickness
			if thickness > 0 then
				value = Vector3(value.x * thickness, value.y, value.z * thickness)
			else
				value = Vector3(value.x, HIDDEN_LENGTH, value.z)
			end
		end
		return orig_set(world, id, index, value)
	end
	local ok, err = pcall(orig_update, template_data, template_context, dt, t)
	World.move_particles = orig_move
	World.set_particles_variable = orig_set
	if not ok then
		broken = true
		destroy_dots(entry)
		instances[template_data] = nil
		mod:error("Redshift wave: update failed, vanilla beam for the rest of this session (%s)", tostring(err))
		return
	end
	if not (muzzle_pos and beam_rot and beam_length) then
		return
	end

	local pitch = settings.dot_length + settings.dot_gap
	local count = math_floor(beam_length / pitch) + 1
	if count > MAX_DOTS then
		count = MAX_DOTS
		pitch = beam_length / MAX_DOTS
	end
	entry.phase = (entry.phase + dt * settings.dot_speed) % pitch

	local world = template_context.world
	local forward = Quaternion.forward(beam_rot)
	local recolour = settings.recolour
	local dot_value = settings.dot_value
	if recolour then
		tint(world, particle_id, settings.beam_value)
	end
	local dots = entry.dots
	for i = 1, count do
		local id = dots[i]
		if not id then
			local ok_create, new_id = pcall(World.create_particles, world, entry.effect_name, muzzle_pos, beam_rot)
			if not ok_create then
				break
			end
			dots[i] = new_id
			id = new_id
		end
		local offset = entry.phase + (i - 1) * pitch
		local length = settings.dot_length
		if offset >= beam_length then
			length = HIDDEN_LENGTH
			offset = 0
		elseif offset + length > beam_length then
			length = beam_length - offset
		end
		pcall(orig_move, world, id, muzzle_pos + forward * offset, beam_rot)
		pcall(orig_set, world, id, variable_index, Vector3(DOT_WIDTH, length, DOT_DEPTH))
		if recolour and length > HIDDEN_LENGTH then
			tint(world, id, dot_value)
		end
	end
	for i = count + 1, #dots do
		pcall(orig_set, world, dots[i], variable_index, Vector3(DOT_WIDTH, HIDDEN_LENGTH, DOT_DEPTH))
	end
end

function wave.on_laser_stop(template_data)
	local entry = instances[template_data]
	if entry then
		destroy_dots(entry)
		instances[template_data] = nil
	end
end

function wave.teardown()
	for template_data, entry in pairs(instances) do
		destroy_dots(entry)
		instances[template_data] = nil
	end
end

wave.refresh_settings()

return wave
