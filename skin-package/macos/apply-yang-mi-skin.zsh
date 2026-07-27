#!/usr/bin/env zsh
set -euo pipefail
theme_id="${1:-}"; shift || true
dry_run=false; restart=false; port=9447
while (( $# )); do case "$1" in --dry-run) dry_run=true;; --restart-existing) restart=true;; --port) port="$2"; shift;; *) print -u2 "Unknown option: $1"; exit 2;; esac; shift; done
[[ -n "$theme_id" ]] || { print -u2 'Usage: apply-yang-mi-skin.zsh <theme-id> [--restart-existing] [--dry-run]'; exit 2; }
root="${0:A:h:h}"; injector="$root/shared/injector.mjs"
node "$injector" --theme "$theme_id" --check-payload
$dry_run && exit 0
if pgrep -x Codex >/dev/null && ! $restart; then print -u2 'Save drafts, then rerun with --restart-existing.'; exit 1; fi
if $restart; then osascript -e 'tell application "Codex" to quit' 2>/dev/null || true; sleep 2; fi
open -na Codex --args --remote-debugging-address=127.0.0.1 "--remote-debugging-port=$port"
for i in {1..90}; do curl -fsS "http://127.0.0.1:$port/json/version" >/dev/null 2>&1 && break; sleep .5; done
browser_id="$(curl -fsS "http://127.0.0.1:$port/json/version" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{let u=new URL(JSON.parse(s).webSocketDebuggerUrl);process.stdout.write(u.pathname.split("/").pop())})')"
state_root="$HOME/Library/Application Support/YangMiCodexSkin"; mkdir -p "$state_root"
node "$injector" --watch --theme "$theme_id" --port "$port" --browser-id "$browser_id" >"$state_root/injector.log" 2>"$state_root/injector-error.log" &
pid=$!
printf '{"platform":"macos","themeId":"%s","port":%s,"browserId":"%s","injectorPid":%s}\n' "$theme_id" "$port" "$browser_id" "$pid" > "$state_root/state.json"
sleep 1; node "$injector" --verify --theme "$theme_id" --port "$port" --browser-id "$browser_id"
