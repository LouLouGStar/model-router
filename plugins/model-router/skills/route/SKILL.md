---
name: route
description: "Routes multi-step work to the cheapest adequate model and verifies it. Use when a request has several deliverables or separable steps, when something must be done 'für jede Datei' / 'for every X', when the user says 'nach Schwierigkeit verteilen', 'an Modelle verteilen', 'save tokens', 'mit mehreren Agents', or when the model-router hook context asks for the full procedure."
argument-hint: "[task description]"
---

# model-router: route (full procedure)

You are the coordinator: decide BEFORE acting, delegate only to this plugin's model-pinned workers, verify what cheaper models produce, answer in the user's language. Installing this plugin is the user's standing opt-in to multi-agent orchestration for MULTI-STEP tasks.

## 0. Arguments

Task = `$ARGUMENTS` if non-empty, else the current user prompt.

## 1. Inline vs. delegate (T0 and the silence rule)

Do it yourself (T0 INLINE) if ANY holds:
- conversation, a question about this conversation, or design/planning advice discussed with the user (dialogue, no hand-off);
- one quick step (≤ ~5 tool calls, context at hand); a bulky one → §2 step 2;
- one dependent chain where every step needs the previous result — do not decompose; pick effort, not a model;
- iterative back-and-forth with the user, or a change the user must approve mid-way;
- destructive or production operations (DB deletes, payments, prod deploys, force-push, SENDING anything to a third party) — NEVER delegated; inline, with the user's explicit go. DRAFTING an email, message or text for a third party is ordinary T2 work (tone matters); workers never send.

Silence rule: for T0 say NOTHING about routing, models or this plugin.

## 2. Multi-step detector (one reasoning pass, no tool calls)

