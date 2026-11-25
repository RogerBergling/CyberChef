#!/bin/sh
set -eu
port=${APP_PORT:-8080}
wget -qO- "http://127.0.0.1:${port}/healthz" >/dev/null
wget -qO- "http://127.0.0.1:${port}/" >/dev/null
wget -qO- "http://127.0.0.1:${port}/config.js" >/dev/null
