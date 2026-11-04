---
type: llm
weight: 3
focus: trace
---
Check which worker agent each of the three deliverables was routed to. Agent calls carry a `subagent_type`; accept both the namespaced form (model-router:quick-worker) and the bare form (quick-worker). Mapping: quick-worker = haiku = easy; standard-worker = sonnet = medium; expert-worker = opus = hard.

PASS if ALL of the following hold:
1. The literal translation of the 20 German sentences was delegated to model-router:quick-worker (haiku). The Agent prompt for that call must be about the translation. This step is bulky mechanical output (about 20 lines), so the protocol requires delegation to the cheapest tier; doing it inline is a failure.
2. The friendly email to the landlord (Herr Brandt, broken heater) was EITHER delegated to model-router:standard-worker (sonnet) OR written inline by the assistant itself. It must NOT go to quick-worker.
3. The architecture judgement (SQLite vs JSON files for a small Telegram bot) was EITHER answered inline by the assistant itself OR delegated to model-router:expert-worker (opus). Delegating it to model-router:standard-worker is also tolerable; delegating it to quick-worker is not.
4. At least one Agent call was made, and when more than one delegation happened the independent calls were issued together (in one assistant turn) rather than strictly one after another.

A reviewer call (model-router:reviewer, any model) is allowed and does not affect the result.

FAIL if the translation was done inline or went to standard-worker or expert-worker, if the email went to quick-worker, if the architecture judgement went to quick-worker, if any step was delegated to a non-model-router agent (e.g. general-purpose, Explore), or if no Agent call was made at all.
