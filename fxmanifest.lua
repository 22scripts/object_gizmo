fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'FGizmo'
author 'Firgyy'
version '2.0.0'

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
