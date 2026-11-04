#!/bin/bash
# model-router state switch: state.sh on | off | status   (always exits 0; output in German)
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$DIR/common.sh"
STATE_DIR="${MODEL_ROUTER_STATE_DIR:-$HOME/.claude/model-router}"
STATE_FILE="${MODEL_ROUTER_STATE_FILE:-$STATE_DIR/state.json}"
cmd="${1:-status}"
stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"

write_state() {
  mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null || true
  printf '{"enabled": %s, "updated": "%s"}\n' "$1" "$stamp" > "$STATE_FILE" 2>/dev/null || {
    echo "Konnte $STATE_FILE nicht schreiben."
    return 0
  }
}

plugin_version() {
  manifest="$DIR/../.claude-plugin/plugin.json"
  [ -f "$manifest" ] || { echo "unbekannt"; return 0; }
  sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest" | head -1
}

case "$cmd" in
  on)
    write_state true
    echo "model-router ist eingeschaltet. Das Routing-Protokoll wird ab dem nächsten Prompt wieder eingespielt."
    ;;
  off)
    write_state false
    echo "model-router ist ausgeschaltet. Bis /model-router:on wird kein Routing-Protokoll mehr eingespielt."
    ;;
  status)
    enabled="an"
    if [ "${MODEL_ROUTER_DISABLE:-0}" = "1" ]; then
      enabled="aus (Umgebungsvariable MODEL_ROUTER_DISABLE=1)"
    elif [ -f "$STATE_FILE" ] && grep -q '"enabled"[[:space:]]*:[[:space:]]*false' "$STATE_FILE" 2>/dev/null; then
      enabled="aus (per /model-router:off, Datei $STATE_FILE)"
    fi
    project="$(mr_find_project_config "$PWD")"
    if [ -n "$project" ]; then
      if grep -q '"enabled"[[:space:]]*:[[:space:]]*false' "$project" 2>/dev/null; then
        enabled="aus (Projekt-Config $project)"
      fi
      project_line="Projekt-Config: $project"
    else
      project_line="Projekt-Config: keine (.claude/model-router.json nicht gefunden)"
    fi
    py="$(mr_find_python)"
    if [ -n "$py" ]; then
      pyver="$("$py" -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null)"
      py_line="Python: $py $pyver (volle Hinweis-Erkennung aktiv)"
    else
      py_line="Python: nicht gefunden (Fallback ohne Hinweise aktiv)"
    fi
    echo "model-router $(plugin_version) – Routing: $enabled"
    echo "$project_line"
    echo "$py_line"
    if [ -n "$py" ]; then
      "$py" "$DIR/router_hook.py" selftest 2>/dev/null | sed 's/^/Selbsttest: /'
    fi
    ;;
  *)
    echo "Verwendung: state.sh on | off | status"
    ;;
esac
exit 0
