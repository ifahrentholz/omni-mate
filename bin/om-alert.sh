#!/usr/bin/env bash
# om-alert.sh — reach the captain when they are not looking at the session.
#
#   om-alert.sh <title> <message>       send on every configured channel
#   om-alert.sh --test                  send a probe and report what worked
#   om-alert.sh --channels              list what is configured, send nothing
#
# This is the ONLY outbound path to a captain who is away. Everything else the
# first mate says waits in the conversation until they come back and read it.
#
# Channels live in config/alert, one per line, first token names the channel.
# Blank lines and #comments are ignored. With no config file, macOS
# Notification Center is used when available and nothing else is attempted.
#
# That default is a fallback for an ABSENT file, not an implicit first line: as
# soon as config/alert exists it is the complete list, so a file holding only
# an ntfy line silently turns the local notification off. Explicit beats
# additive — but it surprises people, so list `notify` too when you want it.
#
#   notify                       macOS Notification Center (local machine only)
#   say                          speak it aloud (macOS `say`)
#   ntfy https://ntfy.sh/<topic> HTTP push to a phone; the topic IS the secret
#   webhook <url>                POST {"title":…,"message":…} as JSON
#   command <shell command>      anything; gets OM_ALERT_TITLE / OM_ALERT_MESSAGE
#
# Exit code is 0 when at least one channel accepted the alert, 1 when every
# channel failed, and 2 when none is configured. That distinction is the point:
# a first mate must be able to tell the difference between "the captain has
# been told" and "I could not reach them", and must never report the first
# when the second is true. Every attempt is appended to state/alerts.log.
set -euo pipefail
# shellcheck source=om-lib.sh
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/om-lib.sh"
om_ensure_home

LOG="$OM_STATE/alerts.log"
CONF="$OM_CONFIG/alert"

configured_channels() {
  if [ -f "$CONF" ]; then
    grep -v '^[[:space:]]*#' "$CONF" 2>/dev/null | grep -v '^[[:space:]]*$' || true
  elif [ "$(uname -s)" = "Darwin" ] && command -v osascript >/dev/null 2>&1; then
    # The sane default on this platform, and the same one firstmate's
    # wedge-alarm falls back to. It only reaches a captain who is at the
    # machine — config/alert is how you reach one who is not.
    echo "notify"
  fi
}

# Keep it out of AppleScript's string syntax rather than trying to escape it.
sanitize() { printf '%s' "$1" | tr '\n' ' ' | sed -e 's/"/'"'"'/g' -e 's/\\/ /g' | cut -c1-240; }

send_notify() {
  osascript -e "display notification \"$(sanitize "$2")\" with title \"omni-mate\" subtitle \"$(sanitize "$1")\" sound name \"Submarine\"" >/dev/null 2>&1
}
send_say() { say "$(sanitize "$1"). $(sanitize "$2")" >/dev/null 2>&1; }
send_ntfy() {
  curl -fsS --max-time 10 -H "Title: omni-mate: $(sanitize "$2")" -d "$3" "$1" >/dev/null 2>&1
}
send_webhook() {
  curl -fsS --max-time 10 -H 'Content-Type: application/json' \
    -d "$(printf '{"title":"%s","message":"%s"}' "$(sanitize "$2")" "$(sanitize "$3")")" \
    "$1" >/dev/null 2>&1
}
send_command() {
  OM_ALERT_TITLE="$2" OM_ALERT_MESSAGE="$3" bash -c "$1" >/dev/null 2>&1
}

mode=send
case "${1:-}" in
  --channels) configured_channels; exit 0 ;;
  --test) mode=test; title="omni-mate test"; message="If you can read this, the channel works." ;;
  "") om_die "usage: om-alert.sh <title> <message> | --test | --channels" ;;
  *) title="$1"; message="${2:-}" ;;
esac

channels="$(configured_channels)"
if [ -z "$channels" ]; then
  printf '%s\tNO-CHANNEL\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$title" >> "$LOG"
  echo "no alert channel configured (config/alert is absent and this is not a mac)" >&2
  echo "delivered=0 failed=0 configured=0"
  exit 2
fi

delivered=0; failed=0; detail=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  kind="${line%% *}"; arg="${line#"$kind"}"; arg="${arg# }"
  ok=1
  case "$kind" in
    notify)  send_notify  "$title" "$message" && ok=0 ;;
    say)     send_say     "$title" "$message" && ok=0 ;;
    ntfy)    send_ntfy    "$arg" "$title" "$message" && ok=0 ;;
    webhook) send_webhook "$arg" "$title" "$message" && ok=0 ;;
    command) send_command "$arg" "$title" "$message" && ok=0 ;;
    *) detail="$detail $kind=unknown-channel"; failed=$((failed+1)); continue ;;
  esac
  if [ "$ok" = 0 ]; then
    delivered=$((delivered+1)); detail="$detail $kind=ok"
  else
    failed=$((failed+1)); detail="$detail $kind=FAILED"
  fi
done <<CHANNELS
$channels
CHANNELS

printf '%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "$([ "$delivered" -gt 0 ] && echo DELIVERED || echo UNDELIVERED)" \
  "$title" "$(echo "$detail" | sed 's/^ //')" >> "$LOG"

echo "delivered=$delivered failed=$failed channels=$(echo "$detail" | sed 's/^ //')"
[ "$mode" = test ] && echo "(test only — nothing about the fleet was reported)"
[ "$delivered" -gt 0 ] || exit 1
exit 0
