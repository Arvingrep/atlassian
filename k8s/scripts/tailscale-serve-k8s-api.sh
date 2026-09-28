#!/usr/bin/env bash
# Expose the MacBook OrbStack k8s API to the tailnet so that the mac-mini ArgoCD
# can reach it. OrbStack only listens on 127.0.0.1:26443, so a raw TCP forward is
# required; Tailscale Serve keeps it inside the tailnet (no LAN/公网 exposure).
#
# Idempotent: safe to run at login / from launchd.
set -euo pipefail

PORT="${1:-26443}"
TARGET="tcp://127.0.0.1:${PORT}"

if ! command -v tailscale >/dev/null 2>&1; then
  echo "tailscale CLI not found" >&2
  exit 1
fi

# OrbStack must be running for the API to exist; wait briefly if it is not up yet.
for _ in $(seq 1 30); do
  if nc -z 127.0.0.1 "${PORT}" 2>/dev/null; then break; fi
  sleep 2
done

if tailscale serve status 2>/dev/null | grep -q ":${PORT}"; then
  echo "serve already configured for tcp/${PORT}"
else
  tailscale serve --bg --tcp "${PORT}" "${TARGET}" >/dev/null
  echo "serve configured: tcp/${PORT} -> ${TARGET}"
fi

tailscale serve status | sed -n '1,6p'
