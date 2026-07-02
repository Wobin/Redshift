--[[
	Name: Redshift
	Author: Wobin
	URL: https://www.github.com/Wobin/Redshift
	Date: 03/07/2026
	Version: 1.1.0
]]--

local mod = get_mod("Redshift")
mod.version = "1.1.0"

local wave = mod:io_dofile("Redshift/scripts/mods/Redshift/modules/wave")

local TEMPLATE_PATH = "scripts/settings/fx/effect_templates/renegade_sniper_laser"

-- ─────────────────────────────────────────────
-- Effect template wrap
-- ─────────────────────────────────────────────

local function get_template()
	local ok, template = pcall(require, TEMPLATE_PATH)
	if ok and type(template) == "table" and template.name == "renegade_sniper_laser" then
		return template
	end
	return nil
end

local function unwrap_template()
	local template = get_template()
	if not template then
		return
	end
	local orig = rawget(template, "__redshift_orig")
	if orig then
		if orig.start then
			template.start = orig.start
		end
		template.update, template.stop = orig.update, orig.stop
		template.__redshift_orig = nil
	end
end

local function wrap_template()
	local template = get_template()
	if not template then
		mod:error("Redshift: could not resolve the sniper laser effect template")
		return
	end
	unwrap_template()
	local orig = { update = template.update, stop = template.stop }
	template.__redshift_orig = orig

	template.update = function(template_data, template_context, dt, t)
		if mod:is_enabled() then
			wave.update(orig.update, template_data, template_context, dt, t)
		else
			orig.update(template_data, template_context, dt, t)
		end
	end
	template.stop = function(template_data, template_context)
		pcall(wave.on_laser_stop, template_data)
		orig.stop(template_data, template_context)
	end

	mod:info("Redshift: sniper laser template wrapped")
end

-- ─────────────────────────────────────────────
-- Lifecycle
-- ─────────────────────────────────────────────

mod.on_all_mods_loaded = function()
	wrap_template()
	mod:info("Redshift " .. tostring(mod.version) .. " loaded")
end

mod.on_unload = function()
	wave.teardown()
	unwrap_template()
end

mod.on_disabled = function()
	wave.teardown()
end

mod.on_game_state_changed = function(status, state_name)
	if status == "exit" and state_name == "StateGameplay" then
		wave.teardown()
	end
end

mod.on_setting_changed = function()
	wave.refresh_settings()
end
