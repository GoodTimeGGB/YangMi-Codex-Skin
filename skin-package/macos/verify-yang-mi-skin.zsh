#!/usr/bin/env zsh
set -euo pipefail
root="${0:A:h:h}"; state="$HOME/Library/Application Support/YangMiCodexSkin/state.json"
[[ -f "$state" ]] || { print -u2 'No Yang Mi skin session is recorded.'; exit 1; }
node "$root/shared/injector.mjs" --verify --theme "$(node -p 'require(process.argv[1]).themeId' "$state")" --port "$(node -p 'require(process.argv[1]).port' "$state")" --browser-id "$(node -p 'require(process.argv[1]).browserId' "$state")"
