#!/usr/bin/env zsh
set -euo pipefail
root="${0:A:h:h}"; state="$HOME/Library/Application Support/YangMiCodexSkin/state.json"
[[ -f "$state" ]] || { print 'No Yang Mi skin session is recorded.'; exit 0; }
theme="$(node -p 'require(process.argv[1]).themeId' "$state")"; port="$(node -p 'require(process.argv[1]).port' "$state")"; browser="$(node -p 'require(process.argv[1]).browserId' "$state")"; pid="$(node -p 'require(process.argv[1]).injectorPid' "$state")"
node "$root/shared/injector.mjs" --remove --port "$port" --browser-id "$browser"
kill "$pid" 2>/dev/null || true; rm -f "$state"
