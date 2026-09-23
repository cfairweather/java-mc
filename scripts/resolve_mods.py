#!/usr/bin/env python3
"""Resolve mods/mods.txt against the Modrinth API into pinned, reproducible outputs.

Outputs (all generated, all committed):
  mods/lock.json               every resolved file with version id, URL and hashes
  mods/server-mods.core.txt    itzg MODRINTH_PROJECTS listing, core profile
  mods/server-mods.full.txt    itzg MODRINTH_PROJECTS listing, full profile
  mods/versions.env            VERSION / FABRIC_LOADER_VERSION for compose + terraform

Usage: scripts/resolve_mods.py [--game-version 26.2] [--check]
  --check  exit non-zero if regenerating would change any output (used by CI)
"""
import argparse
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODS_TXT = ROOT / "mods" / "mods.txt"
LOCK = ROOT / "mods" / "lock.json"
VERSIONS_ENV = ROOT / "mods" / "versions.env"
API = "https://api.modrinth.com/v2"
FABRIC_META = "https://meta.fabricmc.net/v2/versions/loader"
UA = "cfairweather/java-mc resolve_mods (github.com/cfairweather/java-mc)"
PROFILES = ("core", "full")
SIDES = ("server", "client", "both")


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    for attempt in range(5):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < 4:
                time.sleep(2 ** attempt)
                continue
            raise
    raise RuntimeError(f"gave up on {url}")


def parse_mods_txt():
    entries = []
    for lineno, raw in enumerate(MODS_TXT.read_text().splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) < 3:
            sys.exit(f"{MODS_TXT}:{lineno}: expected '<slug> <side> <profile> [datapack]'")
        slug, side, profile = parts[:3]
        flags = set(parts[3:])
        if side not in SIDES or profile not in PROFILES or not flags <= {"datapack"}:
            sys.exit(f"{MODS_TXT}:{lineno}: bad side/profile/flag in '{raw}'")
        entries.append({"slug": slug, "side": side, "profile": profile, "datapack": "datapack" in flags})
    return entries


def pick_version(project_id, game_version, loader):
    q = urllib.parse.urlencode({
        "game_versions": json.dumps([game_version]),
        "loaders": json.dumps([loader]),
    })
    versions = get(f"{API}/project/{project_id}/version?{q}")
    # API returns newest first; prefer releases, fall back to beta, then alpha.
    for vtype in ("release", "beta", "alpha"):
        for v in versions:
            if v["version_type"] == vtype:
                return v
    return None


def merge_side(a, b):
    if a == b:
        return a
    return "both"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--game-version", default=None, help="defaults to value in mods/versions.env or 26.2")
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    game_version = args.game_version
    if game_version is None and VERSIONS_ENV.exists():
        for line in VERSIONS_ENV.read_text().splitlines():
            if line.startswith("VERSION="):
                game_version = line.split("=", 1)[1].strip()
    game_version = game_version or "26.2"

    wanted = parse_mods_txt()
    resolved = {}  # project_id -> entry
    queue = []

    print(f"Resolving {len(wanted)} mods for Minecraft {game_version} / Fabric", file=sys.stderr)
    for w in wanted:
        proj = get(f"{API}/project/{w['slug']}")
        queue.append((proj, w["side"], w["profile"], w["datapack"], None))

    missing = []
    while queue:
        proj, side, profile, is_datapack, dep_of = queue.pop(0)
        pid = proj["id"]
        if pid in resolved:
            e = resolved[pid]
            e["side"] = merge_side(e["side"], side)
            if profile == "core":
                e["profile"] = "core"  # core is the superset requirement
            if dep_of and dep_of not in e["dependency_of"]:
                e["dependency_of"].append(dep_of)
            continue
        loader = "datapack" if is_datapack else "fabric"
        v = pick_version(pid, game_version, loader)
        if v is None:
            missing.append(f"{proj['slug']} ({loader})" + (f" required by {dep_of}" if dep_of else ""))
            continue
        primary = next((f for f in v["files"] if f["primary"]), v["files"][0])
        entry = {
            "slug": proj["slug"],
            "title": proj["title"],
            "project_id": pid,
            "version_id": v["id"],
            "version_number": v["version_number"],
            "version_type": v["version_type"],
            "side": side,
            "profile": profile,
            "loader": loader,
            "modrinth_client_side": proj["client_side"],
            "modrinth_server_side": proj["server_side"],
            "filename": primary["filename"],
            "url": primary["url"],
            "sha1": primary["hashes"]["sha1"],
            "sha512": primary["hashes"]["sha512"],
            "size": primary["size"],
            "dependency_of": [dep_of] if dep_of else [],
        }
        resolved[pid] = entry
        print(f"  {entry['slug']:32} {entry['version_number']:28} [{side}/{profile}]", file=sys.stderr)
        for dep in v["dependencies"]:
            if dep["dependency_type"] != "required" or not dep.get("project_id"):
                continue
            dep_proj = get(f"{API}/project/{dep['project_id']}")
            queue.append((dep_proj, side, profile, False, proj["slug"]))

    if missing:
        print("\nNo compatible version found for:", file=sys.stderr)
        for m in missing:
            print(f"  - {m}", file=sys.stderr)
        sys.exit(1)

    loaders = get(FABRIC_META)
    fabric_loader = next(l["version"] for l in loaders if l.get("stable"))

    entries = sorted(resolved.values(), key=lambda e: (e["profile"], e["side"], e["slug"]))
    lock = {
        "game_version": game_version,
        "fabric_loader": fabric_loader,
        "mods": entries,
    }
    outputs = {
        LOCK: json.dumps(lock, indent=2) + "\n",
        VERSIONS_ENV: (
            "# Generated by scripts/resolve_mods.py. Do not edit.\n"
            f"VERSION={game_version}\n"
            f"FABRIC_LOADER_VERSION={fabric_loader}\n"
        ),
    }
    for profile in PROFILES:
        lines = [
            "# Generated by scripts/resolve_mods.py from mods/mods.txt. Do not edit.",
            f"# Profile: {profile}. Minecraft {game_version}, Fabric loader {fabric_loader}.",
            "# Format: [datapack:]<slug>:<modrinth version id>",
            "",
        ]
        for e in entries:
            if e["side"] == "client":
                continue
            if profile == "core" and e["profile"] != "core":
                continue
            prefix = "datapack:" if e["loader"] == "datapack" else ""
            lines.append(f"{prefix}{e['slug']}:{e['version_id']}   # {e['title']} {e['version_number']}")
        outputs[ROOT / "mods" / f"server-mods.{profile}.txt"] = "\n".join(lines) + "\n"

    changed = [p for p, c in outputs.items() if not p.exists() or p.read_text() != c]
    if args.check:
        if changed:
            print("Outputs out of date: " + ", ".join(str(p.relative_to(ROOT)) for p in changed), file=sys.stderr)
            sys.exit(1)
        print("Lock files are up to date.", file=sys.stderr)
        return
    for p, c in outputs.items():
        p.write_text(c)
    print(f"\nWrote {len(entries)} entries to {LOCK.relative_to(ROOT)}", file=sys.stderr)


if __name__ == "__main__":
    main()
