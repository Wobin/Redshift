--[[
	Name: Redshift
	Author: Wobin
	URL: https://www.github.com/Wobin/Redshift
	Date: 27/09/2026
]]--

local mod = get_mod("Redshift")
mod.version = mod.get_metadata and mod:get_metadata("version") or "unknown"

local wave = mod:io_dofile("Redshift/scripts/mods/Redshift/modules/wave")

local asset_redirect = mod:io_dofile("Redshift/scripts/mods/Redshift/asset_redirect")
local REDIRECT_CONTRACT = "polychromatic_jet/live_hsv"
local REDIRECTS = {
	{ stock = "data/00/0028686adad0c743", file = "payload/0028686adad0c743.livehsv", sha256 = "9718ee668c306c2a0ecad99fa4a7f904af6ee52b478cec288532e02f0c4a2840" },
	{ stock = "0f9a5678bd0a3560", file = "payload/0f9a5678bd0a3560.pyro", sha256 = "f1906429db4cc8409bb06c64bf2260fd25ac80d82a1fc7b5844a45a16380f3b6" },
	{ stock = "76a1b3d86421bc64", file = "payload/76a1b3d86421bc64.pyro", sha256 = "3758f36171fac9c343b4414e3c949ccee038d83ef79c8a70ba9dd68266e5ac80" },
	{ stock = "data/94/943d1b280637fc01", file = "payload/943d1b280637fc01.livehsv", sha256 = "46b846d2261aa4dd0b68cb6c3de9ca5d57a8c7f6fb011d3eee740559bce08fcc" },
	{ stock = "5e2f514ce9a3a638", file = "payload/5e2f514ce9a3a638.pyro", sha256 = "b863b16890913d01c8426240978210c430bc3e7c09dc9ee8b4e911e1558121d0" },
	{ stock = "4cc74ef319030258", file = "payload/4cc74ef319030258.pyro", sha256 = "0c3715740bc3c3c00213bf37ad155fd79d675222db34e1aa35519c9119d7368c" },
	{ stock = "cadc4aad69c172b6", file = "payload/cadc4aad69c172b6.pyro", sha256 = "2ff8f632ee2e3dafeb584e627335d6039093ce4d309fce08f22cb87c0e31d340" },
	{ stock = "4a5ab95b41bb65a4", file = "payload/4a5ab95b41bb65a4.pyro", sha256 = "88760b6da1d1dc31ad76a3ddf9fdc7184647f8c7c602be03ba761fdfbe9a89ff" },
}
local _redirect_handles = {}
local _redirect_reported = {}
local _redirect_waiting = false

if asset_redirect then
	for i = 1, #REDIRECTS do
		local entry = REDIRECTS[i]

		_redirect_handles[i] = asset_redirect.register(mod, {
			stock = entry.stock,
			file = entry.file,
			sha256 = entry.sha256,
			priority = 0,
			contract = REDIRECT_CONTRACT,
		})
	end
end

local function report_redirects()
	local settled = true
	local restart = false

	for i = 1, #_redirect_handles do
		if not _redirect_reported[i] then
			local state = asset_redirect.state(_redirect_handles[i])

			if state == "pending" then
				settled = false
			else
				_redirect_reported[i] = true

				mod:info("redirect %s: %s", REDIRECTS[i].stock, state)

				restart = restart or state == "restart_required"
			end
		end
	end

	if restart then
		mod:echo(mod:localize("restart_required"))
	end

	return settled
end

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
-- Spawn tint
-- ─────────────────────────────────────────────

mod:hook(World, "create_particles", function(func, world, effect_name, ...)
	local particle_id = func(world, effect_name, ...)
	if particle_id then
		wave.tint_spawn(world, effect_name, particle_id)
	end
	return particle_id
end)

-- ─────────────────────────────────────────────
-- Lifecycle
-- ─────────────────────────────────────────────

mod.on_all_mods_loaded = function()
	wrap_template()
	mod:info("Redshift " .. tostring(mod.version) .. " loaded")

	if not asset_redirect then
		return
	end

	asset_redirect.commit()

	_redirect_waiting = not report_redirects()
end

mod.update = function()
	if not _redirect_waiting then
		return
	end

	if asset_redirect.ready() then
		_redirect_waiting = false

		report_redirects()
	end
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


mod.on_settings_reset = function()
	mod.on_setting_changed()
end