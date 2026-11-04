---
type: llm
weight: 2
focus: trace
---
PASS if the assistant's visible text contains a line with the marker "🧭 Routing" that explicitly names haiku as the model for the note blocks (e.g. "🧭 Routing: 8 Schritte → haiku ×8 · Review: Stichprobe" or "🧭 Routing: 1 Sweep (8 Notizen) → haiku · Review: sonnet"). German or English wording is fine; the marker and the word "haiku" must both be present in that line.

FAIL if no "🧭 Routing" line appears, or if the line names only sonnet/opus and not haiku.
