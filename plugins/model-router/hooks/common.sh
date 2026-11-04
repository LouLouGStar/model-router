#!/bin/bash
# model-router: shared helpers for the hook launchers (bash 3.2 compatible, sourced).

# Print the path of a python >= 3.6 interpreter, or nothing.
mr_find_python() {
  if [ "${MODEL_ROUTER_FORCE_NO_PYTHON:-0}" = "1" ]; then
    return 0
  fi
  for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1; then
      # macOS without Command Line Tools: /usr/bin/python3 is Apple's shim, and running it pops up the
      # "install developer tools" dialog on every prompt. Skip it while no developer directory is active.
      if [ "$(uname -s 2>/dev/null)" = Darwin ] && [ "$(command -v "$candidate")" = "/usr/bin/$candidate" ] \
         && ! xcode-select -p >/dev/null 2>&1; then
        continue
      fi
      if "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 6) else 1)' >/dev/null 2>&1; then
        printf '%s' "$candidate"
        return 0
      fi
    fi
  done
  return 0
}

# Resolve the context directory (env override, plugin root, or ../context next to this script).
mr_context_dir() {
  if [ -n "${MODEL_ROUTER_CONTEXT_DIR:-}" ]; then
    printf '%s' "$MODEL_ROUTER_CONTEXT_DIR"
  elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT}/context" ]; then
    printf '%s' "${CLAUDE_PLUGIN_ROOT}/context"
  else
    printf '%s' "$1/../context"
  fi
}

# Print the "cwd" value of the raw hook JSON on stdin (crude match), or nothing.
mr_json_cwd() {
  sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' 2>/dev/null | head -1
}

# Print the nearest .claude/model-router.json walking up from $1 (default $PWD; stops below $HOME and at /).
mr_find_project_config() {
  cur="${1:-$PWD}"
  while [ -n "$cur" ] && [ "$cur" != "${HOME:-}" ]; do
    if [ -f "$cur/.claude/model-router.json" ]; then
      printf '%s' "$cur/.claude/model-router.json"
      return 0
    fi
    [ "$cur" = "/" ] && break
    cur="$(dirname "$cur")"
  done
  return 0
}

# Print max_agents (1..1000) from the project config file $1, else 10.
mr_project_cap() {
  cap=""
  if [ -n "${1:-}" ] && [ -f "$1" ]; then
    cap="$(sed -n 's/.*"max_agents"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$1" 2>/dev/null | head -1)"
  fi
  case "$cap" in ''|*[!0-9]*|?????*) cap=10 ;; esac
  if [ "$cap" -lt 1 ] || [ "$cap" -gt 1000 ]; then cap=10; fi
  printf '%s' "$cap"
}

# True (exit 0) when routing is switched off without needing python: env, user state file, or the
# project config found above $1 (default $PWD) saying "enabled": false.
mr_disabled_without_python() {
  if [ "${MODEL_ROUTER_DISABLE:-0}" = "1" ]; then
    return 0
  fi
  state_dir="${MODEL_ROUTER_STATE_DIR:-$HOME/.claude/model-router}"
  state_file="${MODEL_ROUTER_STATE_FILE:-$state_dir/state.json}"
  if [ -f "$state_file" ] && grep -q '"enabled"[[:space:]]*:[[:space:]]*false' "$state_file" 2>/dev/null; then
    return 0
  fi
  project="$(mr_find_project_config "${1:-$PWD}")"
  if [ -n "$project" ] && grep -q '"enabled"[[:space:]]*:[[:space:]]*false' "$project" 2>/dev/null; then
    return 0
  fi
  return 1
}

# JSON-escape stdin (UTF-8 passes through; control chars dropped; lines joined with \n).
mr_json_escape() {
  tab="$(printf '\t')"
  cr="$(printf '\r')"
  tr -d '\000-\010\013\014\016-\037' \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e "s/$tab/\\\\t/g" -e "s/$cr/\\\\r/g" \
    | awk 'NR > 1 { printf "\\n" } { printf "%s", $0 }'
}

# Emit {"hookSpecificOutput":{"hookEventName":"<event>","additionalContext":"<escaped text from file>"}}
mr_emit_file() {
  event_name="$1"
  file="$2"
  extra="$3"
  [ -f "$file" ] || return 0
  body="$( { cat "$file"; if [ -n "$extra" ]; then printf '\n\n%s' "$extra"; fi; } | mr_json_escape)"
  [ -n "$body" ] || return 0
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$event_name" "$body"
}
