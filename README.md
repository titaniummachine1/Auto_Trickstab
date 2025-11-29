# Auto_Trickstab

[![Visitors](https://api.visitorbadge.io/api/visitors?path=https://github.com/titaniummachine1/Auto_Trickstab\&label=Visitors\&countColor=%23263759\&style=plastic)]()
[![Release](https://img.shields.io/github/v/release/titaniummachine1/Auto_Trickstab?style=flat-square)]()
[![Downloads](https://img.shields.io/github/downloads/titaniummachine1/Auto_Trickstab/total?style=flat-square)]()
[![License](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](https://opensource.org/licenses/MIT)

A lightweight Lua script for **Lmaobox** that automates trickstabs by detecting safe warp angles behind or beside enemies and executing the backstab automatically.
Nothing fancy — just consistent and reliable trickstab automation.

---

## 🚀 Features (clear + essential)

* Auto-detects safe warp-behind / warp-side positions.
* Executes warp → backstab only when safe.
* Fully auto-saving configuration system.
* Minimalistic in-game menu (TimMenu).
* Zero manual setup beyond dropping the files.

---

## 📦 Required Libraries (MUST HAVE)

These two **must exist in your `lua/` folder** or the script will *not load*:

* **lnxLib v1.00.0**
  [https://github.com/lnx00/Lmaobox-Library/releases/download/v1.00.0/lnxLib.lua](https://github.com/lnx00/Lmaobox-Library/releases/download/v1.00.0/lnxLib.lua)

* **TimMenu v1.8.4**
  [https://github.com/titaniummachine1/TimMenu/releases/download/v1.8.4/TimMenu.lua](https://github.com/titaniummachine1/TimMenu/releases/download/v1.8.4/TimMenu.lua)

---

## ⬇️ Download

**Latest Release:**
[https://github.com/titaniummachine1/Auto_Trickstab/releases/latest/download/Auto.Trickstab.lua](https://github.com/titaniummachine1/Auto_Trickstab/releases/latest/download/Auto.Trickstab.lua)

---

## 📸 Preview

https://github.com/user-attachments/assets/d0a8e074-a9ba-4b31-ad9f-facd144148fe

---

## 🛠️ Installation (simple, not padded)

Place the files exactly like this:

```
<Lmaobox>/lua/lnxLib.lua
<Lmaobox>/lua/TimMenu.lua
<Lmaobox>/lua/Auto.Trickstab.lua
```

**Do NOT require() these manually.**
Just load Auto.Trickstab.lua in Lmaobox — it loads its own dependencies.

If the script “does nothing”, 99% of the time it’s because:

* wrong filenames
* wrong folder
* missing libs
* using an experimental Lmaobox build

---

## ❓ Quick Troubleshooting

### ❌ “Failed to load lnxlib”

* File must be named **lnxLib.lua** (case-sensitive for some users)
* Must be in `lua/`
* Must be *exact* v1.00.0

### ❌ Script loads but doesn’t work

* Confirm libs are in the same `lua/` folder
* Check game console for Auto_Trickstab logs
* Make sure you didn’t try to `require()` the libs manually
* Confirm your Lmaobox version is stable, not a forked beta

---

## 🐞 Reporting Issues (don’t waste time)

Include these **every time**:

* Lmaobox version (exact string)
* File paths
* Console output
* Steps to reproduce
* Screenshot/video if possible

Template:

```
Lmaobox version:
Files + paths:
Errors (copy-paste):
Steps to reproduce:
What you've already tried:
```

---

## 📬 Contact

Telegram (fastest): **[https://t.me/TerminatorMachine](https://t.me/TerminatorMachine)**

---

## 📄 License

MIT License — see LICENSE.

---

## 📘 Changelog (high level)

* **v1.0** — First release: warp+stab logic, config system.

---

If you want, I can also:

✅ generate a **clean badge row** with more metrics (stars, forks, last commit, code size)
✅ prepare a **commit-ready PR patch**
✅ restructure the repo to look like a professional Lua project
✅ add icons, video previews, GIFs, or a features comparison chart

Just tell me what style you want — brutal minimal, flashy GitHub-pro, or ultra-organized dev-friendly.
