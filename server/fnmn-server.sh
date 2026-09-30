#!/bin/zsh
# Keep the FNMN server and its Tailscale Funnel running as login agents.
#
#   server/fnmn-server.sh on       install and start both agents; they restart after login and on crash
#   server/fnmn-server.sh off      stop both agents and remove them
#   server/fnmn-server.sh status   show agents, Funnel address and an authorized /health check
set -euo pipefail

SERVER="${0:A:h}"
ROOT="${SERVER:h}"
AGENTS="$HOME/Library/LaunchAgents"
LOGS="$HOME/Library/Logs/FNMN"
STATE="$HOME/Library/Application Support/FNMN/Tailscale"
SOCKET=/private/tmp/fnmn-tailscaled.sock
PORT=8765
TAILSCALE=local.fnmn.tailscaled
SERVICE=local.fnmn.service

token() {
  security find-generic-password -s local.fnmn.mac-service -a fnmn -w
}

agent() {
  local label=$1; shift
  local arguments=""
  for argument in "$@"; do arguments+="<string>${argument}</string>"; done
  cat > "$AGENTS/$label.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array>$arguments</array>
  <key>EnvironmentVariables</key><dict>
    <key>PATH</key><string>$ROOT/.venv/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$LOGS/$label.log</string>
  <key>StandardErrorPath</key><string>$LOGS/$label.log</string>
</dict></plist>
PLIST
}

start() {
  launchctl bootout "gui/$UID/$1" 2>/dev/null || true
  launchctl bootstrap "gui/$UID" "$AGENTS/$1.plist"
}

case "${1:-}" in
  on)
    mkdir -p "$AGENTS" "$LOGS"
    install -d -m 700 "$STATE"
    agent $TAILSCALE /opt/homebrew/bin/tailscaled --tun=userspace-networking \
      "--statedir=$STATE" "--socket=$SOCKET" --no-logs-no-support
    agent $SERVICE "$SERVER/fnmn-server.sh" serve
    start $TAILSCALE
    start $SERVICE
    ;;
  off)
    for label in $SERVICE $TAILSCALE; do
      launchctl bootout "gui/$UID/$label" 2>/dev/null || true
      rm -f "$AGENTS/$label.plist"
    done
    ;;
  status)
    for label in $TAILSCALE $SERVICE; do
      launchctl print "gui/$UID/$label" 2>/dev/null | grep -m1 "state =" | sed "s/^/$label: /" || echo "$label: not installed"
    done
    tailscale --socket=$SOCKET funnel status
    address=$(tailscale --socket=$SOCKET status --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))')
    curl -sS -m 20 -H "Authorization: Bearer $(token)" "https://$address/health"; echo
    ;;
  serve)
    cd "$SERVER"
    FNMN_TOKEN="$(token)" exec "$ROOT/.venv/bin/python" -m uvicorn service:app --host 127.0.0.1 --port $PORT
    ;;
  *)
    echo "usage: $0 on | off | status" >&2
    exit 64
    ;;
esac
