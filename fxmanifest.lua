fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'FGizmo'
author 'Firgyy'
version '1.0.0'

escrow_ignore {
	'client/camera.lua',
	'client/gizmo.lua',
	'client/test.lua',
}

client_scripts {
	'client/camera.lua',
	'client/gizmo.lua',
	'client/test.lua',
}

shared_scripts {
	'@ox_lib/init.lua',
}

ui_page 'html/index.html'

files {
	'locales/*.json',
	'html/index.html',
	'html/style.css',
	'html/app.js',
}

dependencies {
	'ox_lib',
}
