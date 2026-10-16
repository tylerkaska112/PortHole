#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 The Porthole authors. See LICENSE.
"""Generate Madeira touch-control layouts for Factorio -> factorio-presets.json (Madeira's madeira-control-presets.json format, version 1).

Keys are Windows virtual-key codes. Factorio's keys are rebindable in-game, so these follow Factorio's DEFAULT bindings; change KEYS below if yours differ.
Positions are normalised (0-1 of the landscape screen). The overlay reserves a 200x76pt band at top-centre for its own buttons: keep it clear.
Not included on purpose: hotbar numbers (Factorio's own hotbar is tappable) and anything I am not sure is a default binding.
"""
import json, uuid, sys

def key(vk):  return {"key": {"_0": vk}}
WASD = {"joystickWASD": {}}
LMB  = {"mouseLeft": {}}
RMB  = {"mouseRight": {}}
KBD  = {"keyboardToggle": {}}

# name -> (action, nx, ny, scale)   (iPad 13in layout; right thumb cluster, left thumb stick)
def layout(tablet):
    s = 1.0 if tablet else 0.85
    return [
        ("WASD move",   WASD,        0.11, 0.74, 1.5 * s),
        ("Shift",       key(0x10),   0.05, 0.40, 0.8 * s),
        ("Ctrl",        key(0x11),   0.05, 0.27, 0.8 * s),
        ("Alt",         key(0x12),   0.05, 0.14, 0.8 * s),
        ("Right click", RMB,         0.93, 0.74, 1.1 * s),
        ("R rotate",    key(0x52),   0.86, 0.56, 0.9 * s),
        ("Q pipette",   key(0x51),   0.93, 0.52, 0.9 * s),
        ("E inventory", key(0x45),   0.80, 0.74, 0.9 * s),
        ("Space",       key(0x20),   0.80, 0.90, 0.9 * s),
        ("Map",         key(0x4D),   0.95, 0.12, 0.7 * s),
        ("Tech",        key(0x54),   0.95, 0.24, 0.7 * s),
        ("Esc",         key(0x1B),   0.05, 0.90, 0.7 * s),
        ("Keyboard",    KBD,         0.95, 0.36, 0.7 * s),
    ]

def preset(pid, name, tablet):
    return {"id": pid, "name": name,
            "controls": [{"id": str(uuid.uuid5(uuid.NAMESPACE_URL, pid + n)).upper(), "nx": x, "ny": y, "scale": round(sc, 3), "action": a}
                         for (n, a, x, y, sc) in layout(tablet)]}

out = {"version": 1, "presets": [preset("user.factorio.ipad", "Factorio iPad", True),
                                 preset("user.factorio.iphone", "Factorio iPhone", False)]}
json.dump(out, open(sys.argv[1] if len(sys.argv) > 1 else "factorio-presets.json", "w"), indent=2, sort_keys=True)
print("wrote", len(out["presets"]), "layouts,", len(out["presets"][0]["controls"]), "controls each")
