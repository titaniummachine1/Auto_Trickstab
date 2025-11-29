# Auto_Trickstab

![Visitors](https://api.visitorbadge.io/api/visitors?path=https%3A%2F%2Fgithub.com%2Ftitaniummachine1%2FAuto_Trickstab&label=Visitors&countColor=%23263759&style=plastic)  
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Auto_Trickstab is a small Lua script for Lmaobox that automates trickstabs by detecting safe warp positions behind or to the side of enemies and performing a backstab when possible.

Important: This script REQUIRES the following two Lua libraries. It will NOT work without them:
- lnxLib (v1.00.0): https://github.com/lnx00/Lmaobox-Library/releases/download/v1.00.0/lnxLib.lua
- TimMenu (v1.8.4): https://github.com/titaniummachine1/TimMenu/releases/download/v1.8.4/TimMenu.lua

Download the latest release:
[Download Latest](https://github.com/titaniummachine1/Auto_Trickstab/releases/latest/download/Auto.Trickstab.lua)

Screenshot
![Auto Trickstab Preview](https://github.com/titaniummachine1/Auto_Trickstab/assets/78664175/bf32fbb5-cb37-4c75-9c89-90be1c46bb68)

---

## Features
- Automatic configuration system (loads and saves settings automatically).
- Automatic warp-behind or warp-to-side detection.
- Automatically detects when a safe backstab is possible and warps to execute it.
- Minimal UI via TimMenu.

## Description
Auto_Trickstab helps you perform reliable trickstabs by checking positions and performing the warp+backstab when safe. It is intended to be simple and lightweight.

## Requirements
- Lmaobox (compatible with the stable Lmaobox version current at the time of the script). If you use a fork or a very old/new version of Lmaobox, compatibility is not guaranteed.
- lnxLib v1.00.0 — required helper library.
- TimMenu v1.8.4 — required menu helper.

Links:
- lnxLib: https://github.com/lnx00/Lmaobox-Library/releases/download/v1.00.0/lnxLib.lua
- TimMenu: https://github.com/titaniummachine1/TimMenu/releases/download/v1.8.4/TimMenu.lua

## Installation
1. Download these files:
   - Auto.Trickstab.lua (this script)
   - lnxLib.lua (link above)
   - TimMenu.lua (link above)
2. Place `lnxLib.lua` and `TimMenu.lua` in your Lmaobox `lua` folder (the same folder where other scripts and libs are stored).
   - Example: <Lmaobox_install_folder>/lua/
3. Place `Auto.Trickstab.lua` where you normally keep your scripts (also in the `lua` folder or where Lmaobox expects scripts).
4. Do NOT manually require/load `lnxLib.lua` or `TimMenu.lua` from other scripts — they should be present in the `lua` folder so Auto_Trickstab can load them automatically.
5. Launch Lmaobox and load `Auto.Trickstab.lua` via the scripts menu.

Tip: If you see an error like "failed to load lnxlib", double-check that the file is named exactly `lnxLib.lua` and is located in the `lua` folder.

## Usage
- Load the script from your scripts menu in Lmaobox.
- Configure options using TimMenu in-game. The script saves and loads your configuration automatically.

## Troubleshooting / FAQ

Q: "It doesn't work" / "There are no errors at startup"  
A: If there are no console errors at startup but the functionality feels absent:
- Confirm that `lnxLib.lua` and `TimMenu.lua` are placed in the correct `lua` folder (not inside subfolders unless Lmaobox expects that).
- Make sure you only load `Auto.Trickstab.lua`. Do not manually load the dependency libs in addition to this script.
- Open the game console and look for messages from `Auto_Trickstab`. If there are no messages, the script might not be loading — check that the script filename matches and that your scripts menu shows it.

Q: "Failed to load lnxlib"  
A:
- Ensure the file is named `lnxLib.lua` (case-sensitive on some systems) and is the correct version.
- Place it in the same `lua` folder as other script libraries.
- Do not attempt to `require` or load it manually from other scripts; simply let Auto_Trickstab load it.

Q: "Do I need a beta Lmaobox build?"  
A: Auto_Trickstab targets the stable Lmaobox API. If you use a very new or forked client, compatibility might vary. If unsure, provide the exact Lmaobox version and any console errors when reporting an issue.

Q: "Where do I put the files?"  
A: Put `lnxLib.lua` and `TimMenu.lua` in the main `lua` folder for Lmaobox. Put `Auto.Trickstab.lua` alongside your other scripts. Example:
```
<Lmaobox root>/lua/lnxLib.lua
<Lmaobox root>/lua/TimMenu.lua
<Lmaobox root>/lua/Auto.Trickstab.lua
```

## Reporting Issues — please include:
If something isn't working, please open an issue and include:
- Lmaobox version (exact string).
- Exact filenames and their locations on disk.
- Full console output / error messages (copy-paste).
- Steps to reproduce.
- Screenshot or short video (optional).
This information makes it much easier to debug and avoids repeated clarifying questions.

If you want a helpful template, paste this into a new issue:
- Lmaobox version:
- Files and paths:
- Exact console errors (if any):
- Steps to reproduce:
- Anything you tried already:

## Contact
If you need quick help, message me on Telegram: https://t.me/TerminatorMachine

## License
MIT License — see LICENSE file for details.

---
Changelog (high-level)
- v1.0 — Initial release: automatic warp and backstab detection; auto config system.

Thanks for using Auto_Trickstab! If you want this README committed to the repo with a PR, tell me the branch name and I can prepare a commit for you.
```