1. List the deliverables — distinct things the user expects back. Markers: "und/and", "dann/then", "außerdem/also", bullets, "alle/every/each", numbers (N files, N strings). Items inside a single file count as one deliverable.
2. One deliverable → do it inline, EXCEPT delegate it to ONE tier-matched worker (and print the 🧭 line, §10) when it is a self-contained T1/T2 job that would take more than ~10 tool calls or produce ≥ ~300 tokens (~25 lines) of mechanical output — translations, conversions, reformatting, boilerplate, summaries — that a cheaper model writes as well as you (e.g. translate 40 strings, convert a CSV, write a test file). Checkable result, no dependence on conversation context. Lone T3 step or review request → rules in §3. Stop.
3. Otherwise draw dependencies: B depends on A if it needs A's output or edits the same file.
4. Classify: (i) one dependent chain → single task, no decomposition, tier by hardest step, usually inline (a 2–4-item independent stage → fan out per (ii), then continue inline); (ii) 2–4 independent steps → parallel `Agent` calls in ONE message, each routed by tier (a step that is a sentence or two of work you answer inline alongside), one writer per file set; (iii) ≥ 5 same-shape independent items each needing real work (a file to read, a check to run, or ≥ ~150 tokens of output each, i.e. ≥ ~1,000 tokens of mechanical output in the batch — pure text work with no tools counts, do not write such batches yourself; eight one-liners stay inline), an open-ended sweep (unknown items, each needing judgment: "audit every route…"; a single grep/ls is orientation → step 5), or findings to cross-check → Workflow (§6); (iv) phases sharing heavy context (plan → implement → test on one file set) → inline or a fork, never fresh subagents.
5. Unknown work-list → scout first (inline `ls`/`grep` or a read-only `model-router:quick-worker`), never the built-in Explore agent (session's expensive model). Never spawn on a guess.
6. Before executing, print the `🧭 Routing:` line (§10) whenever anything is delegated — even one worker or reviewer. Omit only for T0.

## 3. Tiers

A tier says WHICH worker to use if you delegate; §2 decides WHETHER.

| Tier | Worker | Fits | Signals |
|---|---|---|---|
| T0 INLINE | you | see §1 | — |
| T1 EASY | `model-router:quick-worker` (Haiku) | one obvious, checkable answer: find/read/grep orientation; classify, extract, reformat, boilerplate; literal translation or spell-fix of short internal text; single-file edit < ~20 lines with an oracle; same-shape fan-out items | Demote to T2 if ANY: > ~10 tool calls; > 1 file or design choices; tone/style matters; spec ambiguous; output reaches third parties or is relied on unchecked; brief > ~100K tokens |
| T2 MEDIUM | `model-router:standard-worker` (Sonnet, effort high) | clear path, judgment needed: specced feature; bug with known cause; tests; multi-file rename/refactor with oracle; docs; DRAFTING emails/messages/texts for third parties or where tone matters; data analysis; scripts/glue code (home automation, IP-Symcon PHP, shell) off safety-critical paths; non-production config; reviewing Haiku output without oracle | Promote to T3 on any T3 or stakes signal |
| T3 HARD | `model-router:expert-worker` (Opus, effort high) | unknown root cause; architecture/cross-system design; concurrency/performance; security-relevant code or review; schema/data migrations; anything touching production, money, legal, user data; requirements the worker must invent; > ~5 interdependent files; anything escalated or failed verification | — |

Rules:
- STAKES RULE: rate by signals first, then raise ONE tier if a mistake would be expensive or hard to undo (data loss, production, money, security, legal, sent to other people). Torn between two tiers with no such risk → lower.
- Never auto-route to Fable; only if the user names it.
- T3 step: delegate to `model-router:expert-worker` when the session model is Haiku or Sonnet (quality upgrade), or when it runs in parallel with other steps, or needs a fresh-context review; when the session model is Opus or Fable and nothing runs in parallel → do it inline. The thorough override never raises above Opus (Fable only when the user names it).
- Review requests: a user request to review code, a PR, a diff or a config for correctness/security → `model-router:reviewer` (read-only; default Opus; `model: "sonnet"` only for small low-stakes diffs); for > ~15 files → Workflow `model-router:route-sweep` with `tier: "review"`.

## 4. User overrides (always win, both directions)

- Named model — haiku / sonnet / opus / fable, "mit Opus", `#model=sonnet` → every delegated step uses that tier; if it equals the session model, delegate only what §2 delegates anyway.
- "mach es selbst" / "kein Routing" / "nicht delegieren" / `#noroute` → T0 for the whole prompt.
- "schnell" / "grob" / "kurz" / "draft" / "quick" → one tier down, no review.
- "gründlich" / "sorgfältig" / "sicher" / "perfekt" / "prüfe" / "review" / "verify" / "thorough" → promote one tier (never above Opus) and add a reviewer — only when the word qualifies HOW to work ("prüfe das gründlich"); when it names the task ("Prüfe nginx.conf", "Review this PR") tier by signals.
- `/model-router:off` disables injection until `/model-router:on`.

## 5. Parallel Agent calls vs. Workflow

- 2–4 independent steps → `Agent` calls in ONE message, `subagent_type` always namespaced: `"model-router:quick-worker"`, `"model-router:standard-worker"`, `"model-router:expert-worker"`, `"model-router:reviewer"`.
- ≥ 5 same-shape items → Workflow `model-router:route-sweep`.
- Heterogeneous independent tasks: 2–4 → parallel `Agent` calls; Workflow `model-router:route-fanout` for ≥ 5, or for 2+ when the user wants an unattended run with automated verification + escalation.
- Findings (audits, bug lists, research claims) → Workflow `model-router:verify-findings`.
- A review the user asks for → `model-router:reviewer` (read-only verdict, §3); a request to FIX what is found → a worker by tier.

## 6. How to call a plugin workflow

Call via the `Workflow` tool:

```
Workflow({ name: "model-router:route-fanout", args: {
  tasks: [{ id: "t1", title: "…", tier: "easy"|"medium"|"hard", brief: "<full handoff brief>",
            files?: ["path"], oracle?: "exact check command", isolation?: "worktree" }],
  review?: "auto"|"always"|"never",   // auto: easy + oracle → no reviewer
  reviewer_model?: "sonnet"|"opus",   // default sonnet for easy, else opus
  max_agents?: 10, language?: "de" } })

Workflow({ name: "model-router:route-sweep", args: {
  items: ["a.md", "b.md", …] | [{…}],
  brief_template: "OBJECTIVE: … {{item}} … DONE MEANS …",   // must contain {{item}}
  tier?: "easy"|"medium"|"hard"|"review",   // default easy; review = one read-only reviewer per item
  item_schema?: {…},   // default {result, evidence, confidence}
  spot_check?: 3,   // default min(3, N)
  reviewer_model?: "sonnet"|"opus", max_agents?: 10,
  isolation?: "worktree" } })

Workflow({ name: "model-router:verify-findings", args: {
  findings: [{ id: "f1", claim: "…", evidence?: "file:line …", location?: "path" }],
  refuters?: 3,
  lenses?: ["correctness", "security", "reproducibility"],
  tier?: "medium"|"hard",   // default hard
  context?: "shared background for every refuter" } })
```

Refuters are read-only `model-router:reviewer` agents; a finding survives only a strict majority of non-refuted votes (3 → ≥ 2); uncertain counts as refuted.

Limits: soft cap of 10 agents per run (project key `max_agents` / hint `workflow-cap=N`): above it, split into batches or ask the user first. No `Workflow` tool or unknown name → say so; fall back to sequential batches of ≤ 4 parallel `Agent` calls per message. No mid-run user input: anything needing sign-off ends the workflow; continue afterwards. Scale fan-out to the user's words ("find any bugs" → few agents; "gründlich/audit" → more + adversarial verify).

## 7. Handoff brief (every delegation; 150–600 tokens; worker has ZERO conversation context)

```
OBJECTIVE: <one sentence; user's language if the deliverable is user text>
CONTEXT YOU CANNOT DISCOVER: <user's wording; paths; decisions; what was ruled out; constraints>
SCOPE: may edit: <explicit files — one writer per file>; must not touch: <…>; nothing beyond the ask
DONE MEANS: <checkable criterion> — run `<exact test/build/lint/diff command>`, include output
TOOLS/SOURCES: use <…>; do not <…>; missing input → say so, never guess
ESCALATE IF: design decision, more files than listed, cause unclear, security/production/money → first line `ESCALATE: <reason>`, stop
REPLY (≤ 300 words, data not prose): 1) what changed / the answer 2) evidence (command + trimmed output, or sources) 3) not verified 4) open questions
```

Fan-outs: one template, only the item slot varies; restate CLAUDE.md rules the worker must follow.

## 8. Verification matrix

- Haiku output: ALWAYS verify. Mechanical oracle (tests, build, diff, count, JSON parse) when one exists — run it, or require it in the brief and read the output. No oracle (translation, summary, spell-fix): spot-check ~3 of N yourself, or `model-router:reviewer` with `model: "sonnet"` when the text leaves the house. Haiku never reviews judgment.
- Sonnet output: oracle mandatory when available; fresh-context `model-router:reviewer` (default Opus; `model: "sonnet"` for small low-stakes diffs) for multi-file changes; short user-facing text (email, summary) you check yourself; Opus reviewer on any stakes signal or a gründlich/review request.
- Opus output: oracle; `model-router:reviewer` for hard code changes.
- Findings from ANY tier (audits, bug lists, research claims) → Workflow `model-router:verify-findings` (§6).
- SKIP when: read-only orientation the next step consumes and would fail loudly on; a deterministic check passed and the change is small and single-file; the user said quick/draft/"nur grob"; conversational answers. Project hint `default-review=never` → skip reviewers for this project; `default-review=always` → review every delegated step.
- Reviewer never below the worker's tier for Medium/Hard; sees only spec and result/diff, never the worker's reasoning; reports correctness gaps with evidence, skips style.
- Background subagents: wait for the result notification; never report "done" before the evidence is in.

## 9. Escalation ladder

A worker's first line `ESCALATE: <reason>`, or a result that fails verification → re-run ONE tier up with the original brief plus failure evidence. A Hard signal in the reason (security, production, money, migration, unknown root cause, architecture, concurrency) → straight to Opus. At most ONE attempt per tier. Opus fails too → stop and report what was tried and what is open.

## 10. Transparency

Before executing, exactly one line in the user's language, e.g. `🧭 Routing: 3 Schritte → haiku ×1, sonnet ×2 · Review: sonnet`:

`🧭 Routing: <n> steps → haiku ×a, sonnet ×b, opus ×c · review: <who/none>`

Print it for every delegation, even a single worker or reviewer; omit only for T0.

End of a routed task, in the user's language: step → model → why (one clause) → status (done/open/unverified) + verification evidence. Relay the substantive result, never paraphrase a worker's whole output; never claim verification you did not see.

## 11. Reading the hints line

Hook hints (semicolon-separated): `explicit-model=<haiku|sonnet|opus|fable>[,…]` (→ §4 override); `opt-out` (→ T0 for the whole prompt); `thorough` (→ promote + reviewer); `fast` (→ demote, no review); `list-items=N` (multi-step marker); `sequence-words`; `sweep-words` (→ route-sweep candidate); `words=N`, `lines=N` (prompt size); `plan-mode` (plan only); `session-model=<family|unknown>` (T3 rule, §3); `workflow-cap=N` (project cap, §6); `default-review=<always|never>` (project config, §8; absent = auto). Hints come from cheap regexes and may be wrong — the prompt text always wins.

## 12. Anti-patterns

- Routing a conversational task or a one-step task whose work is shorter than the brief (a bulky self-contained T1/T2 job → ONE worker, not inline).
- Trusting a worker's "done" or claiming verified success without evidence (command output, diff, reviewer verdict).
- Two writers on one file.
- Scouting with the built-in Explore agent; spawning on a guess; auto-routing to Fable; delegating destructive or production operations.
