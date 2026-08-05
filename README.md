# SmelterWorks Dockerized Vintage Story Server

Docker image and Compose stack for a [Vintage Story](https://www.vintagestory.at/) dedicated server. Targets `linux/amd64` and `linux/arm64`.

SmelterWorks is not affiliated with Anego Studios. The server binaries come from the official CDN. Arm64 replaces native binaries with the experimental overlay from [anegostudios/VintagestoryServerArm64](https://github.com/anegostudios/VintagestoryServerArm64). Harmony-using coded mods need that overlay line (1.21+).

## Requirements

- Docker Engine with Compose v2 and Buildx
- Open TCP and UDP `42420` on the host firewall ([wiki](https://wiki.vintagestory.at/Guide:Dedicated_Server))
- About 1 GB RAM base plus roughly 300 MB per concurrent player ([wiki hardware notes](https://wiki.vintagestory.at/Guide:Dedicated_Server))

Default image pins Vintage Story `1.22.6` (sha256-verified download) on .NET 10.

## Run

```bash
cp .env.example .env
mkdir -p mods backups
docker compose build
docker compose up -d
docker compose attach vintagestory
```

Attach gives you the server console. Detach with `Ctrl-p Ctrl-q`. Stop with `/stop` in the console, or `docker compose stop`.

Published image: `ghcr.io/smelterworks/dockerized-server`.

## Mods

Drop `.zip` or unpacked mods into `./mods`. The container loads them with `--addModPath /mods` ([startup parameters](https://wiki.vintagestory.at/Server_startup_parameters/en)). The bind mount is read-only.

World data, player data, and `serverconfig.json` live in the `vs-data` volume at `/data`.

## Backups

Timed tar snapshots of `Saves`, `Playerdata`, `Mods`, and `serverconfig.json` land in `./backups`. Interval and retention are set in `.env`. A shutdown backup runs by default.

Manual run:

```bash
docker compose --profile tools run --rm backup
```

These are best-effort copies while the process is live. Use in-game `/genbackup` when you need a consistent world dump.

## Config

Edit `/data/serverconfig.json` after the first start (stop the container first), or pass overrides with `VS_EXTRA_ARGS` / `--withconfig` as documented on the [startup parameters](https://wiki.vintagestory.at/Server_startup_parameters/en) page.

Common `.env` knobs: `VS_PORT`, `VS_MAX_CLIENTS`, `VS_CPUS`, `VS_MEM_LIMIT`, backup flags.

Compose defaults: read-only rootfs, `cap_drop: ALL` plus the few caps needed for the root-to-`65532` drop, `no-new-privileges`, resource limits, TCP healthcheck on `42420`, `stop_grace_period: 90s`.

## Build

```bash
docker buildx build --platform linux/amd64,linux/arm64 -t ghcr.io/smelterworks/dockerized-server:dev --load .
```

`--load` only works for a single platform. For both arches, push to a registry or use `--push`.

Bump `VS_VERSION` / `VS_SHA256` (and the arm overlay args) in the Dockerfile when you change game version. Digests for base images are pinned on the latest tags.

## CI

`.github/workflows/docker.yml` builds an amd64 image, runs `scripts/ci-smoke.sh` (start, healthcheck, uid `65532`, backup, stop), then publishes multi-arch images to GHCR on `main` and `v*` tags. Publish waits on smoke. Actions are SHA-pinned. CodeQL scans Actions workflows. Dependabot watches Actions and Docker base images weekly. Patterns follow [GitHub Actions secure use](https://docs.github.com/en/actions/reference/security/secure-use).

## Upstream docs

- [Setting up a Multiplayer Server](https://wiki.vintagestory.at/Setting_up_a_Multiplayer_Server)
- [Guide: Dedicated Server](https://wiki.vintagestory.at/Guide:Dedicated_Server)
- [Server startup parameters](https://wiki.vintagestory.at/Server_startup_parameters/en)
