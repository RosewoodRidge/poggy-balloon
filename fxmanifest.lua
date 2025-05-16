fx_version "adamant"
games {"rdr3"}
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
author 'Poggy (original by Persepixels)'
description 'Some balloon related scripts'
lua54 'yes'

client_scripts {
    "@uiprompt/uiprompt.lua",
    'client/balloon_controls.lua',
    'client/balloon.lua',
    'client/balloonanimations.lua',
}

server_scripts {
    'server/balloon_server.lua'
}