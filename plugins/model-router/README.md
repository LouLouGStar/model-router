# model-router

Claude-Code-Plugin: verteilt Mehrschritt-Aufgaben nach Schwierigkeit an Haiku, Sonnet oder Opus, prüft die Ergebnisse und eskaliert bei Fehlern. Einzelschritte bleiben inline; nur ein einzelner sperriger Job geht an genau einen Worker.

## Quick start (English)

```
claude plugin marketplace add <GITHUB-USER>/model-router      # add the "diegruenis" marketplace
claude plugin install model-router@diegruenis                 # install the plugin
# one step instead:  claude plugin install model-router --marketplace <GITHUB-USER>/model-router
# then restart Claude Code or run /reload-plugins
# Work as usual. Single-step prompts: nothing changes (only a bulky self-contained job goes to ONE worker).
# Multi-step prompts: each step is rated easy/medium/hard, delegated to a Haiku/Sonnet/Opus worker,
# verified by a fresh-context reviewer and escalated one tier on failure. You see one line:
# "🧭 Routing: 3 steps → haiku ×1, sonnet ×2 · review: sonnet".
# Steer in plain words ("use Opus", "do it yourself", "quick", "thorough") or with
# /model-router:route <task>, /model-router:on, /model-router:off, /model-router:status.
# Per project: .claude/model-router.json  {"enabled": true, "max_agents": 10, "default_review": "auto"}; kill switch: MODEL_ROUTER_DISABLE=1
```

## Was es macht

Vor jedem Prompt spielt ein Hook ein kurzes Routing-Protokoll in den Kontext deiner Session ein. Deine Session (der „Koordinator“) entscheidet damit vor dem Loslegen: Einzelschritt oder Gespräch → selbst erledigen und kein Wort über Routing; ein einzelner sperriger, in sich geschlossener Job → genau ein Worker; Mehrschritt-Aufgabe → zerlegen, jeden Schritt als leicht/mittel/schwer einstufen und an den günstigsten passenden Worker-Agent (Haiku, Sonnet, Opus) geben, unabhängige Schritte parallel laufen lassen, Ergebnisse von einem Reviewer mit frischem Kontext prüfen lassen und bei Fehlern eine Stufe höher eskalieren. Für große oder prüfintensive Arbeit startet er einen der drei Workflows des Plugins.

```
du: Prompt
 │
 ▼
UserPromptSubmit-Hook ──► Protokoll + Hints (für dich unsichtbar, für Claude sichtbar)
 │
 ▼
Koordinator (deine Session)
 ├─ Einzelschritt / Gespräch ──► macht es selbst, sagt nichts
 ├─ ein sperriger Einzeljob ──► genau ein Worker (mit „🧭 Routing“-Zeile)
 └─ Mehrschritt ──► „🧭 Routing: …“
       ├─► quick-worker (Haiku)      ─┐
       ├─► standard-worker (Sonnet)  ─┼─► reviewer (Opus, ggf. Sonnet) ─► Report
       ├─► expert-worker (Opus)      ─┘
       └─► Workflow: route-fanout · route-sweep · verify-findings
```

## Installation für andere

Das Plugin liegt in einem Marketplace namens `diegruenis` (Repo-Root = Marketplace-Root). Ersetze `<GITHUB-USER>` durch den GitHub-Account, der das Repo hostet.

**Aus GitHub, zwei Schritte:**

```
claude plugin marketplace add <GITHUB-USER>/model-router
claude plugin install model-router@diegruenis
```

**Aus GitHub, ein Schritt:**

```
claude plugin install model-router --marketplace <GITHUB-USER>/model-router
```

**In einer laufenden Session:**

```
/plugin marketplace add <GITHUB-USER>/model-router
/plugin install model-router@diegruenis
```

Danach Claude Code neu starten oder `/reload-plugins` ausführen, damit Hooks und Agents geladen werden.

**Lokale Entwicklung:** `claude plugin marketplace add /pfad/zum/repo` lädt den Marketplace in-place aus dem Verzeichnis (Änderungen gelten ab der nächsten Session). Zum Testen ohne Installation: `claude --plugin-dir /pfad/zum/repo/plugins/model-router`.

## Wie geroutet wird

