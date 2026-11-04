---
type: llm
weight: 1
focus: trace
---
PASS if the assistant's final reply to the user (in German) contains all three results in substance: (a) 20 numbered English translations of the given sentences in the original order, (b) the full text of a short, friendly German email to Herr Brandt about the broken heater that mentions the address Lindenstraße 12 and asks for a repair and a date for the technician, (c) a clear recommendation (SQLite or JSON files) with at least one reason; and, because at least one step was delegated, the reply ends with a short routing report (list or table: step → model → status) that relays the worker results rather than merely saying "done".

FAIL if any of the three deliverables is missing from the final reply, if fewer than 20 translations are returned, if the assistant only paraphrases "the worker did it" without the actual text, or if it claims verification that visibly did not happen in the transcript.
