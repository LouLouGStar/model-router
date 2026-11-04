#!/bin/bash
# model-router SessionStart hook launcher (startup|resume|clear|compact).
# Injects the full routing protocol as additionalContext. Prints one JSON object or nothing; exits 0.
# MODEL_ROUTER_DEBUG=1 forwards the interpreter's stderr; stdout stays clean JSON either way.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$DIR/common.sh"

input="$(cat 2>/dev/null)"
py="$(mr_find_python)"
if [ -n "$py" ]; then
  if [ "${MODEL_ROUTER_DEBUG:-0}" = "1" ]; then
    printf '%s' "$input" | "$py" "$DIR/router_hook.py" sessionstart
  else
    printf '%s' "$input" | "$py" "$DIR/router_hook.py" sessionstart 2>/dev/null
  fi
  exit 0
fi

# ---- fallback without python ------------------------------------------------------------------
cwd="$(printf '%s' "$input" | mr_json_cwd)"
cwd="${cwd:-$PWD}"
if mr_disabled_without_python "$cwd"; then
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"model-router is installed but switched off (/model-router:on to enable)."}}\n'
  exit 0
fi
ctx="$(mr_context_dir "$DIR")"
cap="$(mr_project_cap "$(mr_find_project_config "$cwd")")"
mr_emit_file "SessionStart" "$ctx/protocol-session.md" "Routing state: on. Max agents per workflow: $cap."
exit 0
