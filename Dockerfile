# Server image: itzg/minecraft-server plus this repo's pinned mod listings and
# mod configuration baked in, so the exact same image runs locally (compose)
# and on AWS (ECS). Everything else is configured through environment variables
# in server/server.env and mods/versions.env.
ARG BASE_IMAGE=itzg/minecraft-server:2026.9.1-java25
FROM ${BASE_IMAGE}

# Pinned Modrinth listings. MODRINTH_PROJECTS points at one of these
# (see SERVER_PROFILE in compose.yaml / terraform).
COPY mods/server-mods.core.txt mods/server-mods.full.txt /mods-list/

# Mod configuration. The base image syncs /config into /data/config at startup.
COPY server/config/ /config/

LABEL org.opencontainers.image.source="https://github.com/cfairweather/java-mc" \
      org.opencontainers.image.description="Private Fabric Minecraft server with pinned mods"