| Tier | Modell / Agent | Typische Aufgaben | Nicht für |
|---|---|---|---|
| **T0 inline** | deine Session selbst | Gespräch, Rückfragen zum Verlauf, ein Schritt in ≤ ~5 Tool-Aufrufen, eine abhängige Kette (jeder Schritt braucht den vorigen), iteratives Hin und Her, Änderungen, die du zwischendurch freigeben musst, **alles Destruktive/Produktive** (DB-Löschungen, Zahlungen, Prod-Deploys, Force-Push, das Versenden von Nachrichten an Dritte) – immer inline, immer mit Rückfrage | – |
| **T1 leicht** | `model-router:quick-worker` (Haiku) | Dateien finden, lesen, grep; Klassifizieren, Extrahieren, Umformatieren, Boilerplate; wörtliche Übersetzung oder Rechtschreibung kurzer interner Texte; Einzeldatei-Edit < ~20 Zeilen mit Test/Compiler/Linter als Orakel; gleichförmige Fan-out-Items | > ~10 Tool-Aufrufe, mehrere Dateien, Designentscheidungen, Ton/Stil, unklare Spec, Text für Dritte, Ergebnisse ohne mechanische Prüfung, Briefs > ~100K Tokens |
| **T2 mittel** | `model-router:standard-worker` (Sonnet, effort high) | Feature mit Spec, Bug mit bekannter Ursache, Tests schreiben, Rename/Refactor über mehrere Dateien mit Compiler/Tests, Doku, E-Mails, Nachrichten und Übersetzungen entwerfen, bei denen der Ton zählt (auch für Dritte), Datenanalyse, Skripte und Glue-Code (Home-Automation, IP-Symcon-PHP, Shell), Config außerhalb Produktion, Review eines Haiku-Ergebnisses ohne Orakel | unbekannte Ursache, Architektur, Sicherheit, Migrationen, Produktion, Geld, Versand an Dritte |
| **T3 schwer** | `model-router:expert-worker` (Opus, effort high) | unbekannte Root Cause, Architektur und systemübergreifendes Design, Concurrency/Performance, sicherheitsrelevanter Code oder Review, Schema-/Datenmigrationen, alles rund um Produktion, Geld, Recht, Nutzerdaten, Anforderungen, die der Worker selbst erfinden müsste, Querschnittsänderung > ~5 abhängige Dateien, alles, was eine Stufe tiefer eskaliert oder durchgefallen ist | Routinearbeit, die eine günstigere Stufe prüfbar erledigt |

**Stakes-Regel:** Erst nach Signalen einstufen, dann **eine Stufe höher**, wenn ein Fehler teuer oder schwer rückgängig wäre (Datenverlust, Produktion, Geld, Sicherheit, Recht, etwas geht an andere Menschen). Nur wenn zwischen zwei Stufen kein solches Risiko steht, gilt die niedrigere. Fable wird nie automatisch gewählt, nur wenn du es nennst.

**Dritte:** Eine E-Mail, Nachricht oder einen Text für Dritte zu *entwerfen* ist T2-Arbeit (Ton zählt). *Verschickt* wird nie delegiert – das bleibt inline und braucht dein ausdrückliches Go.

**Schwere Schritte und Session-Modell:** Ein T3-Schritt geht an `model-router:expert-worker`, wenn deine Session auf Haiku oder Sonnet läuft (Qualitäts-Upgrade), wenn er parallel zu anderen Schritten läuft oder wenn er eine Prüfung mit frischem Kontext braucht. Läuft die Session auf Opus oder Fable und nichts läuft parallel → inline. Das „gründlich“-Override hebt nie über Opus hinaus (Fable nur, wenn du es nennst).

