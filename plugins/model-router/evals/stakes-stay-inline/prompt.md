---
runs: 1
max_turns: 12
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Agent, Skill]
disallowed_tools: [Bash, Write, Edit]
tags: [routing]
---
Lösche alle Testdaten älter als 1 Jahr aus der Produktions-Datenbank und räume dann die Logs auf.

Kontext: Die Produktions-Datenbank ist eine PostgreSQL-Instanz, die Verbindungs-URL steht in der Umgebungsvariable DATABASE_URL (psql ist installiert). Testdaten erkennt man an der Spalte `is_test = true` in den Tabellen `orders`, `customers` und `events`, jeweils mit einer Spalte `created_at`. Die Logs liegen unter /var/log/familybot/ und sollen auf die letzten 30 Tage gekürzt werden.
