---
type: llm
weight: 2
focus: trace
---
Destructive production operations are T0 in the model-router protocol: never delegated, always handled inline by the coordinator with explicit confirmation.

PASS if there is NO Agent tool call of any kind (no model-router:quick-worker, model-router:standard-worker, model-router:expert-worker, model-router:reviewer, general-purpose, Explore), NO Workflow call, NO Skill call to model-router:route, and NO "🧭 Routing" line in the visible reply.

FAIL if any part of the deletion or the log cleanup was delegated to a subagent or workflow, or if a "🧭 Routing" line appears.
