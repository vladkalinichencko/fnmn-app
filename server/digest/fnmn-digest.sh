#!/bin/zsh
# Keep the social digest monitor and its builder running as login agents.
#
#   server/digest/fnmn-digest.sh on       install and start both agents
#   server/digest/fnmn-digest.sh off      stop both agents and remove them
#   server/digest/fnmn-digest.sh status   show the agents and the newest delivery
#   server/digest/fnmn-digest.sh monitor  read every source once, now
#   server/digest/fnmn-digest.sh build    build a digest if the schedule is due, now
#   server/digest/fnmn-digest.sh login x|instagram|telegram   log the reader in once
set -euo pipefail

DIGEST="${0:A:h}"
SERVER="${DIGEST:h}"
ROOT="${SERVER:h}"
PYTHON="$ROOT/.venv/bin/python"
AGENTS="$HOME/Library/LaunchAgents"
LOGS="$HOME/Library/Logs/FNMN"
MONITOR=local.fnmn.digest.monitor
BUILDER=local.fnmn.digest.builder
TRAINER=local.fnmn.digest.trainer

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
  <key>WorkingDirectory</key><string>$SERVER</string>
  <key>EnvironmentVariables</key><dict>
    <key>PATH</key><string>$ROOT/.venv/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>RunAtLoad</key><true/>
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
    mkdir -p "$AGENTS" "$LOGS" "$DIGEST/out"
    agent $MONITOR "$PYTHON" -m digest.monitor
    agent $BUILDER "$PYTHON" -m digest.build
    agent $TRAINER "$PYTHON" -m digest.train
    /usr/libexec/PlistBuddy -c "Add :StartInterval integer 7200" "$AGENTS/$MONITOR.plist"
    /usr/libexec/PlistBuddy -c "Add :StartCalendarInterval array" "$AGENTS/$BUILDER.plist"
    /usr/libexec/PlistBuddy -c "Add :StartCalendarInterval:0 dict" "$AGENTS/$BUILDER.plist"
    /usr/libexec/PlistBuddy -c "Add :StartCalendarInterval:0:Hour integer 8" "$AGENTS/$BUILDER.plist"
    /usr/libexec/PlistBuddy -c "Add :StartCalendarInterval:0:Minute integer 0" "$AGENTS/$BUILDER.plist"
    /usr/libexec/PlistBuddy -c "Add :StartCalendarInterval:1 dict" "$AGENTS/$BUILDER.plist"
    /usr/libexec/PlistBuddy -c "Add :StartCalendarInterval:1:Hour integer 20" "$AGENTS/$BUILDER.plist"
    /usr/libexec/PlistBuddy -c "Add :StartCalendarInterval:1:Minute integer 0" "$AGENTS/$BUILDER.plist"
    /usr/libexec/PlistBuddy -c "Add :StartCalendarInterval array" "$AGENTS/$TRAINER.plist"
    /usr/libexec/PlistBuddy -c "Add :StartCalendarInterval:0 dict" "$AGENTS/$TRAINER.plist"
    /usr/libexec/PlistBuddy -c "Add :StartCalendarInterval:0:Hour integer 21" "$AGENTS/$TRAINER.plist"
    /usr/libexec/PlistBuddy -c "Add :StartCalendarInterval:0:Minute integer 0" "$AGENTS/$TRAINER.plist"
    start $MONITOR
    start $BUILDER
    start $TRAINER
    echo "The digest monitor runs every two hours; the builder at 08:00 and 20:00; the trainer at 21:00."
    ;;
  off)
    launchctl bootout "gui/$UID/$MONITOR" 2>/dev/null || true
    launchctl bootout "gui/$UID/$BUILDER" 2>/dev/null || true
    launchctl bootout "gui/$UID/$TRAINER" 2>/dev/null || true
    rm -f "$AGENTS/$MONITOR.plist" "$AGENTS/$BUILDER.plist" "$AGENTS/$TRAINER.plist"
    echo "The digest agents are off."
    ;;
  status)
    launchctl print "gui/$UID/$MONITOR" 2>/dev/null | grep -E "state|last exit" || echo "$MONITOR: not loaded"
    launchctl print "gui/$UID/$BUILDER" 2>/dev/null | grep -E "state|last exit" || echo "$BUILDER: not loaded"
    launchctl print "gui/$UID/$TRAINER" 2>/dev/null | grep -E "state|last exit" || echo "$TRAINER: not loaded"
    ls -1t "$HOME/Library/Mobile Documents/com~apple~CloudDocs/FNMN/digests" 2>/dev/null | head -3 || echo "no deliveries yet"
    ;;
  monitor)
    cd "$SERVER" && "$PYTHON" -m digest.monitor --verbose
    ;;
  build)
    cd "$SERVER" && "$PYTHON" -m digest.build
    ;;
  train)
    cd "$SERVER" && "$PYTHON" -m digest.train
    ;;
  login)
    cd "$SERVER" && "$PYTHON" -m digest.login "${2:?usage: fnmn-digest.sh login x|instagram|telegram}"
    ;;
  *)
    echo "usage: fnmn-digest.sh on|off|status|monitor|build|train|login x|instagram|telegram"
    exit 2
    ;;
esac
