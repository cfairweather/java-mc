# Runbook

Everything here assumes `make tf-init` has been run and `infra/terraform/terraform.tfvars` exists.

## Where things are

| What | Where |
| --- | --- |
| Server address | `terraform -chdir=infra/terraform output -raw server_address` (Elastic IP) |
| World data | Docker volume `mc-data` on the Bottlerocket data volume (`/dev/xvdb`, survives instance stop/start, not termination) |
| Backups | S3 bucket in output `backup_bucket`, restic repo at prefix `restic/` |
| Logs | CloudWatch log group `/ecs/java-mc`, streams `mc/…` and `backup/…` |
| Secrets | SSM parameters `/java-mc/rcon_password`, `/java-mc/restic_password` |
| BlueMap | `http://<server_address>:8100/` from the CIDRs in `admin_cidrs` |

## Adding or removing a friend

Live, without a restart:

```sh
make aws-console CMD="whitelist add TheirName"
```

Then add the name to `WHITELIST=` in `server/server.env` and commit, so the next
deployment keeps it (the image merges the env list into the whitelist file on
every start, so a live add survives restarts even before you commit).

Removing: `make aws-console CMD="whitelist remove TheirName"` and
`make aws-console CMD="kick TheirName"`, then remove from `server/server.env`.

## Deploying a change

| Change | Steps |
| --- | --- |
| Mods, configs, or Dockerfile | commit to `main` → CI pushes `ghcr.io/…:latest` → `make deploy` |
| `server/server.env` or `mods/versions.env` | commit → `make tf-apply` (new task definition revision, rolls automatically) |
| Terraform (instance size, admin IPs) | `make tf-apply` |

A deployment stops the running server (players are warned 10 seconds before)
and starts the new task. Expect 2 to 5 minutes of downtime.

## Backups

- Automatic: every 2 hours while players have been online since the last run,
  snapshots kept per `backup_retention` (last 10 plus 24 hourly, 7 daily, 4 weekly, 3 monthly). The `--keep-last 10` matters: without it two snapshots in the same hour collapse into one, including manual pre-update snapshots.
- Manual, before anything risky: `make aws-backup-now`.
- List: `make aws-snapshots`.

### Restore on AWS

1. `make aws-backup-now` (so the current state is recoverable too).
2. Scale the service to zero so nothing writes to the volume:
   `aws ecs update-service --cluster java-mc --service java-mc --desired-count 0`
3. Run a one-off restore task from the host shell (`make aws-ssm`, then `enter-admin-container` is not needed; use `apiclient exec`):

   ```sh
   # on the Bottlerocket host, via SSM
   sudo sheltie
   docker run --rm -it -v mc-data:/data \
     -e RESTIC_REPOSITORY=s3:s3.<region>.amazonaws.com/<bucket>/restic \
     -e RESTIC_PASSWORD=... -e AWS_DEFAULT_REGION=<region> \
     itzg/mc-backup:2026.9.2 \
     sh -c 'restic snapshots && find /data -mindepth 1 -delete && restic restore latest --target / --path /data'
   ```

   The container inherits the instance role, which has read access to the bucket.
4. `aws ecs update-service --cluster java-mc --service java-mc --desired-count 1`.

Locally: `make restore SNAPSHOT=latest` does the same against the compose stack.

### Restore drill

Do this once after the first deploy and after any change to the backup config:
take a snapshot, break something visible in-game, restore, confirm it is back.

## Upgrading Minecraft

1. `python3 scripts/resolve_mods.py --game-version 26.3`. If it fails, wait or
   drop the mods it names (edit `mods/mods.txt`).
2. `make up && make logs` locally with a copy of the world if you want to be
   careful: `docker run --rm -v java-mc_mc-data:/data -v $PWD/backups:/backups itzg/mc-backup restic restore latest --target /`.
3. `make aws-backup-now`, commit, `make tf-apply`.
4. Tag a release so friends get a new `.mrpack` (`git tag v1.1.0 && git push --tags`).

Mojang world upgrades are one way. Keep the pre-upgrade snapshot until you are sure.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Task keeps restarting | `make aws-logs`. First start can take >5 minutes downloading mods; health check allows 10. |
| "Failed to verify username" on join | The server can't reach Mojang session servers: security group egress, or the host has no public route. |
| Friend can't join, "not white-listed" | Name spelling/case in the whitelist; `make aws-console CMD="whitelist list"`. |
| Friend can't join, "missing mods" | Server is on `full`; they need the pack. Or the pack version doesn't match the server; re-release. |
| Lag | `make aws-console CMD="spark tps"` then `spark profiler start`, `spark profiler stop` for a report URL. |
| Disk full | `make aws-ssm`, `sudo sheltie`, `docker system df`, `docker image prune`. Or raise `data_volume_gb`. |
| Backups not running | Backup container logs in CloudWatch; `PAUSE_IF_NO_PLAYERS` skips runs while nobody has joined. |

## Costs (us-west-2, rough)

m7i.xlarge on-demand ≈ $0.20/h ≈ $145/month if left running 24/7; 100 GB gp3
≈ $8/month; S3 and logs a few dollars. Stopping the instance when idle
(`aws ec2 stop-instances`) keeps the world and costs only the volumes.
