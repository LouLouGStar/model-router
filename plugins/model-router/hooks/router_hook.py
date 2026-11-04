#!/usr/bin/env python3
"""model-router hook logic (python 3.6+; no third-party modules).

Usage:  router_hook.py userprompt    (stdin: UserPromptSubmit JSON)
        router_hook.py sessionstart  (stdin: SessionStart JSON)
        router_hook.py selftest      (prints the rendered UserPromptSubmit output for a sample prompt)

Contract: print exactly ONE JSON object to stdout, or nothing. Always exit 0.
Diagnostics only on stderr and only when MODEL_ROUTER_DEBUG=1 (the launchers forward stderr only then).
"""
import io
import json
import os
import re
import sys

PROJECT_CONFIG = os.path.join(".claude", "model-router.json")
DEFAULT_MAX_AGENTS = 10
SESSION_CONTEXT_CAP = 9500
TRANSCRIPT_TAIL_STEPS = (64 * 1024, 1024 * 1024, 4 * 1024 * 1024)  # grown when a huge last line swallows the window
MODEL_FAMILIES = ("haiku", "sonnet", "opus", "fable")

SAMPLE_PROMPT = (
    "Bitte drei Dinge:\n"
    "- übersetze die drei Sätze wörtlich ins Englische\n"
    "- schreib dann eine freundliche Mail an den Vermieter wegen der Heizung\n"
    "- danach prüfe gründlich, ob SQLite oder JSON-Dateien für den Planer-Bot besser sind"
)

# --- regexes (case-insensitive, German + English) ---------------------------------------------
# A model word counts only in routing context ("mit Opus", "use the haiku model", "Haiku-Modell",
# "claude-sonnet", "Opus 4.5", "model: fable"), never as a poem/story noun ("ein Haiku über den Herbst",
# "a fable about a fox", "magnum opus"). A list after the anchor is kept ("mit haiku oder sonnet").
RE_MODEL_WORD = re.compile(
    r"\b(?:mit|with|use|using|via|nimm|take|model|modell|auf|per|durch|by|nutze|verwende|lieber)(?::\s*|\s+)"
    r"(?:dem|der|den|the)?\s*(?:haiku|sonnet|opus|fable)\b"
    r"(?:\s*(?:,|und|and|oder|or|/)\s*(?:haiku|sonnet|opus|fable)\b)*"
    r"|\b(?:haiku|sonnet|opus|fable)(?=[- ](?:model|modell|agent|worker|tier|version|nutzen|verwenden|benutzen|reicht|statt|only|nur)\b|\s*[0-9])"
    r"|\bclaude[- ](?:haiku|sonnet|opus|fable)\b",
    re.I,
)
RE_MODEL_NAME = re.compile(r"\b(haiku|sonnet|opus|fable)\b", re.I)
RE_MODEL_TAG = re.compile(r"#model=([a-z0-9.-]+)", re.I)
RE_OPT_OUT = re.compile(
    r"#noroute|#noshift|kein routing|nicht routen|nicht delegieren|mach es selbst|mach das selbst|"
    r"selber machen|selbst machen|do it yourself|don['’]?t delegate|no routing|no agents|keine agents|keine agenten",
    re.I,
)
# "nicht perfekt" / "not perfect" belong to RE_FAST only; "reviewer" and "Sicherheitslücke" do not count.
RE_THOROUGH = re.compile(
    r"gründlich|sorgfältig|\bsicher(heit)?\b|(?<!nicht )(?<!not )perfekt|prüf|gegenprüf|\breview(s|ed|ing)?\b|verif|"
    r"thorough|careful|\baudit\b|alle fehler|double-check",
    re.I,
)
# Inflections count (kurze, grobe); compounds do not (Kurzschluss, Schnellstart, Entwurfsmuster).
RE_FAST = re.compile(
    r"\bschnell(?!start)|\bgrob(e[nrs]?)?\b|\bkurz(e[nrs]?)?\b|\bentwurf\b|\bdraft\b|\bquick(ly)?\b|\brough(ly)?\b|"
    r"nur mal|nicht perfekt|not perfect",
    re.I,
)
RE_LIST_LINE = re.compile(r"^\s*(?:[-*•]|\d+[.)])\s+\S", re.M)
RE_INLINE_ENUM = re.compile(r"\(\d+\)")
# English "also" only as an additive ("and also", "also add …"); the German particle "Also, …" is not a sequence.
RE_SEQUENCE = re.compile(
    r"und dann|danach|anschließend|außerdem|zusätzlich|\bthen\b|after that|afterwards|and then|"
    r"\b(?:and|but) also\b|\balso (?:add|write|check|create|fix|make|update|run|include|test|remove|rename|change|please|the|a|an|need|want|do)\b",
    re.I,
)
# Dative/accusative forms count (allen, jeden, jedem); "alles", "allerdings", "jedenfalls" do not.
RE_SWEEP = re.compile(
    r"\balle[nrm]?\b|\bjede[rsnm]?\b|sämtliche|\bevery\b|\beach\b|all files|für jede|for every|for each", re.I
)


