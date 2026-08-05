# syntax=docker/dockerfile:1

# Pinned latest tags by digest. Refresh digests when bumping base images.
ARG ALPINE_IMAGE=alpine:3.22@sha256:14358309a308569c32bdc37e2e0e9694be33a9d99e68afb0f5ff33cc1f695dce
ARG DOTNET_IMAGE=mcr.microsoft.com/dotnet/runtime:10.0@sha256:68d35011fe04a39cca38208d392ed48f2df15653633dca16dbc4582d07342b9f

# Vintage Story stable server (linux-x64 CDN package). Assets are shared; arm64
# replaces native binaries via the experimental overlay from anegostudios.
ARG VS_VERSION=1.22.6
ARG VS_CHANNEL=stable
ARG VS_SHA256=afc8ebdc9292bc149964829468633bbda621fb486122df40d3a144253f74a289

# Do not strip .pdb files from the server tree. LoggerBase static init calls
# StackFrame.GetFileName() and crashes without symbols.

# ARM64 overlay major line (compatible with .NET 10 / 1.22.x per upstream README)
ARG ARM_OVERLAY_VERSION=1.22.0
ARG ARM_OVERLAY_SHA256=191c7f3a58a89a47843e7ab8d1fb16d51f3030f7a6cead639c7c48a907679bfa

ARG OCI_TITLE="SmelterWorks Vintage Story Server"
ARG OCI_DESCRIPTION="Rootless multi-arch Vintage Story dedicated server image for SmelterWorks."
ARG OCI_URL=https://github.com/SmelterWorks/Dockerized-Server
ARG OCI_SOURCE=https://github.com/SmelterWorks/Dockerized-Server
ARG OCI_VENDOR=SmelterWorks
ARG OCI_LICENSES=0BSD
ARG OCI_VERSION=dev
ARG OCI_REVISION=unknown

FROM ${ALPINE_IMAGE} AS fetch

ARG TARGETARCH
ARG VS_VERSION
ARG VS_CHANNEL
ARG VS_SHA256
ARG ARM_OVERLAY_VERSION
ARG ARM_OVERLAY_SHA256

RUN apk add --no-cache ca-certificates curl tar

WORKDIR /tmp

RUN set -eu; \
    url="https://cdn.vintagestory.at/gamefiles/${VS_CHANNEL}/vs_server_linux-x64_${VS_VERSION}.tar.gz"; \
    curl -fsSL --retry 3 --retry-delay 2 -o vs_server.tar.gz "${url}"; \
    echo "${VS_SHA256}  vs_server.tar.gz" | sha256sum -c -; \
    mkdir -p /opt/vintagestory; \
    tar -xzf vs_server.tar.gz -C /opt/vintagestory; \
    rm -f vs_server.tar.gz

RUN set -eu; \
    if [ "${TARGETARCH}" = "arm64" ]; then \
      curl -fsSL --retry 3 --retry-delay 2 -o vs_arm.tar.gz \
        "https://github.com/anegostudios/VintagestoryServerArm64/releases/download/${ARM_OVERLAY_VERSION}/vs_server_linux-arm64_${ARM_OVERLAY_VERSION}.tar.gz"; \
      echo "${ARM_OVERLAY_SHA256}  vs_arm.tar.gz" | sha256sum -c -; \
      rm -rf \
        /opt/vintagestory/VintagestoryServer \
        /opt/vintagestory/VintagestoryServer.deps.json \
        /opt/vintagestory/VintagestoryServer.dll \
        /opt/vintagestory/VintagestoryServer.pdb \
        /opt/vintagestory/VintagestoryServer.runtimeconfig.json \
        /opt/vintagestory/Lib; \
      tar -xzf vs_arm.tar.gz -C /opt/vintagestory; \
      rm -f vs_arm.tar.gz; \
    elif [ "${TARGETARCH}" != "amd64" ]; then \
      echo "unsupported TARGETARCH=${TARGETARCH}" >&2; \
      exit 1; \
    fi; \
    chmod 755 /opt/vintagestory/VintagestoryServer; \
    test -f /opt/vintagestory/VintagestoryServer.dll


FROM ${DOTNET_IMAGE} AS runtime

ARG APP_UID=65532
ARG APP_GID=65532
ARG VS_VERSION
ARG ARM_OVERLAY_VERSION
ARG OCI_TITLE
ARG OCI_DESCRIPTION
ARG OCI_URL
ARG OCI_SOURCE
ARG OCI_VENDOR
ARG OCI_LICENSES
ARG OCI_VERSION
ARG OCI_REVISION
ARG DOTNET_IMAGE

LABEL org.opencontainers.image.title="${OCI_TITLE}" \
      org.opencontainers.image.description="${OCI_DESCRIPTION}" \
      org.opencontainers.image.url="${OCI_URL}" \
      org.opencontainers.image.source="${OCI_SOURCE}" \
      org.opencontainers.image.vendor="${OCI_VENDOR}" \
      org.opencontainers.image.licenses="${OCI_LICENSES}" \
      org.opencontainers.image.version="${OCI_VERSION}" \
      org.opencontainers.image.revision="${OCI_REVISION}" \
      org.opencontainers.image.base.name="${DOTNET_IMAGE}" \
      org.opencontainers.image.authors="SmelterWorks" \
      smelterworks.vintagestory.version="${VS_VERSION}" \
      smelterworks.vintagestory.arm_overlay="${ARM_OVERLAY_VERSION}"

ENV DOTNET_NOLOGO=1 \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_EnableDiagnostics=0 \
    ASPNETCORE_URLS= \
    APP_UID=65532 \
    APP_GID=65532 \
    VS_DATA_PATH=/data \
    VS_MODS_PATH=/mods \
    VS_BACKUP_PATH=/backups \
    VS_PORT=42420 \
    VS_MAX_CLIENTS=16 \
    VS_BACKUP_ENABLED=true \
    VS_BACKUP_INTERVAL_SEC=3600 \
    VS_BACKUP_RETENTION=24 \
    VS_BACKUP_ON_SHUTDOWN=true \
    HOME=/data

WORKDIR /opt/vintagestory

RUN set -eu; \
    groupadd --gid "${APP_GID}" vs; \
    useradd --uid "${APP_UID}" --gid vs --home-dir /data --shell /usr/sbin/nologin --no-create-home vs; \
    mkdir -p /data /mods /backups /tmp/vs; \
    chown -R vs:vs /data /mods /backups /tmp/vs

COPY --from=fetch --chown=vs:vs /opt/vintagestory /opt/vintagestory
COPY docker/entrypoint.sh docker/healthcheck.sh docker/backup.sh /usr/local/bin/

RUN chmod 755 /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh /usr/local/bin/backup.sh \
    && chmod 755 /opt/vintagestory/VintagestoryServer

# Starts as root so entrypoint can fix volume ownership, then drops to vs via setpriv.
USER root

EXPOSE 42420/tcp 42420/udp

VOLUME ["/data", "/mods", "/backups"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=3 \
    CMD ["/usr/local/bin/healthcheck.sh"]

STOPSIGNAL SIGTERM

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
