# Poggy's Balloon - Enhanced Hot Air Balloon System for RedM

An improved hot air balloon system for RedM that enhances the balloon flight experience with proper animations, multiple passenger support, and improved controls. No more passengers ragdolling in the basket and captains awkwardly standing still!

![Poggy's Balloon](https://media.discordapp.net/attachments/1294984490757652552/1372968546526695424/thumbnail_1.jpg?ex=6828b41a&is=6827629a&hm=e86f6c68db76cc006737cab2d3922ec86299414c7398c310c5f2d46e1a1ba9f6&=&format=webp)

## Features

- **Enhanced Balloon Controls**: Camera-relative movement options make flying more intuitive
- **Multiple Passenger Support**: Up to 4 passengers can ride in the balloon basket safely
- **Captain Animation System**: Realistic burner pull animation with rope visual
- **Passenger Animations**: Proper sitting animations for passengers
- **Altitude Lock**: Lock balloon height for stable horizontal navigation
- **Invisible Safety Floor**: Prevents passengers from ragdolling inside the basket
- **Server Synchronization**: All players see consistent passenger positions and animations
- **Prompt System**: Clear UI prompts for entering/exiting and controlling the balloon
- **Boost & Brake Controls**: Fine-tune your balloon's speed with dedicated controls

## Dependencies

- **RedM Native UI**: For prompt system (included)
- Base RedM server with the hot air balloon model enabled

## Installation

1. Extract the `poggy-balloon` folder into your server's `resources` directory
2. Add `ensure poggy-balloon` to your server.cfg
3. Restart your server

## How It Works

### For Captains:
1. Enter the balloon as normal using the game's vehicle entry system
2. Use the following controls while piloting:
   - **W/S**: Move forward/backward 
   - **A/D**: Move left/right 
   - **Space**: Ascend
   - **F**: Boost (increase speed)
   - **R**: Brake (slow down)
   - **SPACE**: Toggle altitude lock (maintain current height)

### For Passengers:
1. Approach a balloon and press **F** when prompted to enter as a passenger
2. Press **F** again to exit the balloon
3. Up to 4 passengers can ride in designated positions in the basket

## Debugging

The script includes comprehensive debugging capabilities:

- **/balloon_debug_main [level|toggle|status]**: Control debug output for main module
- **/balloon_debug_anim [level|toggle]**: Control debug output for animation module
- **/balloon_debug_ctrl [level|toggle]**: Control debug output for controls module
- **/balloon_server_status**: View current balloon occupancy (admin only)

Debug levels range from 0 (OFF) to 4 (DEBUG), with 3 (INFO) as the default when enabled.

## Technical Details

### Passenger System
The system uses server-side seat tracking to ensure consistent passenger placement across all clients. When a player requests to enter as a passenger, the server confirms seat availability before allowing entry.

### Animation System
- **Captains**: Animated burner controls with rope visuals that respond to ascent input
- **Passengers**: Proper sitting animations to prevent awkward T-poses in the basket

### Control Enhancement
The original balloon controls are enhanced with camera-relative movement, allowing players to move in the direction they're facing rather than fixed compass directions. 

## Credits

This resource combines and enhances code from:
- [kibook's side saddle](https://github.com/kibook/redm-sidesaddle)
- [kibook's balloon control scripts](https://github.com/kibook/redm-ballooncontrols)
- [PersePixel's balloon crap](https://github.com/PersePixels/balloon-crap)

## License & Legal

This is a free resource, modified from other open source projects.
Feel free to use and modify for your server, but please credit the original authors.

## Video Example

https://medal.tv/games/red-dead-2/clips/kizULvk7B3R3miNy1?invite=cr-MSxvUzMsMjcwNjc4MTcx