# java-mc

A private, modded Minecraft Java Edition server for friends. Runs the same
Docker image locally (Docker Compose) and on AWS (one Bottlerocket host on ECS)
with whitelist-only access, Mojang authentication, and restic backups to S3.

- **Minecraft 26.2 on Fabric**, ~40 curated mods pinned by exact version (see
  [`mods/mods.txt`](mods/mods.txt) and the generated [`mods/lock.json`](mods/lock.json)).
- **Two profiles.** `core`: server-side mods only, friends join with the stock
  launcher. `full` (default): adds content mods; friends install a one-click
  client pack (`.mrpack`).
- **Access**: `online-mode=true`, `enforce-secure-profile=true`, whitelist
  enabled and enforced. Nothing else is reachable except BlueMap from your own IP.
- **Backups**: every 2 hours to S3 (locally, to `./backups`), with retention,
  and a restore script.

Design and decisions: [docs/PROPOSAL.md](docs/PROPOSAL.md).
Day-2 operations: [docs/RUNBOOK.md](docs/RUNBOOK.md).
What to send friends: [docs/JOINING.md](docs/JOINING.md).

## Layout

```
Dockerfile                itzg/minecraft-server + pinned mod listings + configs
compose.yaml              local stack: mc + backup sidecar
server/server.env         every server setting (shared by compose and terraform)
server/config/            mod configs (synced to /data/config at start)
mods/mods.txt             the curated mod list  → make resolve → lock.json + listings
mods/versions.env         pinned Minecraft / Fabric loader versions (generated)
client-pack/              pack.json (name, server address) + overrides/
scripts/                  resolve_mods.py, build_mrpack.py, whitelist.sh, restore.sh, aws-exec.sh
infra/terraform/          AWS: EC2 (Bottlerocket) + ECS + S3 + SSM + IAM + EIP
.github/workflows/        CI (lock check, image build, boot test, terraform) and release (GHCR + packs)
```

## Local

Requirements: Docker with Compose v2, Python 3.10+, `make`.

```sh
cp .env.example .env            # set RCON_PASSWORD and RESTIC_PASSWORD
make up                         # builds the image, starts server + backup
make logs                       # wait for "Done"
make console CMD="list"         # any RCON command
make whitelist-add NAME=Steve   # live + persisted in server/server.env
make backup-now && make snapshots
make down
```

First start downloads Fabric and every mod (a few minutes). The server
listens on `localhost:25565`; BlueMap is at <http://localhost:8100>.

## AWS

Requirements: AWS CLI v2 with the Session Manager plugin, Terraform 1.6+.

1. The image is published by GitHub Actions: every push to `main` updates
   `ghcr.io/cfairweather/java-mc:latest`, and every release adds a version tag.
   Make the GHCR package public, or set `image_pull_secret_arn`.
2. `cp infra/terraform/terraform.tfvars.example infra/terraform/terraform.tfvars`
   and fill it in (passwords, your home IP for BlueMap).
3. `make tf-init tf-apply`. Output `server_address` is the Elastic IP.
4. Put that address in `client-pack/pack.json`, publish a release, and send
   friends the `.mrpack` from it. To release, either push a tag
   (`git tag v1.0.1 && git push origin v1.0.1`) or run **Actions → Release →
   Run workflow** on `main` with the version (it creates the tag).

Day to day:

```sh
make deploy                       # roll the service to the latest image / task definition
make aws-logs                     # CloudWatch tail
make aws-console CMD="whitelist add Steve"
make aws-backup-now && make aws-snapshots
make aws-ssm                      # shell on the Bottlerocket host
```

Changing anything in `server/server.env`, `mods/mods.txt`, or `server/config/`
means: commit, let CI publish the image, then `make tf-apply` (task definition
changed) or `make deploy` (image only).

## Updating mods or Minecraft

```sh
vim mods/mods.txt                 # add/remove a slug
make resolve                      # re-pin everything against Modrinth
git diff mods/                    # review what changed
make up && make logs              # test locally
```

To move to a new Minecraft version: `python3 scripts/resolve_mods.py --game-version 26.3`.
It fails loudly listing every mod without a build for that version.