**Mehrschritt-Erkennung:** Der Koordinator listet zuerst die Deliverables, also die unterschiedlichen Dinge, die du zurückerwartest (Marker: „und“, „dann“, „außerdem“, Aufzählungen, „alle/jede“, Zahlen wie „5 Dateien“; Items innerhalb einer Datei zählen als ein Deliverable). Genau ein Deliverable → inline. Ausnahme: ein in sich geschlossener T1/T2-Job, der mehr als ~10 Tool-Aufrufe bräuchte oder ab etwa 300 Tokens (~25 Zeilen) mechanischer Ausgabe liefert – Übersetzungen, Konvertierungen, Umformatierungen, Zusammenfassungen, die ein günstigeres Modell genauso gut schreibt (40 Strings übersetzen, eine CSV konvertieren, eine Testdatei schreiben, einen zweiseitigen Text korrigieren, ein Skript nach klarer Spec), geht an genau **einen** passenden Worker – mit 🧭-Zeile. Der Job muss ein prüfbares Ergebnis haben und darf nicht vom Gesprächsverlauf abhängen. Ein einzelner schwerer Schritt folgt der T3-Regel oben, ein Review-Wunsch der Review-Regel unten. Bei mehreren Deliverables zeichnet der Koordinator Abhängigkeiten: B hängt von A ab, wenn B dessen Ergebnis braucht oder dieselbe Datei anfasst. Eine abhängige Kette wird nicht zerlegt, sondern nach dem schwersten Schritt eingestuft und meist inline erledigt (eine Stufe aus 2–4 unabhängigen Items wird trotzdem parallel vergeben, danach geht es inline weiter); unbekannte Arbeitslisten werden erst mit `ls`/`grep` oder einem Haiku-Scout erkundet, nie geraten.

**Wann parallel, wann Workflow:**
- 2–4 unabhängige Schritte → parallele `Agent`-Aufrufe in einer Nachricht, jeder nach Tier geroutet, pro Datei genau ein Schreiber.
- ≥ 5 gleichförmige Items, die jeweils echte Arbeit sind („fasse jede Notiz zusammen“, „prüfe alle Routen“ – eine Datei lesen, einen Check ausführen oder ab ~150 Tokens Ausgabe je Item, also ab etwa 1.000 Tokens mechanischer Ausgabe im Batch – reine Textarbeit ohne Tools zählt mit; acht Einzeiler bleiben inline) oder ein offener Sweep (Items unbekannt, jedes braucht Urteil; ein einzelnes `grep` ist nur Orientierung) → Workflow `route-sweep`.
- ≥ 5 heterogene unabhängige Schritte – oder schon ab 2, wenn der Lauf unbeaufsichtigt mit automatischer Prüfung und Eskalation durchlaufen soll – → Workflow `route-fanout`; einfache 2–4 Schritte bleiben parallele `Agent`-Aufrufe.
- Befunde, die stimmen müssen (Audit-Ergebnisse, Bug-Listen, Recherche-Behauptungen) → Workflow `verify-findings`.
- Du bittest um ein Review (Code, PR, Diff oder Config auf Korrektheit/Sicherheit) → `model-router:reviewer` (nur lesend; Standard Opus, `model: sonnet` nur für kleine Diffs ohne Risiko); bei > ~15 Dateien → `route-sweep` mit `tier: "review"` (ein lesender Reviewer pro Datei).
- Phasen, die schweren gemeinsamen Kontext teilen (planen → bauen → testen an denselben Dateien) → inline, nie frische Subagents.

Vor dem Ausführen bekommst du genau eine Zeile, z. B. `🧭 Routing: 3 Schritte → haiku ×1, sonnet ×2 · Review: sonnet` – bei jeder Delegation, auch wenn es nur ein Worker oder ein Reviewer ist. Design- und Planungsgespräche mit dir bleiben inline, auch auf einer Sonnet-Session: Das ist Dialog, kein Auftrag zum Abgeben. Bei einfachen Einzelschritten und im Gespräch passiert nichts Sichtbares – kein Hinweis, kein Agent; nur der eine sperrige Einzeljob bekommt die 🧭-Zeile und genau einen Worker.

## Steuern

**In natürlicher Sprache** (gilt immer, in beide Richtungen):

| Du sagst | Wirkung |
|---|---|
| „nutz Opus“, „mit Sonnet“, `#model=haiku` | jeder delegierte Schritt läuft auf diesem Modell; nennst du das Modell, auf dem die Session schon läuft, wird nur delegiert, was ohnehin delegiert würde |
| „mach es selbst“, „kein Routing“, „nicht delegieren“, `#noroute` | ganzer Prompt inline, keine Agents |
| „schnell“, „grob“, „kurz“, „Entwurf“, „quick“ | eine Stufe tiefer, keine Prüfung |
| „gründlich“, „sorgfältig“, „sicher“, „prüfe“, „review“, „thorough“ | eine Stufe höher (nie über Opus), Reviewer dazu |

