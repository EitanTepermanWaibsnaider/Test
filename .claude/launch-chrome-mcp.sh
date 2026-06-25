#!/bin/bash
# Detect the egress proxy — Claude Code may or may not forward HTTPS_PROXY to
# MCP subprocesses, so fall back to reading it from the init process's environ.
PROXY="${HTTPS_PROXY:-}"
if [ -z "$PROXY" ]; then
  PROXY=$(tr '\0' '\n' < /proc/1/environ 2>/dev/null | grep "^HTTPS_PROXY=" | cut -d= -f2-)
fi

PROXY_ARG=""
[ -n "$PROXY" ] && PROXY_ARG="--proxyServer=$PROXY"

exec npx -y chrome-devtools-mcp@latest \
  --executablePath=/opt/pw-browsers/chromium \
  --headless --isolated \
  $PROXY_ARG \
  --chromeArg=--no-sandbox \
  --chromeArg=--disable-dev-shm-usage \
  --chromeArg=--disable-gpu
