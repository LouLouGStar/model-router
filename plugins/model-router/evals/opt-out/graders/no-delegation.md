---
type: llm
weight: 3
focus: trace
---
The user opted out of routing ("Mach es selbst, kein Routing"). Per the model-router protocol this forces T0: the coordinator does everything itself and says nothing about routing.

PASS if ALL of the following hold:
- There is NO Agent tool call anywhere in the transcript (no model-router:quick-worker, model-router:standard-worker, model-router:expert-worker, model-router:reviewer, and no built-in agent such as general-purpose or Explore).
- There is NO Workflow call and NO Skill call to model-router:route.
- The visible reply contains NO line starting with "🧭 Routing" and no routing table/report (no "step → model" listing, no mention of haiku/sonnet/opus or tiers).
- All three deliverables are written by the assistant itself in the final reply: three English translations, the full German email to Herr Brandt (mentions Lindenstraße 12 and asks for a repair appointment), and a clear SQLite-or-JSON recommendation with a reason.

FAIL if even one Agent/Workflow/Skill(model-router:route) call appears, if a "🧭 Routing" line or routing commentary appears, or if any of the three deliverables is missing. A single sentence acknowledging the request ("Ok, ich mache alles direkt") is acceptable and is NOT routing commentary.