**Slash-Befehle:**
- `/model-router:route <Aufgabe>` – vollständige Routing-Prozedur für genau diese Aufgabe erzwingen.
- `/model-router:on` / `/model-router:off` – Einspielen des Protokolls ein- oder ausschalten (gilt ab dem nächsten Prompt; Zustand in `~/.claude/model-router/state.json`).
- `/model-router:status` – Zustand, Projekt-Override, Python-Verfügbarkeit, Plugin-Version und Beispiel-Hints anzeigen.

**Projekt-Config** `.claude/model-router.json` (wird vom Arbeitsverzeichnis aufwärts bis unterhalb von `$HOME` gesucht – ein `~/.claude/model-router.json` zählt nicht, der Benutzerzustand liegt in `~/.claude/model-router/state.json`):

```json
{"enabled": true, "max_agents": 10, "default_review": "auto"}
```

`enabled` schaltet das Plugin pro Projekt. `max_agents` ist der Soft-Deckel pro Workflow-Lauf (Hint `workflow-cap`): darüber teilt der Koordinator in Batches oder fragt dich vorher; die Workflows selbst loggen eine Überschreitung und reihen den Rest ein. `default_review` ist `auto` (Standard: Prüfmatrix unten), `never` (keine Reviewer in diesem Projekt) oder `always` (jeder delegierte Schritt wird geprüft); der Hook meldet `default-review=always|never` nur, wenn der Wert gesetzt ist.

**Umgebungsvariablen:** `MODEL_ROUTER_DISABLE=1` schaltet alles ab, egal was Config oder Zustand sagen. `MODEL_ROUTER_DEBUG=1` schreibt Diagnose auf stderr, auch durch die Hook-Launcher hindurch (stdout bleibt immer sauberes JSON).

## Agents & Workflows

| Agent | Modell | Effort | Rolle |
|---|---|---|---|
| `model-router:quick-worker` | Haiku | medium | leichte, mechanisch prüfbare Schritte |
| `model-router:standard-worker` | Sonnet | high | mittlere Schritte mit klarem Weg und Urteil |
| `model-router:expert-worker` | Opus | high | schwere Schritte, Stakes, Eskalationen |
| `model-router:reviewer` | Opus (per `model: "sonnet"` umschaltbar) | high | Fresh-Context-Prüfung, nur lesend, bearbeitet nie – auch für Reviews, um die du selbst bittest |

| Workflow | Zweck | args (Kurzform) |
|---|---|---|
| `model-router:route-fanout` | ≥ 5 unabhängige, verschiedenartige Schritte (oder ab 2 für einen unbeaufsichtigten Lauf) auf passenden Tiers, je mit Prüfung und Eskalation Stufe für Stufe (höchstens ein Versuch pro Stufe; eine übersprungene Prüfung wird als `skipped` gemeldet, nie als bestanden) | `{tasks:[{id, title, tier, brief, files?, oracle?, isolation?}], review?, reviewer_model?, max_agents?, language?}` |
| `model-router:route-sweep` | derselbe Brief über viele gleichförmige Items, deterministische Stichprobe, eine Synthese | `{items:[…], brief_template:"… {{item}} …", tier? (easy|medium|hard|review), item_schema?, spot_check?, reviewer_model?, max_agents?, isolation?}` |
| `model-router:verify-findings` | Befunde adversarial widerlegen lassen: drei Refuter mit den Linsen correctness/security/reproducibility, überlebt nur mit ≥ 2 Nicht-Widerlegungen | `{findings:[{id, claim, evidence?, location?}], refuters?, lenses?, tier?, context?}` |

Aufruf über das `Workflow`-Tool, z. B. `Workflow({ name: "model-router:route-sweep", args: {…} })`. Soft-Deckel: 10 Agents pro Lauf (Projekt-Key `max_agents`, Hint `workflow-cap`) – darüber teilt der Koordinator in Batches oder fragt dich vorher; die Workflows loggen die Überschreitung und reihen die restlichen Items ein.

## Prüfung & Eskalation

