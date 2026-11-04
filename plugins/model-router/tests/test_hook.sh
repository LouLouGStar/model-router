#!/bin/bash
# model-router hook test suite (bash 3.2 compatible).
# Run from the repo root: bash plugins/model-router/tests/test_hook.sh   Exit 1 on any failure.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
HOOKS="$PLUGIN/hooks"
FIX="$HERE/fixtures"
TMP="$(mktemp -d 2>/dev/null || mktemp -d -t mrtest)"
trap 'rm -rf "$TMP"' EXIT

# Isolate state: no real user state file, no project config above /tmp.
export HOME="$TMP/home"; mkdir -p "$HOME"
export MODEL_ROUTER_STATE_DIR="$TMP/state"
unset MODEL_ROUTER_DISABLE MODEL_ROUTER_FORCE_NO_PYTHON MODEL_ROUTER_CONTEXT_DIR MODEL_ROUTER_DEBUG 2>/dev/null || true

pass=0; fail=0
ok()   { pass=$((pass + 1)); printf 'PASS  %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf 'FAIL  %s\n      %s\n' "$1" "$2"; }

# json_field KEY  -> prints hookSpecificOutput.<KEY> from the JSON on stdin (python3 preferred, jq fallback)
PY="$(command -v python3 || true)"
JQ="$(command -v jq || true)"
json_field() {
  if [ -n "$PY" ]; then
    "$PY" -c 'import json,sys; o=json.loads(sys.stdin.buffer.read().decode("utf-8","surrogateescape")); v=o["hookSpecificOutput"][sys.argv[1]]; sys.stdout.buffer.write((v if isinstance(v,str) else json.dumps(v)).encode("utf-8","surrogateescape")+b"\n")' "$1" 2>/dev/null
  elif [ -n "$JQ" ]; then
    "$JQ" -r ".hookSpecificOutput.$1" 2>/dev/null
  else
    cat
  fi
}
is_json() {
  if [ -n "$PY" ]; then "$PY" -c 'import json,sys; json.loads(sys.stdin.buffer.read().decode("utf-8","surrogateescape"))' 2>/dev/null
  elif [ -n "$JQ" ]; then "$JQ" -e . >/dev/null 2>&1
  else grep -q '^{.*}$'; fi
}
run_hook() { # run_hook SCRIPT FIXTURE  -> stdout in $OUT, exit code in $RC, stderr in $TMP/stderr
  OUT="$(bash "$HOOKS/$1" < "$2" 2>"$TMP/stderr")"; RC=$?
}
expect_empty() { # NAME
  if [ -z "$OUT" ] && [ "$RC" -eq 0 ]; then ok "$1"; else bad "$1" "expected no output, got rc=$RC: $(printf '%s' "$OUT" | head -c 200)"; fi
}
check_json_event() { # NAME EVENT -> 0 when stdout is exactly one JSON object for EVENT (else reports FAIL)
  lines=$(printf '%s\n' "$OUT" | grep -c .)
  if [ "$RC" -ne 0 ]; then bad "$1" "exit code $RC"; return 1; fi
  if [ "$lines" -ne 1 ]; then bad "$1" "expected exactly 1 output line, got $lines"; return 1; fi
  if ! printf '%s' "$OUT" | is_json; then bad "$1" "stdout is not valid JSON: $(printf '%s' "$OUT" | head -c 200)"; return 1; fi
  got_event="$(printf '%s' "$OUT" | json_field hookEventName)"
  if [ "$got_event" != "$2" ]; then bad "$1" "hookEventName=$got_event, expected $2"; return 1; fi
  return 0
}
expect_json_with() { # NAME EVENT NEEDLE...  (every needle must occur in additionalContext)
  name="$1"; event="$2"; shift 2
  check_json_event "$name" "$event" || return
  ctx="$(printf '%s' "$OUT" | json_field additionalContext)"
  for needle in "$@"; do
    if ! printf '%s' "$ctx" | grep -q -- "$needle"; then bad "$name" "additionalContext lacks '$needle'"; return; fi
  done
  ok "$name"
}
expect_json_without() { # NAME EVENT NEEDLE...  (valid JSON whose additionalContext lacks every needle)
  name="$1"; event="$2"; shift 2
  check_json_event "$name" "$event" || return
  ctx="$(printf '%s' "$OUT" | json_field additionalContext)"
  for needle in "$@"; do
    if printf '%s' "$ctx" | grep -q -- "$needle"; then bad "$name" "additionalContext must not contain '$needle'"; return; fi
  done
  ok "$name"
}
ctx_len() { printf '%s' "$OUT" | json_field additionalContext | wc -c | tr -d ' '; }
set_project() { printf '%s' "$1" > "$TMP/proj/.claude/model-router.json"; }

echo "== static checks =="
for f in "$HOOKS"/*.sh; do
  if bash -n "$f" 2>"$TMP/err"; then ok "bash -n $(basename "$f")"; else bad "bash -n $(basename "$f")" "$(cat "$TMP/err")"; fi
done
if [ -n "$PY" ]; then
  if "$PY" -m py_compile "$HOOKS/router_hook.py" 2>"$TMP/err"; then ok "py_compile router_hook.py"; else bad "py_compile router_hook.py" "$(cat "$TMP/err")"; fi
  if "$PY" -c 'import json,sys; json.load(open(sys.argv[1]))' "$HOOKS/hooks.json" 2>"$TMP/err"; then ok "hooks.json parses"; else bad "hooks.json parses" "$(cat "$TMP/err")"; fi
  if grep -q '"hooks"' "$HOOKS/hooks.json" && grep -q 'UserPromptSubmit' "$HOOKS/hooks.json" && grep -q 'SessionStart' "$HOOKS/hooks.json"; then ok "hooks.json declares both events under the hooks wrapper"; else bad "hooks.json wrapper" "missing hooks/UserPromptSubmit/SessionStart"; fi
  if grep -q 'python 3\|sys.version_info' "$HOOKS/common.sh" && ! grep -Eq '\| None|:=' "$HOOKS/router_hook.py"; then ok "no python>=3.10-only syntax in router_hook.py"; else bad "python compat" "found 3.10+ syntax or missing version probe"; fi
fi
head -1 "$PLUGIN/context/protocol-session.md" | grep -q '^# model-router protocol (standing instructions)$' && ok "protocol-session.md heading" || bad "protocol-session.md heading" "$(head -1 "$PLUGIN/context/protocol-session.md")"
head -1 "$PLUGIN/context/protocol-prompt.md" | grep -q '^model-router — decide before acting\.' && ok "protocol-prompt.md opening" || bad "protocol-prompt.md opening" "$(head -1 "$PLUGIN/context/protocol-prompt.md")"
[ "$(grep -c '{{HINTS}}' "$PLUGIN/context/protocol-prompt.md")" -eq 1 ] && ok "protocol-prompt.md has one {{HINTS}} placeholder" || bad "{{HINTS}} placeholder" "count != 1"

echo "== UserPromptSubmit =="
run_hook route-prompt.sh "$FIX/01-multistep.json"
expect_json_with "01 multi-step prompt gets the protocol + hints" UserPromptSubmit "model-router" "list-items=3" "sequence-words" "words=" "workflow-cap=10" "session-model=unknown"
len=$(ctx_len); if [ "${len:-0}" -le 900 ]; then ok "01 rendered prompt context <= 900 chars ($len)"; else bad "01 rendered size" "$len chars > 900"; fi
run_hook route-prompt.sh "$FIX/02-slash.json";   expect_empty "02 slash command is skipped"
run_hook route-prompt.sh "$FIX/03-short.json";   expect_empty "03 short prompt is skipped"
run_hook route-prompt.sh "$FIX/04-harness.json"; expect_empty "04 harness event is skipped"
run_hook route-prompt.sh "$FIX/05-explicit-model.json"; expect_json_with "05 explicit model + thorough hints" UserPromptSubmit "explicit-model=opus" "thorough"
run_hook route-prompt.sh "$FIX/06-opt-out.json"; expect_json_with "06 opt-out hint" UserPromptSubmit "opt-out"
run_hook route-prompt.sh "$FIX/07-plan-mode.json"; expect_json_with "07 plan-mode hint" UserPromptSubmit "plan-mode"
run_hook route-prompt.sh "$FIX/08-sweep.json"; expect_json_with "08 sweep + fast hints" UserPromptSubmit "sweep-words" "fast"
run_hook route-prompt.sh "$FIX/10-user-prompt-legacy-key.json"; expect_json_with "10 legacy user_prompt key accepted" UserPromptSubmit "model-router"
run_hook route-prompt.sh "$FIX/11-invalid.txt"; expect_empty "11 invalid JSON on stdin -> silent, exit 0"
MODEL_ROUTER_DISABLE=1 run_hook route-prompt.sh "$FIX/01-multistep.json"; expect_empty "12 MODEL_ROUTER_DISABLE=1 silences the hook"
run_hook route-prompt.sh "$FIX/22-quote-start.json"; expect_json_with "13 prompt starting with a quote is routed" UserPromptSubmit "model-router"
run_hook route-prompt.sh "$FIX/23-empty-prompt.json"; expect_empty "14 empty prompt is skipped"

echo "== hints: tightened regexes, positive and negative =="
run_hook route-prompt.sh "$FIX/12-nicht-perfekt.json"
expect_json_with "15 'nicht perfekt … grob' -> fast" UserPromptSubmit "fast"
expect_json_without "15 'nicht perfekt' -> no thorough" UserPromptSubmit "thorough"
run_hook route-prompt.sh "$FIX/13-poem-words.json"
expect_json_without "16 Haiku/fable/opus as poem words -> no explicit-model" UserPromptSubmit "explicit-model"
run_hook route-prompt.sh "$FIX/14-model-list.json"
expect_json_with "17 'mit haiku oder sonnet … auf opus … #model=fable' -> explicit-model list" UserPromptSubmit "explicit-model=haiku,sonnet,opus,fable"
run_hook route-prompt.sh "$FIX/15-german-negatives.json"
expect_json_without "18 'Also …', alles, Kurzschluss, Schnellstart, Entwurfsmuster, Reviewer, Sicherheitslücke -> no hints" UserPromptSubmit "sequence-words" "sweep-words" "fast" "thorough"
run_hook route-prompt.sh "$FIX/16-english-negatives.json"
expect_json_without "19 'than', 'reviewer', 'the sonnet about autumn' -> no hints" UserPromptSubmit "sequence-words" "thorough" "explicit-model"
run_hook route-prompt.sh "$FIX/17-sweep-inflections.json"; expect_json_with "20 'in allen Dateien jeden Import' -> sweep-words" UserPromptSubmit "sweep-words"
run_hook route-prompt.sh "$FIX/18-fast-inflections.json"
expect_json_with "21 'kurze … grobe' -> fast" UserPromptSubmit "fast"
expect_json_without "21 'kurze … grobe' -> no thorough" UserPromptSubmit "thorough"
run_hook route-prompt.sh "$FIX/19-thorough-forms.json"
expect_json_with "22 'reviewed … sicher' -> thorough" UserPromptSubmit "thorough"
expect_json_without "22 'reviewed … sicher' -> no fast" UserPromptSubmit "fast"
run_hook route-prompt.sh "$FIX/20-english-sequence.json"; expect_json_with "23 'then … and also' -> sequence-words" UserPromptSubmit "sequence-words"
run_hook route-prompt.sh "$FIX/21-curly-apostrophe.json"; expect_json_with "24 curly-apostrophe don’t delegate -> opt-out" UserPromptSubmit "opt-out"

echo "== session model from the transcript tail =="
sed "s#/nonexistent/transcript.jsonl#$FIX/transcript-sonnet.jsonl#" "$FIX/01-multistep.json" > "$TMP/with-transcript.json"
run_hook route-prompt.sh "$TMP/with-transcript.json"; expect_json_with "25 session-model read from transcript tail" UserPromptSubmit "session-model=sonnet"
{ cat "$FIX/transcript-sonnet.jsonl"; printf '{"type":"user","message":{"role":"user","content":"'; dd if=/dev/zero bs=1024 count=200 2>/dev/null | tr '\000' 'x'; printf '"}}\n'; } > "$TMP/big-tail.jsonl"
sed "s#/nonexistent/transcript.jsonl#$TMP/big-tail.jsonl#" "$FIX/01-multistep.json" > "$TMP/with-big-transcript.json"
run_hook route-prompt.sh "$TMP/with-big-transcript.json"; expect_json_with "26 session-model found behind a 200 KB last line" UserPromptSubmit "session-model=sonnet"

echo "== project config =="
mkdir -p "$TMP/proj/.claude"; set_project '{"enabled": false}'
sed "s#\"cwd\": \"/tmp\"#\"cwd\": \"$TMP/proj\"#" "$FIX/01-multistep.json" > "$TMP/proj-off.json"
sed "s#\"cwd\": \"/tmp\"#\"cwd\": \"$TMP/proj\"#" "$FIX/09-sessionstart.json" > "$TMP/proj-session.json"
run_hook route-prompt.sh "$TMP/proj-off.json"; expect_empty "27 project config enabled=false silences the hook"
set_project '{"max_agents": 6}'
run_hook route-prompt.sh "$TMP/proj-off.json"; expect_json_with "28 project config max_agents -> workflow-cap" UserPromptSubmit "workflow-cap=6"
expect_json_without "28 default_review absent -> no default-review hint" UserPromptSubmit "default-review"
run_hook session-context.sh "$TMP/proj-session.json"; expect_json_with "29 session trailer carries project max_agents" SessionStart "Max agents per workflow: 6"
set_project '{"default_review": "never"}'
run_hook route-prompt.sh "$TMP/proj-off.json"; expect_json_with "30 default_review=never -> hint default-review=never" UserPromptSubmit "default-review=never"
set_project '{"default_review": "always", "max_agents": 4}'
run_hook route-prompt.sh "$TMP/proj-off.json"; expect_json_with "31 default_review=always -> hint after workflow-cap" UserPromptSubmit "workflow-cap=4; default-review=always"
set_project '{"default_review": "auto"}'
run_hook route-prompt.sh "$TMP/proj-off.json"; expect_json_without "32 default_review=auto -> no default-review hint" UserPromptSubmit "default-review"
set_project '{"default_review": "sometimes"}'
run_hook route-prompt.sh "$TMP/proj-off.json"; expect_json_without "33 invalid default_review -> no default-review hint" UserPromptSubmit "default-review"

echo "== user state via state.sh =="
bash "$HOOKS/state.sh" off >/dev/null
run_hook route-prompt.sh "$FIX/01-multistep.json"; expect_empty "34 state.sh off silences the hook"
bash "$HOOKS/state.sh" on >/dev/null
run_hook route-prompt.sh "$FIX/01-multistep.json"; expect_json_with "35 state.sh on re-enables the hook" UserPromptSubmit "model-router"
bash "$HOOKS/state.sh" status | grep -q "Routing: an" && ok "36 state.sh status reports 'an'" || bad "36 state.sh status" "$(bash "$HOOKS/state.sh" status)"

echo "== SessionStart =="
run_hook session-context.sh "$FIX/09-sessionstart.json"
expect_json_with "37 session start injects the full protocol" SessionStart "model-router protocol (standing instructions)" "Routing state: on" "Max agents per workflow: 10"
len=$(ctx_len); if [ "${len:-0}" -lt 10000 ]; then ok "37 session context < 10000 chars ($len)"; else bad "37 session size" "$len chars"; fi
bash "$HOOKS/state.sh" off >/dev/null
run_hook session-context.sh "$FIX/09-sessionstart.json"; expect_json_with "38 session start while off says so briefly" SessionStart "switched off"
bash "$HOOKS/state.sh" on >/dev/null
mkdir -p "$TMP/bigctx"; cp "$PLUGIN/context/protocol-prompt.md" "$TMP/bigctx/"
{ echo '# model-router protocol (standing instructions)'; dd if=/dev/zero bs=1024 count=12 2>/dev/null | tr '\000' 'x'; echo; } > "$TMP/bigctx/protocol-session.md"
MODEL_ROUTER_CONTEXT_DIR="$TMP/bigctx" run_hook session-context.sh "$FIX/09-sessionstart.json"
expect_json_with "39 oversized protocol-session.md is truncated but keeps the state trailer" SessionStart "Routing state: on" "Max agents per workflow: 10"
len=$(ctx_len); if [ "${len:-0}" -lt 10000 ]; then ok "39 truncated session context < 10000 chars ($len)"; else bad "39 truncated size" "$len chars"; fi

echo "== MODEL_ROUTER_DEBUG=1 (stderr passthrough, stdout untouched) =="
MODEL_ROUTER_DEBUG=1 run_hook route-prompt.sh "$FIX/01-multistep.json"
expect_json_with "40 DEBUG=1: stdout is still exactly one JSON object" UserPromptSubmit "model-router" "workflow-cap=10"
MODEL_ROUTER_DEBUG=1 run_hook route-prompt.sh "$FIX/03-short.json"; expect_empty "41 DEBUG=1: skipped prompt still prints nothing on stdout"
grep -q '\[model-router\] skip' "$TMP/stderr" && ok "41 DEBUG=1: diagnostics reach stderr through the launcher" || bad "41 DEBUG stderr" "no [model-router] line: $(head -c 200 "$TMP/stderr")"
run_hook route-prompt.sh "$FIX/03-short.json"
[ ! -s "$TMP/stderr" ] && ok "42 without DEBUG the launcher keeps stderr silent" || bad "42 stderr not silent" "$(head -c 200 "$TMP/stderr")"
MODEL_ROUTER_DEBUG=1 run_hook session-context.sh "$FIX/09-sessionstart.json"
expect_json_with "43 DEBUG=1: session start stdout is one JSON object" SessionStart "Routing state: on"

echo "== fallback without python =="
MODEL_ROUTER_FORCE_NO_PYTHON=1 run_hook session-context.sh "$FIX/09-sessionstart.json"
expect_json_with "44 no-python session start still injects the protocol" SessionStart "model-router protocol (standing instructions)" "Max agents per workflow: 10"
MODEL_ROUTER_FORCE_NO_PYTHON=1 run_hook route-prompt.sh "$FIX/01-multistep.json"
expect_json_with "45 no-python prompt hook injects template with placeholder note" UserPromptSubmit "hints: unavailable"
MODEL_ROUTER_FORCE_NO_PYTHON=1 run_hook route-prompt.sh "$FIX/02-slash.json"; expect_empty "46 no-python fallback skips slash commands"
MODEL_ROUTER_FORCE_NO_PYTHON=1 run_hook route-prompt.sh "$FIX/04-harness.json"; expect_empty "47 no-python fallback skips harness events"
MODEL_ROUTER_FORCE_NO_PYTHON=1 run_hook route-prompt.sh "$FIX/23-empty-prompt.json"; expect_empty "48 no-python fallback skips an empty prompt"
MODEL_ROUTER_FORCE_NO_PYTHON=1 run_hook route-prompt.sh "$FIX/22-quote-start.json"; expect_json_with "49 no-python fallback injects for a prompt that starts with a quote" UserPromptSubmit "hints: unavailable"
MODEL_ROUTER_FORCE_NO_PYTHON=1 run_hook route-prompt.sh "$FIX/10-user-prompt-legacy-key.json"; expect_json_with "50 no-python fallback accepts the legacy user_prompt key" UserPromptSubmit "hints: unavailable"
MODEL_ROUTER_FORCE_NO_PYTHON=1 MODEL_ROUTER_DISABLE=1 run_hook route-prompt.sh "$FIX/01-multistep.json"; expect_empty "51 no-python fallback honours MODEL_ROUTER_DISABLE"
set_project '{"enabled": false}'
MODEL_ROUTER_FORCE_NO_PYTHON=1 run_hook route-prompt.sh "$TMP/proj-off.json"; expect_empty "52 no-python fallback honours project enabled=false"
MODEL_ROUTER_FORCE_NO_PYTHON=1 run_hook session-context.sh "$TMP/proj-session.json"; expect_json_with "52 no-python session start while project-off says so briefly" SessionStart "switched off"
set_project '{"max_agents": 6}'
MODEL_ROUTER_FORCE_NO_PYTHON=1 run_hook session-context.sh "$TMP/proj-session.json"; expect_json_with "53 no-python session trailer carries project max_agents" SessionStart "Max agents per workflow: 6"
mkdir -p "$TMP/ctx"; printf 'a "q" b\\s\tc \303\274\r\n\001x %s\n' '{{HINTS}}' > "$TMP/ctx/protocol-prompt.md"
MODEL_ROUTER_CONTEXT_DIR="$TMP/ctx" MODEL_ROUTER_FORCE_NO_PYTHON=1 run_hook route-prompt.sh "$FIX/01-multistep.json"
expect_json_with "54 no-python escaper: quote/backslash/tab/CR/umlaut round-trip" UserPromptSubmit 'a "q" b\\s' 'c ü' 'x hints: unavailable'
ls "${TMPDIR:-/tmp}"/model-router-prompt.* >/dev/null 2>&1 && bad "55 no-python fallback leaves a temp file" "$(ls "${TMPDIR:-/tmp}"/model-router-prompt.*)" || ok "55 no-python fallback writes no temp file"

echo "== timing =="
start=$(date +%s)
for i in 1 2 3 4 5; do bash "$HOOKS/route-prompt.sh" < "$FIX/01-multistep.json" >/dev/null; done
end=$(date +%s)
if [ $((end - start)) -le 5 ]; then ok "56 five hook runs took <= 5 s ($((end - start)) s)"; else bad "56 timing" "$((end - start)) s for 5 runs"; fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
