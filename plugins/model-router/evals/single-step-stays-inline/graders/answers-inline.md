---
type: llm
weight: 3
focus: trace
---
This is a single conversational question (T0). The model-router protocol requires the assistant to answer it itself and say nothing about routing.

PASS if ALL of the following hold:
- The assistant answers both parts directly in its own reply: a year has 52 weeks (52 weeks + 1 day, or 52 weeks + 2 days in a leap year, is fine), and from 4 November 2026 it is about 51 days to 25 December 2026 (50 days to 24 December / Heiligabend is also acceptable; any value from 50 to 52 with a stated reference day is fine).
- There is NO Agent tool call at all (no subagent of any kind, including model-router:quick-worker, model-router:standard-worker, model-router:expert-worker, model-router:reviewer or the built-in agents).
- There is NO Skill call to model-router:route and no Workflow call.
- The visible reply contains NO line starting with "🧭 Routing" and does not talk about routing, delegating, tiers, Haiku/Sonnet/Opus or model choice at all.

FAIL if any Agent, Skill(model-router:route) or Workflow call appears, if a "🧭 Routing" line or any routing commentary appears, or if either part of the question is unanswered or clearly wrong (e.g. "31 days" or "48 weeks").