- Der Reviewer sieht nur den Brief und das Ergebnis bzw. den Diff – nie den Plan oder die Überlegungen des Workers. Er meldet Korrektheitslücken mit Evidenz und lässt Stil weg; sein Modell liegt nie unter dem des Workers (bei mittel/schwer).
- **Haiku-Ergebnisse werden immer geprüft:** mit mechanischem Orakel (Tests, Build, Diff, Zählung, JSON-Parse), wenn eins existiert; sonst Stichprobe durch den Koordinator oder Reviewer auf Sonnet, wenn der Text das Haus verlässt. Haiku prüft nie Urteile.
- Sonnet: Orakel Pflicht, wenn vorhanden; Reviewer bei Mehrdatei-Änderungen; kurze Texte an dich (E-Mail, Zusammenfassung) liest der Koordinator selbst gegen die Aufgabe; Opus-Reviewer bei jedem Stakes-Signal oder wenn du „gründlich“/Review verlangst. Opus: Orakel plus Reviewer bei harten Code-Änderungen; Befunde über `verify-findings`.
- Übersprungen wird die Prüfung nur bei reiner Orientierung, bei kleinen Einzeldatei-Änderungen mit bereits bestandenem deterministischem Check, bei „schnell/grob“ und bei Gesprächsantworten.
- Projekt-Config `default_review`: `never` → keine Reviewer in diesem Projekt; `always` → jeder delegierte Schritt wird geprüft; `auto` (Standard) → Matrix oben. In Workflows steuert das Argument `review` dasselbe.
- **ESCALATE-Protokoll:** Jeder Worker darf als erste Zeile `ESCALATE: <Grund>` antworten und stoppen (Designentscheidung nötig, mehr Dateien als erlaubt, Ursache unklar, Sicherheit/Produktion/Geld). Dann – oder bei durchgefallener Prüfung – läuft der Schritt **eine Stufe höher** mit dem ursprünglichen Brief plus Fehler-Evidenz (inklusive der Dateien, die der vorige Versuch schon geändert hat), **höchstens ein Versuch pro Stufe**, nie derselbe Worker mit demselben Brief zweimal. Nennt der Grund ein hartes Signal (Sicherheit, Produktion, Geld, Migration, unbekannte Ursache, Architektur, Concurrency), geht es direkt zu Opus. Scheitert auch Opus, bekommst du einen Bericht, was versucht wurde und was offen ist.

## Was der Hook einspielt

| Event | Inhalt | Größe |
|---|---|---|
| `UserPromptSubmit` (jeder Prompt) | Kurzprotokoll plus eine Hints-Zeile: `explicit-model`, `opt-out`, `thorough`, `fast`, `list-items`, `sequence-words`, `sweep-words`, `words`, `lines`, `plan-mode`, `session-model`, `workflow-cap`, `default-review` (nur wenn die Projekt-Config `always`/`never` setzt) | ≤ ~900 Zeichen |
| `SessionStart` (startup, resume, clear, compact) | Vollprotokoll `context/protocol-session.md` plus Zustandszeile | < 10.000 Zeichen |

Die Hints sind billige Regex-Treffer (Deutsch und Englisch) und im Vollprotokoll sowie in der route-Skill ausdrücklich als „kann falsch sein“ markiert; das Modell entscheidet. Übersprungen werden leere Prompts, Slash-Befehle, Harness-Events (`<…>`) und Kurzantworten unter drei Wörtern. Alles läuft lokal in Bash 3.2 plus Python 3.6+ (ohne Python: Fallback ohne Hints); keine Daten verlassen den Rechner, es gibt keine Netzwerkaufrufe.

## Kosten

Auf der Anthropic-API stehen Haiku : Sonnet : Opus etwa im Verhältnis 1 : 20 : 40 (Input/Output pro MTok: $0.10/$0.50, $2/$10, $4/$20). Ein Haiku-Prompt über 100K Tokens kostet etwa das Fünffache – deshalb gehen große Briefs nach T2. Auf Bedrock und Vertex können die Aliase `haiku`/`sonnet`/`opus` auf andere Modellgenerationen zeigen; das Preisverhältnis ist dort anders.

