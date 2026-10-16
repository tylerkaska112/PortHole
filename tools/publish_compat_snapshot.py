#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 The Porthole authors. See LICENSE.
"""Writes the public compatibility reports to compat.json in the Porthole website repo, so the site can show them without talking to the Hub.

    python3 tools/publish_compat_snapshot.py [--site ~/Desktop/porthole-site] [--hub http://127.0.0.1:8092] [--push]

Only what the Hub already serves publicly is written (approved comments only; reports whose source is "other" are never served). Without --push the
file is written and nothing else happens; with --push it is committed and pushed, which updates the live site within a minute or two.
"""
import argparse, datetime, json, os, re, subprocess, sys, urllib.parse, urllib.request

# Marketing names for models an older build of the app did not know (it then sent "iPad, model iPad16,5").
KNOWN = {
    "iPad16,3": "iPad Pro 11-inch (M4)", "iPad16,4": "iPad Pro 11-inch (M4)", "iPad16,5": "iPad Pro 13-inch (M4)", "iPad16,6": "iPad Pro 13-inch (M4)",
    "iPad14,8": "iPad Air 11-inch (M2)", "iPad14,9": "iPad Air 11-inch (M2)", "iPad14,10": "iPad Air 13-inch (M2)", "iPad14,11": "iPad Air 13-inch (M2)",
    "iPad15,3": "iPad Air 11-inch (M3)", "iPad15,4": "iPad Air 11-inch (M3)", "iPad15,5": "iPad Air 13-inch (M3)", "iPad15,6": "iPad Air 13-inch (M3)",
    "iPad16,1": "iPad mini (A17 Pro)", "iPad16,2": "iPad mini (A17 Pro)",
}

def nice(name, device_id):
    return KNOWN.get(device_id, name) if ", model " in name else name

def current_engine(site=None):
    """The engine this source builds (app/Config/Engine.xcconfig). Badges on the site are for it; reports from other engines are listed as earlier ones.
    When that file cannot be read (the hourly job runs outside the project folder), the engine of the snapshot already on the site is kept; running
    this tool by hand from the project after an engine bump moves the site to the new one."""
    conf = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "app", "Config", "Engine.xcconfig")
    try:
        m = re.search(r"^PORTHOLE_ENGINE_ID\s*=\s*(\S+)", open(conf).read(), re.M)
        if m: return m.group(1)
    except OSError:
        pass
    try:
        with open(os.path.join(site, "compat.json")) as f: return json.load(f)["engine"]
    except (OSError, ValueError, KeyError, TypeError):
        sys.exit("no PORTHOLE_ENGINE_ID in app/Config/Engine.xcconfig and no engine in the site's compat.json")

def get(hub, path):
    with urllib.request.urlopen(hub + path, timeout=20) as r:
        return json.load(r)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--site", default=os.path.expanduser("~/Desktop/porthole-site"))
    ap.add_argument("--hub", default="http://127.0.0.1:8092")
    ap.add_argument("--reports", type=int, default=20, help="newest reports kept per game")
    ap.add_argument("--push", action="store_true")
    args = ap.parse_args()

    engine = current_engine(args.site)
    games, offset = [], 0
    while True:
        page = get(args.hub, f"/compat/games?sort=reports&limit=100&offset={offset}&engine={engine}")
        games += page
        if len(page) < 100: break
        offset += 100

    out = []
    for g in games:
        enc = urllib.parse.quote(g["id"], safe="")
        detail = get(args.hub, f"/compat/games/{enc}?engine={engine}")
        reports = get(args.hub, f"/compat/games/{enc}/reports?limit={min(args.reports, 50)}&engine={engine}")
        out.append({
            "id": g["id"], "title": g["title"], "kind": g["kind"], "steamAppID": g.get("steamAppID"),
            "reportCount": g["reportCount"], "lastReport": g["lastReport"],
            "verdict": (g["badge"].get("overall") or {}).get("verdict"), "confidence": (g["badge"].get("overall") or {}).get("confidence"),
            "countedReports": (g["badge"].get("overall") or {}).get("reports", 0), "earlierReports": (g["badge"].get("earlier") or {}).get("reports", 0),
            "devices": [{"device": nice(d["device"], d["deviceId"]), "verdict": d["verdict"], "reports": d["reports"]} for d in detail.get("devices", [])],
            "settingsSummary": detail.get("settingsSummary"),
            "reports": [dict({k: r.get(k) for k in ("ios", "appVersion", "engine", "onThisEngine", "rating", "stability", "tags", "source", "perf", "settings", "comment", "date")}, device=nice(r["device"], r["deviceId"])) for r in reports],
        })

    snapshot = {"generated": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC"), "engine": engine, "games": out}
    path = os.path.join(args.site, "compat.json")
    # Run on a schedule, this must not commit a new timestamp every time: when nothing but the time changed, leave the file alone.
    try:
        with open(path) as f: previous = json.load(f)
        if {k: v for k, v in previous.items() if k != "generated"} == {k: v for k, v in snapshot.items() if k != "generated"}:
            print(f"no changes: {len(out)} game(s), {sum(g['reportCount'] for g in out)} report(s)")
            return
    except (OSError, ValueError):
        pass
    with open(path, "w") as f:
        json.dump(snapshot, f, indent=1, ensure_ascii=False); f.write("\n")
    print(f"wrote {path}: {len(out)} game(s), {sum(g['reportCount'] for g in out)} report(s)")

    if args.push:
        run = lambda *a: subprocess.run(a, cwd=args.site, check=True, capture_output=True, text=True)
        run("git", "add", "compat.json")
        if run("git", "status", "--porcelain", "compat.json").stdout.strip():
            run("git", "commit", "-m", f"Compatibility snapshot {snapshot['generated']}")
            run("git", "push", "-q", "origin", "main")
            print("committed and pushed")
        else:
            print("no changes to publish")

if __name__ == "__main__":
    try: main()
    except Exception as e: sys.exit(f"snapshot failed: {e}")
