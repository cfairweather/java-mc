# Implementation Proposal: Private Modded Minecraft Server on Docker

Status: accepted 2026-09-23, implemented in this repository (see README.md)
Date: 2026-09-23

## 1. Goals

- A Java Edition server for a small group of friends (target 5 to 10 concurrent, up to ~20 whitelisted).
- Runs entirely in Docker Compose on a single Linux host. One command to start, stop, update, and back up.
- Access is restricted to whitelisted players who authenticate through Mojang/Microsoft (`online-mode=true`). No cracked or offline clients, ever.
- A curated "best of" mod set focused on quality of life, performance, exploration, and social play, with minimal friction for friends to join.
- Automatic, tested backups with a documented restore path.

Non-goals: public server, Bedrock cross-play (would require Floodgate and weakens the auth model), multi-server proxy networks, a web admin panel.

## 2. Key decisions

### 2.1 Game version: 26.2 (not 26.3)

| Option | Pros | Cons |
| --- | --- | --- |
| **26.2 (recommended)** | Every mod in the proposed set has a 26.2 build today. | Three months behind current. |
| 26.3 (current, released 2026-09-15) | Newest content ("Wilderness Bound"). | Krypton, ModernFix, YUNG's, Terralith, and several others have no 26.3 build yet. |
| 1.21.1 (NeoForge) | Only way to get Create and the big tech/kitchen-sink packs. | A year and a half old; different loader; heavier client install. |

We pin to 26.2 now and bump to 26.3 once the full mod list has releases for it. The pin lives in one place (`.env`), so bumping is a one-line change plus a backup.

Both 26.2 and 26.3 require Java 25, so the image tag is `itzg/minecraft-server:<release>-java25`.

### 2.2 Mod loader: Fabric

Fabric has the deepest server-side optimization stack (Lithium, C2ME, ScalableLux, VMP, Krypton) and the largest set of **server-only** mods, which means friends can play with a plain vanilla launcher if we choose. NeoForge is only worth it if you want Create, and Create is stuck on 1.21.1. This is the one decision I'd like you to confirm explicitly (see open questions).

### 2.3 Base image: `itzg/minecraft-server`

The de facto standard. It handles Fabric install, Modrinth mod download with version pinning, whitelist/ops sync, RCON, health checks, JVM tuning flags, and plays with its `itzg/mc-backup` sidecar. We pin the image to a dated release tag rather than `latest`.

### 2.4 Two client profiles

- **Profile A, "zero install"**: only server-side mods. Friends join with the stock launcher on 26.2. Everything in sections 5.1 to 5.3 works this way.
- **Profile B, "full pack"**: adds content mods that need a client install (section 5.4). Distributed as a Modrinth `.mrpack` built with packwiz, installable in one click via the Modrinth App or Prism Launcher. The pack also bundles client-only performance mods (Sodium, Iris) so friends on weak machines get a good experience.

Recommendation: launch with Profile A on day one so everyone can join immediately, then ship Profile B as a v2 once the core is stable. Both are in scope for this project.

### 2.5 Network exposure

| Option | Pros | Cons |
| --- | --- | --- |
| **Port-forward 25565 + whitelist (recommended default)** | Simplest; friends just type an address. | Server is discoverable by scanners (whitelist still blocks them). |
| Tailscale sidecar (VPN overlay) | Server never reachable from the public internet. | Every friend installs Tailscale and gets invited to your tailnet. |

The compose file will include an optional, commented Tailscale sidecar so the choice can be made without a rewrite.

## 3. Architecture