def debug(msg):
    if os.environ.get("MODEL_ROUTER_DEBUG") == "1":
        sys.stderr.write("[model-router] %s\n" % msg)


def read_stdin_json():
    try:
        raw = io.TextIOWrapper(sys.stdin.buffer, encoding="utf-8", errors="replace").read()
    except Exception:
        raw = sys.stdin.read()
    raw = raw.strip()
    if not raw:
        return {}
    data = json.loads(raw)
    return data if isinstance(data, dict) else {}


def script_dir():
    return os.path.dirname(os.path.abspath(__file__))


def context_dir():
    override = os.environ.get("MODEL_ROUTER_CONTEXT_DIR")
    if override:
        return override
    root = os.environ.get("CLAUDE_PLUGIN_ROOT")
    if root and os.path.isdir(os.path.join(root, "context")):
        return os.path.join(root, "context")
    return os.path.join(os.path.dirname(script_dir()), "context")


def read_text(path):
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        return handle.read()


def read_json_file(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def user_state_file():
    override = os.environ.get("MODEL_ROUTER_STATE_FILE")
    if override:
        return override
    state_dir = os.environ.get("MODEL_ROUTER_STATE_DIR") or os.path.join(os.path.expanduser("~"), ".claude", "model-router")
    return os.path.join(state_dir, "state.json")


def find_project_config(start):
    """Walk up from start looking for .claude/model-router.json; stop below $HOME or at the filesystem root."""
    if not start:
        return None
    try:
        cur = os.path.abspath(start)
    except Exception:
        return None
    home = os.path.abspath(os.path.expanduser("~"))
    for _ in range(64):
        if cur == home:
            return None
        candidate = os.path.join(cur, PROJECT_CONFIG)
        if os.path.isfile(candidate):
            return candidate
        parent = os.path.dirname(cur)
        if parent == cur:
            return None
        cur = parent
    return None


def resolve_config(cwd):
    """Returns dict: enabled (bool), max_agents (int), default_review (str), sources (list of str)."""
    cfg = {"enabled": True, "max_agents": DEFAULT_MAX_AGENTS, "default_review": "auto", "sources": []}
    if os.environ.get("MODEL_ROUTER_DISABLE") == "1":
        cfg["enabled"] = False
        cfg["sources"].append("env MODEL_ROUTER_DISABLE=1")
    user = read_json_file(user_state_file())
    if "enabled" in user and user["enabled"] is False:
        cfg["enabled"] = False
        cfg["sources"].append("user state off")
    project_path = find_project_config(cwd)
    if project_path:
        project = read_json_file(project_path)
        cfg["sources"].append("project config " + project_path)
        if project.get("enabled") is False:
            cfg["enabled"] = False
        if project.get("enabled") is True and "user state off" not in cfg["sources"] and os.environ.get("MODEL_ROUTER_DISABLE") != "1":
            cfg["enabled"] = True
        max_agents = project.get("max_agents")
        if isinstance(max_agents, int) and 0 < max_agents <= 1000:
            cfg["max_agents"] = max_agents
        review = project.get("default_review")
        if review in ("auto", "always", "never"):
            cfg["default_review"] = review
    return cfg


def should_skip_prompt(prompt):
    text = prompt.strip()
    if not text:
        return "empty"
    if text.startswith("/"):
        return "slash command"
    if text.startswith("<"):
        return "harness event"
    if len(text.split()) < 3 and "\n" not in text:
        return "too short"
    return None


def model_family_in(lines):
    """Family of the last main-session model in lines; "unknown" for an unmapped id; None when no model line."""
    for raw in reversed(lines):
        if b'"model"' not in raw:
            continue
        try:
            entry = json.loads(raw.decode("utf-8", errors="replace"))
        except Exception:
            continue
        if not isinstance(entry, dict) or entry.get("isSidechain"):
            continue
        model = None
        if entry.get("type") == "assistant":
            message = entry.get("message") or {}
            model = message.get("model") if isinstance(message, dict) else None
        elif entry.get("type") == "attachment":
            attachment = entry.get("attachment") or {}
            if isinstance(attachment, dict) and attachment.get("type") == "model":
                identity = attachment.get("identity") or {}
                model = identity.get("modelId") if isinstance(identity, dict) else None
        if model and model != "<synthetic>":
            lowered = str(model).lower()
            for family in MODEL_FAMILIES:
                if family in lowered:
                    return family
            return "unknown"
    return None


def session_model_family(transcript_path):
    """Model family of the main session, read from the transcript tail. Never raises."""
    try:
        if not transcript_path:
            return "unknown"
        path = os.path.expanduser(transcript_path)
        if not os.path.isfile(path):
            return "unknown"
        size = os.path.getsize(path)
        with open(path, "rb") as handle:
            for tail in TRANSCRIPT_TAIL_STEPS:
                handle.seek(max(size - tail, 0))
                if size > tail:
                    handle.readline()  # drop the partial line
                family = model_family_in(handle.read().splitlines())
                if family or size <= tail:
                    return family or "unknown"
        return "unknown"
    except Exception as exc:
        debug("transcript: %s" % exc)
        return "unknown"


def extract_hints(prompt, permission_mode, transcript_path, cfg):
    hints = []
    models = []
    for match in RE_MODEL_WORD.finditer(prompt):
        for name in RE_MODEL_NAME.findall(match.group(0)):
            if name.lower() not in models:
                models.append(name.lower())
    for match in RE_MODEL_TAG.finditer(prompt):
        name = match.group(1).lower()
        if name not in models:
            models.append(name)
    if models:
        hints.append("explicit-model=" + ",".join(models))
    if RE_OPT_OUT.search(prompt):
        hints.append("opt-out")
    if RE_THOROUGH.search(prompt):
        hints.append("thorough")
    if RE_FAST.search(prompt):
        hints.append("fast")
    list_items = max(len(RE_LIST_LINE.findall(prompt)), len(RE_INLINE_ENUM.findall(prompt)))
    if list_items >= 2:
        hints.append("list-items=%d" % list_items)
    if RE_SEQUENCE.search(prompt):
        hints.append("sequence-words")
    if RE_SWEEP.search(prompt):
        hints.append("sweep-words")
    hints.append("words=%d" % len(prompt.split()))
    hints.append("lines=%d" % (prompt.count("\n") + 1))
    if permission_mode == "plan":
        hints.append("plan-mode")
    hints.append("session-model=" + session_model_family(transcript_path))
    hints.append("workflow-cap=%d" % cfg["max_agents"])
    if cfg["default_review"] != "auto":  # only when the project config sets always|never
        hints.append("default-review=" + cfg["default_review"])
    return "; ".join(hints)


def render_prompt_context(hints):
    template = read_text(os.path.join(context_dir(), "protocol-prompt.md"))
    return template.replace("{{HINTS}}", hints if hints else "none").strip()


def render_session_context(cfg):
    trailer = "\n\nRouting state: on. Max agents per workflow: %d." % cfg["max_agents"]
    text = read_text(os.path.join(context_dir(), "protocol-session.md")).rstrip()
    if len(text) + len(trailer) > SESSION_CONTEXT_CAP:  # safety net; the state trailer always survives
        text = text[:SESSION_CONTEXT_CAP - len(trailer)].rstrip()
    return text + trailer


def emit(event_name, text):
    payload = {"hookSpecificOutput": {"hookEventName": event_name, "additionalContext": text}}
    sys.stdout.write(json.dumps(payload, ensure_ascii=True))
    sys.stdout.write("\n")
    sys.stdout.flush()


def handle_userprompt(data):
    prompt = data.get("prompt")
    if not isinstance(prompt, str):
        prompt = data.get("user_prompt")
    if not isinstance(prompt, str):
        debug("no prompt field")
        return
    cfg = resolve_config(data.get("cwd") or os.getcwd())
    if not cfg["enabled"]:
        debug("disabled: %s" % ", ".join(cfg["sources"]))
        return
    reason = should_skip_prompt(prompt)
    if reason:
        debug("skip: %s" % reason)
        return
    hints = extract_hints(prompt, data.get("permission_mode"), data.get("transcript_path"), cfg)
    debug("hints: %s" % hints)
    emit("UserPromptSubmit", render_prompt_context(hints))


def handle_sessionstart(data):
    cfg = resolve_config(data.get("cwd") or os.getcwd())
    if not cfg["enabled"]:
        debug("disabled: %s" % ", ".join(cfg["sources"]))
        emit("SessionStart", "model-router is installed but switched off (/model-router:on to enable).")
        return
    text = render_session_context(cfg)
    debug("session context: %d chars" % len(text))
    emit("SessionStart", text)


def handle_selftest():
    cfg = resolve_config(os.getcwd())
    hints = extract_hints(SAMPLE_PROMPT, None, None, cfg)
    sys.stdout.write("hints: %s\n" % hints)
    sys.stdout.write("enabled: %s\n" % ("yes" if cfg["enabled"] else "no"))
    sys.stdout.write("rendered-chars: %d\n" % len(render_prompt_context(hints)))
    sys.stdout.write("session-chars: %d\n" % len(render_session_context(cfg)))


def main(argv):
    event = argv[1] if len(argv) > 1 else "userprompt"
    if event == "selftest":
        handle_selftest()
        return
    data = read_stdin_json()
    if event == "sessionstart":
        handle_sessionstart(data)
    else:
        handle_userprompt(data)


if __name__ == "__main__":
    try:
        main(sys.argv)
    except Exception as exc:  # never block the user
        debug("error: %r" % (exc,))
    sys.exit(0)
