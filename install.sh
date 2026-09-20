#!/usr/bin/env bash
# install.sh — put `omni-mate` on your PATH.
#
#   ./install.sh              symlink into ~/.local/bin
#   ./install.sh --dir ~/bin  somewhere else
#   ./install.sh --uninstall  remove the symlink
#
# Your shell config is not touched. A symlink in a PATH directory works in
# every shell and cannot break a login shell.
set -euo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$HOME/.local/bin"
MODE=install

while [ $# -gt 0 ]; do
  case "$1" in
    --dir) TARGET_DIR="${2:?--dir needs a path}"; shift 2 ;;
    --uninstall) MODE=uninstall; shift ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "install.sh: unknown argument: $1" >&2; exit 1 ;;
  esac
done

LINK="$TARGET_DIR/omni-mate"

if [ "$MODE" = uninstall ]; then
  if [ -L "$LINK" ]; then rm "$LINK"; echo "removed $LINK"; else echo "nothing at $LINK"; fi
  exit 0
fi

mkdir -p "$TARGET_DIR"
ln -sf "$ROOT/bin/omni-mate" "$LINK"
echo "linked $LINK -> $ROOT/bin/omni-mate"

case ":$PATH:" in
  *":$TARGET_DIR:"*) ;;
  *) echo "note: $TARGET_DIR is not on your PATH. Add it, or use --dir." ;;
esac

echo
echo "Checked:"

check() {
  if command -v "$1" >/dev/null 2>&1; then
    printf '  %-10s ok\n' "$1"
  else
    printf '  %-10s MISSING — %s\n' "$1" "$2"
  fi
}
check git      "omni-mate cannot cut a worktree without it"
check omnigent "see https://omnigent.ai/"
check gh       "needed for direct-PR and no-mistakes projects; local-only works without it"
check claude   "needed for VISIBLE ship crewmates (claude-native); switch crew/ship.yaml to claude-sdk to run headless"

if command -v gh >/dev/null 2>&1 && ! gh auth status >/dev/null 2>&1; then
  echo "  gh         not authenticated — run: gh auth login"
fi
if command -v omnigent >/dev/null 2>&1; then
  echo
  echo "If no Claude provider is configured yet: omnigent setup"
fi

echo
echo "Then: omni-mate"
