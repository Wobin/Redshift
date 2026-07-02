local mod = get_mod("Redshift")

return {
	name = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id = "dot_length",
				type = "numeric",
				default_value = 1,
				range = { 0.2, 2 },
				decimals_number = 1,
			},
			{
				setting_id = "dot_gap",
				type = "numeric",
				default_value = 0.5,
				range = { 0.2, 2 },
				decimals_number = 1,
			},
			{
				setting_id = "dot_speed",
				type = "numeric",
				default_value = 7,
				range = { 2, 20 },
				decimals_number = 0,
			},
		},
	},
}
