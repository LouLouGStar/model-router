---
type: llm
weight: 3
focus: trace
---
The user explicitly named a model ("Nutz bitte für alles Haiku"). Per the model-router protocol a named model is an override that wins: every delegated step must run on the Haiku tier, i.e. the Agent `subagent_type` must be model-router:quick-worker (bare form quick-worker also accepted), or the call must explicitly set `model: "haiku"`. The session itself cannot become Haiku, so honouring the override means delegating the work.

PASS if ALL of the following hold:
- At least one Agent call performs one of the three tasks (translation, landlord email, SQLite-vs-JSON judgement), and every such work call uses model-router:quick-worker / haiku.
- No work step is delegated to model-router:standard-worker, model-router:expert-worker, or with an explicit `model: "sonnet"` / `model: "opus"`.
- If a "🧭 Routing" line is shown, it names only haiku for the work steps (e.g. "🧭 Routing: 3 Schritte → haiku ×3"); a line that lists sonnet or opus for a work step is a failure.
- All three deliverables appear in the final reply.

A model-router:reviewer call (any model) is allowed and does not count as a work step. Answering the architecture judgement inline is acceptable as long as the bulky translation went to quick-worker.

FAIL if no Agent call was made at all, if any delegated work step ran on standard-worker/sonnet or expert-worker/opus, if the assistant argues with or ignores the override (e.g. "Haiku reicht dafür nicht"), or if a deliverable is missing.
