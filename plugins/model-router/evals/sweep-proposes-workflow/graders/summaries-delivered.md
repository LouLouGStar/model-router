---
type: llm
weight: 1
focus: trace
---
PASS if the final reply to the user contains 8 numbered blocks in the original order and each block has (a) three German bullet points faithful to its note, (b) a full English translation of the note, (c) a next step with the date or deadline from the note where one exists (1 Heizkessel F.28 / Wartungsvertrag Hollmann bis März; 2 Elternabend 4b Donnerstag 19 Uhr; 3 TÜV Golf, Werkstatt 9. Dezember 8 Uhr / Bremsleuchte vorher; 4 Hochbeete vor dem ersten Frost / Dahlien / Rasenmäher-Öl; 5 Hausrat +14 % / Sonderkündigung bis ca. 28. November; 6 Omas 80. am 17. Dezember im Lindenhof / Einladungen und Fotos offen; 7 Planer-Bot 17-Uhr-Timeout / Retry nach 2 Minuten; 8 fehlende Steuerbelege / Frist Ende Juli), and (d) one sensible question back to the note's author; and the reply ends with a short routing report (which model did the work, how it was checked).

FAIL if fewer than 8 blocks are returned, if a block lacks the English translation, the bullets or the question, if any block clearly misrepresents its note, if the order is changed, or if the assistant claims a spot-check or review that is not visible in the transcript.
