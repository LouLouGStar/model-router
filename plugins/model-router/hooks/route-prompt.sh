#!/bin/bash
# model-router UserPromptSubmit hook launcher.
# Reads the hook JSON from stdin, delegates to router_hook.py (python >= 3.6) and falls back to a
# pure-bash injection when no python is available. Prints one JSON object or nothing; always exits 0.
# MODEL_ROUTER_DEBUG=1 forwards the interpreter's stderr; stdout stays clean JSON either way.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$DIR/common.sh"

input="$(cat 2>/dev/null)"
py="$(mr_find_python)"
if [ -n "$py" ]; then
  if [ "${MODEL_ROUTER_DEBUG:-0}" = "1" ]; then
    printf '%s' "$input" | "$py" "$DIR/router_hook.py" userprompt
  else
    printf '%s' "$input" | "$py" "$DIR/router_hook.py" userprompt 2>/dev/null
  fi
  exit 0
fi

# ---- fallback without python ------------------------------------------------------------------
cwd="$(printf '%s' "$input" | mr_json_cwd)"
if mr_disabled_without_python "${cwd:-$PWD}"; then
  exit 0
fi
# Skip slash commands, harness events and empty prompts (crude match on the raw JSON; "prompt" or legacy "user_prompt").
if printf '%s' "$input" | grep -Eq '"(user_)?prompt"[[:space:]]*:[[:space:]]*"(/|<|\\u003c|")'; then
  exit 0
fi
if ! printf '%s' "$input" | grep -Eq '"(user_)?prompt"'; then
  exit 0
fi
ctx="$(mr_context_dir "$DIR")"
template="$ctx/protocol-prompt.md"
[ -f "$template" ] || exit 0
body="$(sed 's/{{HINTS}}/hints: unavailable (no python)/' "$template" 2>/dev/null | mr_json_escape)"
[ -n "$body" ] || exit 0
printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$body"
exit 0
