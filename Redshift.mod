return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`Redshift` encountered an error loading the Darktide Mod Framework.")

		new_mod("Redshift", {
			mod_script       = "Redshift/scripts/mods/Redshift/Redshift",
			mod_data         = "Redshift/scripts/mods/Redshift/Redshift_data",
			mod_localization = "Redshift/scripts/mods/Redshift/Redshift_localization",
		})
	end,
	version = "1.0.0",
	packages = {},
}