Ein Übergabe-Brief (150–600 Tokens plus Antwort) kostet grob 0,02 $. Delegieren lohnt sich bei mehreren Schritten oder bei einem einzelnen sperrigen Job (mehr als ~10 Tool-Aufrufe oder ab etwa 300 Tokens bzw. 25 Zeilen mechanischer Ausgabe wie Übersetzungen, Konvertierungen, Zusammenfassungen; ein, zwei Sätze bleiben inline); darunter ist der Brief länger als die Aufgabe, und das Plugin lässt die Session selbst arbeiten.

## FAQ

**Warum wechselt der Hook nicht einfach das Modell der Session?** Claude Code hat dafür keinen Mechanismus – ein Hook kann Kontext einspielen, aber nicht das Modell setzen. Das Session-Modell änderst nur du per `/model`. Routing läuft deshalb komplett über modell-gepinnte Subagents und Workflow-Stufen.

**Das `Workflow`-Tool fehlt in meiner Session.** Mit Pro in `/config` den Punkt „Dynamic workflows“ einschalten. Ohne das Tool fällt das Plugin auf Batches von bis zu vier parallelen `Agent`-Aufrufen pro Nachricht zurück; Ergebnis gleich, nur ohne Workflow-Protokoll.

**Warum nur bei Mehrschritt-Aufgaben?** Weil die Übergabe (Brief schreiben, Kontext erklären, Ergebnis prüfen) bei einem kurzen Einzelschritt mehr kostet als die Arbeit selbst. Routing spart nur, wenn mehrere Schritte oder viel laute Ausgabe aus der teuren Session herausgehalten werden – deshalb geht auch ein einzelner sperriger Job an einen Worker.

**Funktioniert es ohne Python?** Ja. Die Launcher sind reines Bash 3.2; ohne `python3` wird das Protokoll trotzdem eingespielt, nur die Hints-Zeile lautet `hints: unavailable (no python)`. Ohne Python gelten `MODEL_ROUTER_DISABLE`, `state.json` und die Projekt-Config `.claude/model-router.json` (`enabled`, `max_agents` für die Zustandszeile) weiterhin als Schalter; einziger weiterer Unterschied: Kurzantworten unter drei Wörtern werden nicht übersprungen.

**Was passiert bei `/compact`?** Der `SessionStart`-Hook feuert auch bei `compact` (und `resume`, `clear`) und spielt das Vollprotokoll erneut ein. Das Routing-Wissen überlebt also die Komprimierung.

**Headless (`claude -p`, Evals, Agent SDK)?** Dort feuert nur der `SessionStart`-Hook; der `UserPromptSubmit`-Hook läuft für den Startprompt nicht. Das Vollprotokoll ist also da, die Hints-Zeile fehlt.

**Verlässt irgendetwas den Rechner?** Nein. Hooks lesen nur stdin, Transcript-Datei und Config; die Modellaufrufe laufen wie immer über Claude Code.

## Entwicklung & Tests

```
bash plugins/model-router/tests/test_hook.sh                   # Hook-Tests (Bash 3.2, exit 1 bei Fehler)
claude plugin validate plugins/model-router --strict           # Plugin-Manifest, Agents, Hooks, Skills
claude plugin validate . --strict                              # Marketplace
claude plugin eval plugins/model-router --runs 1 --no-publish  # sechs Eval-Fälle in evals/
```

Alle Befehle vom Repo-Root aus; `--plugin-dir` siehe Installation.

Hinweis zu den Evals: Die drei Negativfälle (Einzelschritt, Opt-out, Produktions-DB) sind die harten Checks und bestehen zuverlässig. Die drei Routing-Fälle (Mehrschritt, Modell-Override, Sweep) laufen headless, also ohne den `UserPromptSubmit`-Hook und nur mit dem `SessionStart`-Protokoll; dort setzt Opus die Routing-Entscheidung zwar an (die `🧭`-Zeile stimmt), erledigt reine Textarbeit aber teils inline. Sie sind deshalb Richtwerte, keine Pflichtschwelle, und brauchen einen wachen Rechner (jeder Fall ist eine echte Session mit Timeout).

## Changelog

Siehe [CHANGELOG.md](CHANGELOG.md). Aktuell: 1.0.0 (2026-11-04) – kompletter Neubau mit Hooks, Protokoll, Reviewer, Workflows, Evals und Tests.

## Lizenz

MIT – siehe [LICENSE](../../LICENSE).
