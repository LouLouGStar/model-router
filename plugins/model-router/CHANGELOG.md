# Changelog

Alle nennenswerten Änderungen am Plugin `model-router`. Format nach [Keep a Changelog](https://keepachangelog.com/de/1.1.0/), Versionierung nach [SemVer](https://semver.org/lang/de/).

## [1.0.0] – 2026-11-04

Kompletter Neubau. Das Routing läuft nicht mehr nur über eine Skill, die Claude von sich aus aufrufen muss, sondern wird vor jedem Prompt als Standing Instruction eingespielt.

### Hinzugefügt
- **Hooks**: `UserPromptSubmit` injiziert vor jedem Prompt ein kompaktes Routing-Protokoll plus maschinell extrahierte Hinweise (`explicit-model`, `opt-out`, `thorough`, `fast`, `list-items`, `sequence-words`, `sweep-words`, `words`, `lines`, `plan-mode`, `session-model`, `workflow-cap`; `default-review` nur, wenn die Projekt-Config `always` oder `never` setzt); `SessionStart` (startup/resume/clear/compact) injiziert das vollständige Protokoll. Launcher in Bash 3.2, Logik in Python 3.6+, Fallback ohne Python; `MODEL_ROUTER_DEBUG=1` leitet Diagnose auf stderr durch.
- **Protokoll** (`context/protocol-session.md`, `context/protocol-prompt.md`): Tiers T0–T3, Stakes-Regel, Mehrschritt-Erkennung mit Einzeljob-Ausnahme (ein sperriger, in sich geschlossener T1/T2-Job → genau ein Worker), T3-Regel nach Session-Modell (Haiku/Sonnet-Session → `expert-worker`; Opus/Fable ohne Parallelarbeit → inline; „gründlich“ hebt nie über Opus), Review-Anfragen → `model-router:reviewer`, Entwürfe für Dritte sind T2 – Versenden wird nie delegiert, Handoff-Brief, Prüfmatrix, Eskalationsleiter, Report-Format, Soft-Deckel von 10 Agents pro Lauf, Fable nur auf ausdrücklichen Wunsch.
- **Reviewer-Agent** `model-router:reviewer` (Opus, auf Wunsch Sonnet): Fresh-Context-Prüfung mit Evidenz, endet mit `Verdict: pass | pass with notes | fail — <Grund>`.
- **Workflows**: `route-fanout` (unabhängige Schritte parallel, Prüfung, Eskalation Stufe für Stufe mit höchstens einem Versuch pro Stufe; eine übersprungene Prüfung wird als `skipped` gemeldet), `route-sweep` (viele gleichförmige Items, Stichprobe, Synthese; `tier: "review"` setzt einen lesenden Reviewer pro Item ein, z. B. für große Review-Wünsche), `verify-findings` (adversariale Prüfung von Befunden mit drei Refutern).
- **Steuerung**: `/model-router:on`, `/model-router:off`, `/model-router:status`; Projekt-Config `.claude/model-router.json` (`enabled`, `max_agents` als Soft-Deckel, `default_review` mit `auto` | `always` | `never`); Umgebungsvariablen `MODEL_ROUTER_DISABLE=1` und `MODEL_ROUTER_DEBUG=1`; Overrides in natürlicher Sprache.
- **Evals** (`evals/`, sechs Fälle für `claude plugin eval`; die LLM-Grader lesen den ganzen Trace) und **Tests** (die Testsuite in `tests/test_hook.sh` für die Hooks).
- Marketplace heißt jetzt `diegruenis` (vorher `diegruenis-local`); `LICENSE` (MIT), `CHANGELOG.md`, `.gitignore`.

### Geändert
- Agents: `effort`, `maxTurns`, `tools` (expert-worker: alle Tools) und `color` je Worker festgelegt; Beschreibungen spiegeln die Tier-Signale inklusive „nicht für“-Grenzen.
- `route`-Skill: vollständige Prozedur (Erkennung, Brief, Prüfung, Eskalation, Report, Workflow-Aufruf) statt der fünf Kurzschritte; `$ARGUMENTS` wird als Aufgabe behandelt.
- README neu geschrieben (Deutsch, mit englischem Quick start): Installation für andere, Tier-Tabelle, Kosten, FAQ, Tests.

### Bekannte Einschränkungen
- Headless (`claude -p`, Evals, Agent SDK): nur der `SessionStart`-Hook feuert, die Hints-Zeile fehlt; reine Textbatches bleiben dort je nach Modell inline.
- Ein Hook kann das Session-Modell nicht wechseln; Routing läuft ausschließlich über Subagents und Workflows.
- Die drei Routing-Evals sind Richtwerte (siehe README, „Entwicklung & Tests“).

## [0.2.0] – 2026-11-04

### Hinzugefügt
- Stakes-Regel („Stakes vor Größe“): eine Stufe höher, wenn ein Fehler teuer oder schwer rückgängig zu machen wäre.
- Eskalationsleiter: Worker melden `ESCALATE: <Grund>`; höchstens ein Versuch pro Stufe; bei harten Signalen direkt zu Opus.
- Deutsche README mit Tier-Übersicht und Nutzungshinweisen.

### Geändert
- Plugin-qualifizierte Agent-Namen (`model-router:quick-worker` usw.) als Fallback dokumentiert.
- Agent-Beschreibungen um „nicht für“-Grenzen erweitert (Produktion, Geld, Sicherheit, Nachrichten an Dritte).

## [0.1.0] – 2026-11-04

### Hinzugefügt
- Erste Version: drei Worker-Agents `quick-worker` (Haiku), `standard-worker` (Sonnet), `expert-worker` (Opus).
- Skill `route`: Anfrage aufteilen, jede Teilaufgabe als leicht/mittel/schwer bewerten, an den passenden Worker delegieren, Ergebnis prüfen und berichten.
- Lokaler Marketplace `diegruenis-local` mit `plugin.json` und `marketplace.json`.
