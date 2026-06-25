#!/bin/bash
# Launch wrapper for chrome-devtools-mcp inside the Claude Code remote sandbox.
#
# Two sandbox-specific problems are handled here before the MCP starts its
# Chromium, so the browser can reach external HTTPS sites:
#
#   1. Egress proxy: all outbound HTTPS is tunneled through the env's proxy.
#      Chromium needs it passed explicitly via --proxy-server.
#   2. TLS trust: the proxy re-terminates TLS with its own CA. Chromium must
#      trust that CA or every site fails with ERR_CERT_AUTHORITY_INVALID.
#      We import the proxy CA into the NSS store BEFORE launching the browser
#      (doing it after, as the default startup does, races the browser start).
#      This is the proxy README's sanctioned fix for that failure class.

# --- Trust the egress proxy CA -------------------------------------------
CA=/root/.ccr/agent-proxy-ca.crt
NSSDB="$HOME/.pki/nssdb"
if [ -f "$CA" ]; then
  command -v certutil >/dev/null 2>&1 || apt-get install -y libnss3-tools >/dev/null 2>&1 || true
  if command -v certutil >/dev/null 2>&1; then
    mkdir -p "$NSSDB"
    [ -f "$NSSDB/cert9.db" ] || certutil -d sql:"$NSSDB" -N --empty-password >/dev/null 2>&1 || true
    certutil -d sql:"$NSSDB" -A -t "CT,C,C" -n "ccr-agent-proxy" -i "$CA" >/dev/null 2>&1 || true
  fi
fi

# --- Detect the egress proxy ---------------------------------------------
# Claude Code may not forward HTTPS_PROXY to MCP subprocesses, so fall back to
# reading it from the init process's environ.
PROXY="${HTTPS_PROXY:-}"
if [ -z "$PROXY" ]; then
  PROXY=$(tr '\0' '\n' < /proc/1/environ 2>/dev/null | grep "^HTTPS_PROXY=" | cut -d= -f2-)
fi
PROXY_ARG=""
[ -n "$PROXY" ] && PROXY_ARG="--proxyServer=$PROXY"

# --disable-quic: QUIC (HTTP/3) runs over UDP and cannot traverse the proxy's
#   HTTP CONNECT (TCP) tunnel, causing ERR_CONNECTION_CLOSED on HTTP/3-capable
#   sites (many CDNs). Forcing TCP/TLS routes cleanly through the proxy.
# --disable-features: ECH/HTTPS-SVCB DNS hints can also break through the MITM.

exec npx -y chrome-devtools-mcp@latest \
  --executablePath=/opt/pw-browsers/chromium \
  --headless --isolated \
  $PROXY_ARG \
  --chromeArg=--no-sandbox \
  --chromeArg=--disable-dev-shm-usage \
  --chromeArg=--disable-gpu \
  --chromeArg=--disable-quic \
  --chromeArg=--disable-features=UseDnsHttpsSvcb,EncryptedClientHello
