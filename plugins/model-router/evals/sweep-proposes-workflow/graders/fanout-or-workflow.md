---
type: llm
weight: 3
focus: trace
---
Eight same-shape independent items, each needing real work (three bullets, a full English translation and a next step per note — well over 300 tokens of mechanical output per item) is a sweep. Per the model-router protocol, ≥ 5 such items go to a plugin Workflow (model-router:route-sweep) or, if the Workflow tool is unavailable, to a fan-out of model-router:quick-worker (haiku) agents.

PASS if EITHER of the following happened:
(a) A Workflow tool call was made with name model-router:route-sweep (model-router:route-fanout also acceptable) whose args contain the notes as items and a brief template for the per-note block; OR
(b) At least one Agent call with `subagent_type` model-router:quick-worker (bare form quick-worker also accepted) was made whose prompt asks for the per-note block (bullets, English translation, next step) for some or all of the 8 notes (one agent per note, or a few agents each handling a batch of notes, are both fine), with parallel calls issued in one assistant turn where more than one agent was used.

Additionally the assistant should verify the cheap output in some form: a visible spot-check of a sample (e.g. "3 von 8 geprüft"), its own check of the blocks against the notes, or a model-router:reviewer call. Missing verification alone does not fail this grader, but note it.

FAIL if the assistant produced all 8 blocks itself inline with no Workflow and no Agent call, if the only delegation went to model-router:standard-worker or model-router:expert-worker (sonnet/opus) rather than quick-worker, if a non-model-router agent (general-purpose, Explore) was used for the notes, or if the fan-out was tried but the assistant then ignored the results and wrote its own blocks instead.