```
 friends (Mojang-authenticated)
        │  TCP 25565 (game)  UDP 24454 (voice chat, optional)
        ▼
┌──────────────────────────────────── docker compose ────────────────────────────────────┐
│                                                                                        │
│  mc  (itzg/minecraft-server:…-java25)                                                  │
│    Fabric 26.2, mods from Modrinth (pinned), whitelist/ops from .env                    │
│    RCON on internal network only (never published)                                     │
│    optional: BlueMap web UI on :8100 (LAN/Tailscale only)                              │
│    volume: mc-data  → /data                                                            │
│                                                                                        │
│  backup  (itzg/mc-backup)                                                              │
│    restic snapshots every 2h, save-off/save-all via RCON, prunes by retention policy   │
│    volume: mc-data (ro), mc-backups → /backups, optional rclone remote (S3/B2/Drive)   │
│                                                                                        │
│  [optional] tailscale sidecar sharing mc's network namespace                           │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

Single host, single compose project, two named volumes. No database, no reverse proxy.

## 4. Access control and security

- `ONLINE_MODE=true` and `ENFORCE_SECURE_PROFILE=true`: only Mojang-verified accounts with signed profile keys can connect.
- `ENABLE_WHITELIST=true`, `ENFORCE_WHITELIST=true`, whitelist entries in `.env` by username (the image resolves them to UUIDs). Changing the list and restarting is enough; a helper script also adds players live over RCON.
- Ops: only you, at level 4. Friends are not ops. Fine-grained permissions (e.g. letting a friend use `/tp` or Vanish) go through LuckPerms.
- RCON enabled (the backup sidecar needs it) but bound to the internal compose network only. Password comes from `.env`, which is git-ignored; `.env.example` is committed.
- Container hardening: non-root UID/GID, `restart: unless-stopped`, memory limit, no host network mode, only 25565/tcp (and 24454/udp if voice chat is on) published.
- BlueMap, if enabled, is not published to the internet. It listens on the LAN or Tailscale interface only.
- Host firewall rules documented in the README (ufw example).
- Explicitly rejected: Geyser/Floodgate, `online-mode=false`, exposing RCON, running as root.

## 5. Mod set (all verified on Modrinth to have 26.2 builds for Fabric)

Legend: S = server-only (friends need nothing), B = both sides, C = client-only (bundled in the pack).

### 5.1 Performance (S)

| Mod | Why |
| --- | --- |
| Lithium | General tick-loop optimization, no behavior changes. |
| FerriteCore | Cuts memory use substantially. |
| Krypton | Networking stack optimization. |
| C2ME | Multithreaded chunk generation and I/O; biggest win for exploration-heavy play. |
| ScalableLux | Modern lighting engine (Starlight successor for 1.21+). |
| Very Many Players (VMP) | Player tracking and chunk-sending optimizations. |
| ServerCore | Dynamic view/simulation distance and mob-spawn tuning under load. |
| Alternate Current | Faster redstone. |
| spark | Profiler, for diagnosing lag when it happens. |
| ModernFix | Startup and memory fixes. Include once a 26.2 build exists; currently 26.1.2. |

### 5.2 Admin and social quality of life (S)

| Mod | Why |
| --- | --- |
| LuckPerms | Permissions without handing out op. |
| Universal Graves | Items go into a grave on death instead of despawning. Huge for friend groups. |
| Styled Chat | Readable chat formatting, mentions, link rendering. |
| Fabric Tailor | Custom skins from a URL or file, server-side. |
| Ledger | Block/chest logging with rollback. Answers "who took my diamonds". |
| Vanish | Admin invisibility for fixing things quietly. |
| Chunky | Pre-generate the spawn region so C2ME isn't working during play. |
| BlueMap (optional) | Browser-based 3D map of the world. |
| AFK Display (datapack) | Marks idle players in the tab list. |

### 5.3 World generation (S, data-driven)

| Mod | Why |
| --- | --- |
| Terralith | The standard "make the overworld beautiful" mod. Include once a 26.2 build exists; currently 26.1.2. Tectonic is the 26.2-ready fallback. |
| Tectonic | Dramatic terrain shaping. Pairs with Terralith. |
| Nullscape | Overhauled End. |
| Incendium | Overhauled Nether. |
| Dungeons and Taverns | Many new structures, vanilla-styled. |
| YUNG's Better Dungeons / Strongholds / Mineshafts | Include once 26.2 builds exist; currently 26.1.2. |

Worldgen must be decided before world creation; these cannot be added to an existing world cleanly.

### 5.4 Content and gameplay (B, requires the client pack)

| Mod | Why |
| --- | --- |
| Waystones | Fast travel between discovered waystones. |
| Simple Voice Chat | Proximity voice chat in-game (needs UDP 24454 published). |
| Farmer's Delight Refabricated | Cooking, farming, and food expansion. |
| Naturalist | New animals and ambient wildlife. |
| Comforts | Sleeping bags and hammocks. |
| Better Combat | Directional melee combat with animations. |
| Immersive Armors | Extra armor sets with vanilla-ish balance. |
| Jade | "What am I looking at" tooltips (server side adds extra info). |
| AppleSkin | Food/saturation HUD (server side adds accuracy). |
| Distant Horizons | Far-render LOD terrain; server side lets it stream pre-generated LODs to clients. |
| Xaero's Minimap and World Map | Shared waypoints when the server-side half is installed. |

Rejected because they are not on 26.2: Create (NeoForge 1.21.1 only), Supplementaries and Trinkets (1.21.1), Noisium (1.21.6, and superseded).

### 5.5 Client-only (C, bundled in the pack)

Sodium, Iris Shaders, Mod Menu, Cloth Config, plus a recommended shader pack link. These never touch the server.

All mods are installed by the image from a pinned listing file (`mods/server-mods.txt`, referenced via `MODRINTH_PROJECTS=@/mods/server-mods.txt`) so upgrades are reviewable diffs, not surprises.

## 6. Backups and operations

- **Backups**: `itzg/mc-backup` with `BACKUP_METHOD=restic`. Every 2 hours, it issues `save-off` / `save-all` over RCON, snapshots `/data`, then `save-on`. Retention: 24 hourly, 7 daily, 4 weekly. Local repo on a second volume; optional second target via rclone (S3, Backblaze B2, Google Drive) configured in `.env`. A restore script and a documented restore drill are part of the deliverable.
- **Idle behavior**: `pause-when-empty-seconds=300` (native since 1.21.2) so the server stops ticking with nobody online. Cheap on CPU, instant wake.
- **Health**: the image's built-in `mc-health` check drives `healthcheck:`; compose restarts on failure.
- **Sizing**: 8 GB heap (`-Xms8G -Xmx8G`) with Aikar's flags via `USE_AIKAR_FLAGS=true`; container memory limit 10 GB; host with 16 GB RAM and 4+ cores recommended. Adjustable in `.env`.
- **Updates**: `make update` bumps image tag and mod pins; a pre-update backup is forced automatically. Rollback = restore snapshot + revert `.env`.
- **Logs**: JSON-file logging with rotation; `make logs` tails the server.
- **Pre-generation**: a one-time `chunky` run for a 3000-block radius around spawn, documented as a make target.

## 7. Repository layout

```
.
├── docker-compose.yml          # mc + backup services, optional tailscale profile
├── .env.example                # every tunable, with comments; copy to .env
├── Makefile                    # up/down/logs/rcon/whitelist/backup/restore/update/pregen
├── mods/
│   └── server-mods.txt         # pinned Modrinth listing (project:version per line)
├── config/                     # mod configs bind-mounted into /data/config
│   ├── luckperms/  styled-chat/  bluemap/  universal-graves/  ...
├── client-pack/                # packwiz project → exports .mrpack
│   ├── pack.toml  index.toml  mods/*.pw.toml
├── scripts/
│   ├── whitelist.sh            # add/remove player live via RCON and .env
│   ├── restore.sh              # list snapshots, restore one to a fresh volume
│   └── update-mods.sh          # bump pins in server-mods.txt, show diff
├── docs/
│   ├── PROPOSAL.md             # this file
│   ├── RUNBOOK.md              # day-2 operations
│   └── JOINING.md              # friend-facing: how to install and connect
├── .github/workflows/validate.yml   # compose config, shellcheck, packwiz refresh
└── README.md
```

## 8. Delivery plan

| Phase | Deliverable | Exit criteria |
| --- | --- | --- |
| 0 | This proposal reviewed, open questions answered. | Sign-off. |
| 1 | Core server: compose, `.env.example`, whitelist/auth, performance + admin + worldgen mods (Profile A), backups, Makefile, README. | A friend with a vanilla 26.2 launcher joins; a non-whitelisted account is refused; a backup snapshot exists and restores. |
| 2 | Client pack: packwiz project, `.mrpack` published as a GitHub release, `JOINING.md`, server-side halves of Profile B mods enabled. | Two people join with the pack; voice chat and waystones work. |
| 3 | Extras: BlueMap, Tailscale profile, chunk pre-generation, restore drill written up in `RUNBOOK.md`. | Map renders; restore drill completed on a scratch volume. |
| 4 | Hardening and CI: validation workflow, log rotation, documented update path, first version bump (26.2 → 26.3) once mods allow. | CI green; upgrade performed and rolled back once. |

Phase 1 is the minimum viable server and is what I'd start on immediately after sign-off.

## 9. Decisions taken (2026-09-23)

| Question | Decision | Where it landed |
| --- | --- | --- |
| Loader / pack style | Fabric, vanilla-plus. No NeoForge, no Create. | `mods/mods.txt` |
| Host | AWS, one EC2 instance on Bottlerocket (aws-ecs-2 variant), 4 vCPU / 16 GiB (`m7i.xlarge`), ECS EC2 launch type | `infra/terraform/ec2.tf`, `ecs.tf` |
| Local testing | Docker Compose with the identical image | `compose.yaml` |
| Network | Direct access on an Elastic IP, game port open, whitelist gates access; BlueMap only from `admin_cidrs` | `infra/terraform/network.tf` |
| Backups | restic to S3 every 2h, IAM task role (no static keys), local restic repo when running under compose | `ecs.tf`, `s3.tf` |
| Voice chat | Not included | |
| BlueMap | Included, port 8100, admin IPs only | `server/config/bluemap/` |
| World | difficulty easy, keepInventory on, PvP on | `server/server.env` |
| Scope | All four phases built | this repo |

Because keep-inventory is on, Universal Graves was dropped from the mod list
(nothing to bury). ModernFix and YUNG's structure mods are still waiting for
26.2 builds and are not installed; re-run `make resolve` after adding them to
`mods/mods.txt` once they publish.

Bottlerocket has no package manager and no SSH, so the host is deliberately
"just a container runtime": ECS runs the two containers, SSM Session Manager
provides a shell, ECS Exec provides RCON. Docker Compose is not used on the
host; the compose file and the ECS task definition are kept equivalent by
sharing `server/server.env` and `mods/versions.env`.

## 10. Original open questions (answered above)

1. **Fabric vanilla-plus vs NeoForge tech pack.** The proposal assumes Fabric. If Create-style automation is a must-have, we switch to NeoForge 1.21.1 and the mod list changes substantially.
2. **Host details.** OS, CPU, RAM, and whether Docker is already installed. Sizing defaults assume 16 GB RAM.
3. **Network.** Plain port forward, or Tailscale so nothing is exposed?
4. **Off-site backup target.** None, S3, Backblaze B2, or Google Drive?
5. **Voice chat and BlueMap.** Include in Phase 2/3, or skip?
6. **World settings.** Difficulty (proposal: normal), keep-inventory (proposal: off, graves cover it), PvP (proposal: on, friendly fire is fun).
