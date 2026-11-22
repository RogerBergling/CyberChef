# Deployment examples

Copy-paste examples for running the CyberChef container. The canonical,
fully-hardened files in this repository are:

| File | Purpose |
|---|---|
| [`Dockerfile`](../Dockerfile) | Multi-stage image definition. |
| [`compose.yaml`](../compose.yaml) | Hardened Compose deployment with all runtime limits. |
| [`.env.example`](../.env.example) | Complete environment-variable template. |
| [`README.md`](../README.md) | Full configuration, security and HAProxy documentation. |

Do not commit a real `.env`; it is ignored by `.gitignore`.

## Minimal `.env`

This is enough for a same-host HAProxy deployment on port `8014`:

```dotenv
IMAGE_TAG=latest
BIND_ADDRESS=0.0.0.0
HOST_PORT=8014
APP_PORT=8080

APP_THEME=dark
APP_TITLE=CyberChef
TRUSTED_PROXY_CIDRS=192.168.0.0/18
```

For white mode, set `APP_THEME=light`. The full template includes branding,
CSP, caching, gzip, proxy and nginx settings.

If HAProxy is itself a container, add the Docker bridge/network CIDR to the
trusted proxies, for example:

```dotenv
TRUSTED_PROXY_CIDRS=192.168.0.0/18,172.16.0.0/12
```

> `BIND_ADDRESS=0.0.0.0` publishes the port on every interface. Restrict it with
> a host firewall, or use `BIND_ADDRESS=127.0.0.1` when HAProxy runs directly on
> the host.

## Compose quick start

```bash
cp .env.example .env
# edit .env, at minimum TRUSTED_PROXY_CIDRS
docker compose up -d
```

Open `http://127.0.0.1:8014` or the host/port you configured. After changing
`.env`, recreate the container:

```bash
docker compose up -d --force-recreate
```

## Minimal Compose file

The root [`compose.yaml`](../compose.yaml) is the recommended deployment. This
smaller example is useful for understanding the required security settings; it
relies on the image's built-in defaults for everything not shown.

```yaml
name: cyberchef

services:
  cyberchef:
    image: ghcr.io/rogerbergling/cyberchef:${IMAGE_TAG:-latest}
    container_name: cyberchef
    restart: unless-stopped
    ports:
      - "${BIND_ADDRESS:-0.0.0.0}:${HOST_PORT:-8014}:${APP_PORT:-8080}"
    env_file:
      - .env
    read_only: true
    tmpfs:
      - /tmp:size=32m,noexec,nosuid,mode=1777
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    pids_limit: 128
    mem_limit: 128m
    memswap_limit: 128m
```

The root Compose file additionally sets explicit environment defaults, bounded
log rotation, a stop grace period and `init: true`. Prefer it for production.

## Run with Docker directly

Create `.env` first with `cp .env.example .env`. This is equivalent to the
Compose deployment for a single container. It uses the same `.env` file;
Compose-only values such as `BIND_ADDRESS`, `HOST_PORT` and `IMAGE_TAG` are
harmless, as the entrypoint ignores unknown variables.

```bash
docker run -d \
  --name cyberchef \
  --restart unless-stopped \
  --stop-timeout 30 \
  --read-only \
  --tmpfs /tmp:size=32m,noexec,nosuid,mode=1777 \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --pids-limit 128 \
  --memory 128m \
  --memory-swap 128m \
  --log-opt max-size=10m \
  --log-opt max-file=3 \
  -p 0.0.0.0:8014:8080 \
  --env-file .env \
  ghcr.io/rogerbergling/cyberchef:latest
```

Open `http://127.0.0.1:8014`. Check the image health:

```bash
docker inspect --format '{{.State.Health.Status}}' cyberchef
docker logs -f cyberchef
```

If `APP_PORT` is changed in `.env`, update the container side of `-p` too. If
`BIND_ADDRESS` is changed, update the host side.

Remove the container:

```bash
docker rm -f cyberchef
```

## Build locally

```bash
docker build -t ghcr.io/rogerbergling/cyberchef:local .
```

Then either use `IMAGE_TAG=local` with Compose:

```bash
IMAGE_TAG=local docker compose up -d --force-recreate
```

or run the local image directly:

```bash
docker run -d \
  --name cyberchef \
  --restart unless-stopped \
  --stop-timeout 30 \
  --read-only \
  --tmpfs /tmp:size=32m,noexec,nosuid,mode=1777 \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --log-opt max-size=10m \
  --log-opt max-file=3 \
  -p 8014:8080 \
  --env-file .env \
  ghcr.io/rogerbergling/cyberchef:local
```

## HAProxy

TLS belongs at HAProxy. A minimal backend:

```haproxy
backend cyberchef
    option forwardfor
    option httpchk GET /healthz
    http-check expect status 200
    server cyberchef 127.0.0.1:8014 check
```

See the main README for the full TLS frontend, trusted proxy CIDRs and Docker
networking notes.

## Security reminders

- The container serves **plain HTTP**; do not expose it directly to the Internet.
- There is no built-in authentication. Add authentication at HAProxy if the
  deployment must be private.
- The default CSP blocks CyberChef's HTTP request, DNS over HTTPS and map
  operations. Relax `CSP_CONNECT_SRC` or `CSP_IMG_SRC` only when required.
- Keep `.env` out of Git. Only `.env.example` should be committed.
