-- ─────────────────────────────────────────────
-- Redshift wave module
-- ─────────────────────────────────────────────

local mod = get_mod("Redshift")

local World = World
local Vector3 = Vector3
local Quaternion = Quaternion
local math_floor = math.floor

local HIDDEN_LENGTH = 0.01
local DOT_WIDTH = 0.05
local DOT_DEPTH = 0.5
local MAX_DOTS = 24

local INDOOR_BEAM = "content/fx/particles/enemies/sniper_laser_sight"
local OUTDOOR_BEAM = "content/fx/particles/enemies/renegade_sniper/renegade_sniper_beam_outdoors"

local wave = {}

local settings = { dot_length = 1, dot_gap = 0.5, dot_speed = 7 }

function wave.refresh_settings()
	settings.dot_length = mod:get("dot_length") or 1
	settings.dot_gap = mod:get("dot_gap") or 0.5
	settings.dot_speed = mod:get("dot_speed") or 7
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
			value = Vector3(value.x, HIDDEN_LENGTH, value.z)
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
