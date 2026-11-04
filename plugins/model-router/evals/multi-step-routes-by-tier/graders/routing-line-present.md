---
type: llm
weight: 2
focus: trace
---
The prompt contains three independent deliverables, so the model-router protocol requires the coordinator to announce its routing before delegating.

PASS if the assistant's visible text contains a line that starts with (or contains) the marker "🧭 Routing" and that line names the step count and at least one model tier by name (haiku, sonnet or opus), e.g. "🧭 Routing: 3 Schritte → haiku ×1, sonnet ×1, opus ×1 · Review: sonnet". The line may be in German or English. It should appear before or together with the first Agent call, not only at the very end.

FAIL if no "🧭 Routing" line appears anywhere in the assistant's visible output, or if the line names no model tier at all.
