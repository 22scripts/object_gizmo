fx_version 'cerulean'
game 'gta5'
lua54 'yes'
author '22scripts, xLaugh'
version '3.0.0beta'

escrow_ignore {
    'client/*.lua',
    'html/*',
    'locales/*.json',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'locales/*.json',
}

shared_scripts {
    '@ox_lib/init.lua',
}

client_scripts {
    'client/camera.lua',
    'client/gizmo.lua',
    'client/test.lua',
}

dependencies {
    'ox_lib',
}

