#!/usr/bin/env python3
"""Build a Modrinth modpack (.mrpack) for friends from mods/lock.json.

  scripts/build_mrpack.py --profile full   # content mods + client perf mods
  scripts/build_mrpack.py --profile core   # client perf mods only (joins a core server)

The pack pre-fills the server in the multiplayer list (servers.dat) using
client-pack/pack.json, and copies anything under client-pack/overrides/ verbatim.
Output: dist/<slug>-<profile>-<version>.mrpack
"""
import argparse
import io
import json
import shutil
import struct
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOCK = ROOT / "mods" / "lock.json"
PACK = ROOT / "client-pack" / "pack.json"
OVERRIDES = ROOT / "client-pack" / "overrides"
DIST = ROOT / "dist"


# --- minimal NBT writer for servers.dat (uncompressed) -----------------------
def _nbt_string(s):
    b = s.encode("utf-8")
    return struct.pack(">H", len(b)) + b


def _tag(tag_type, name, payload):
    return bytes([tag_type]) + _nbt_string(name) + payload


def servers_dat(name, address):
    entry = _tag(8, "name", _nbt_string(name)) + _tag(8, "ip", _nbt_string(address)) + _tag(1, "hidden", b"\x00") + b"\x00"
    servers_list = bytes([10]) + struct.pack(">i", 1) + entry  # list of 1 compound
    root_payload = _tag(9, "servers", servers_list) + b"\x00"
    return _tag(10, "", root_payload)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--profile", choices=("core", "full"), default="full")
    ap.add_argument("--version", default=None, help="pack version (default: client-pack/pack.json)")
    args = ap.parse_args()

    lock = json.loads(LOCK.read_text())
    pack = json.loads(PACK.read_text())
    version = args.version or pack["version"]
    profile = args.profile

    files = []
    for m in lock["mods"]:
        if m["side"] == "server" or m["loader"] == "datapack":
            continue
        if profile == "core" and m["profile"] != "core":
            continue
        files.append({
            "path": f"mods/{m['filename']}",
            "hashes": {"sha1": m["sha1"], "sha512": m["sha512"]},
            "env": {
                "client": "required",
                "server": "unsupported" if m["side"] == "client" else "required",
            },
            "downloads": [m["url"]],
            "fileSize": m["size"],
        })

    index = {
        "formatVersion": 1,
        "game": "minecraft",
        "versionId": f"{version}-{profile}",
        "name": f"{pack['name']} ({profile})",
        "summary": pack.get("summary", ""),
        "files": sorted(files, key=lambda f: f["path"]),
        "dependencies": {
            "minecraft": lock["game_version"],
            "fabric-loader": lock["fabric_loader"],
        },
    }

    DIST.mkdir(exist_ok=True)
    out = DIST / f"{pack['slug']}-{profile}-{version}.mrpack"
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("modrinth.index.json", json.dumps(index, indent=2))
        address = pack.get("server_address", "")
        if address and not address.startswith("SET-ME"):
            z.writestr("overrides/servers.dat", servers_dat(pack["server_name"], address))
        else:
            print("note: client-pack/pack.json has no server_address yet; pack will not pre-fill the server list", file=sys.stderr)
        if OVERRIDES.exists():
            for p in sorted(OVERRIDES.rglob("*")):
                if p.is_file():
                    z.write(p, f"overrides/{p.relative_to(OVERRIDES)}")
    print(f"{out.relative_to(ROOT)}  ({len(files)} mods, Minecraft {lock['game_version']}, Fabric {lock['fabric_loader']})")


if __name__ == "__main__":
    main()
