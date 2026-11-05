# DieGrünis – Claude-Code-Plugins

Dieses Repository ist ein Claude-Code-Marketplace (`diegruenis`) mit derzeit einem Plugin:

| Plugin | Zweck |
|---|---|
| [`model-router`](plugins/model-router/README.md) | Verteilt Mehrschritt-Aufgaben nach Schwierigkeit an Haiku, Sonnet oder Opus, prüft die Ergebnisse und eskaliert bei Fehlern. Einzelschritte bleiben beim Hauptmodell; nur ein einzelner sperriger, in sich geschlossener Job geht an genau einen Worker. |

## Installation

```bash
claude plugin marketplace add LouLouGStar/model-router
claude plugin install model-router@diegruenis
```

Zum lokalen Entwickeln: `claude plugin marketplace add /pfad/zum/repo` – das Plugin wird dann direkt aus diesem Ordner geladen.

Die vollständige Dokumentation (Tiers, Steuerung, Agents, Workflows, Kosten, FAQ, Tests) steht in [plugins/model-router/README.md](plugins/model-router/README.md), die Versionshistorie in [plugins/model-router/CHANGELOG.md](plugins/model-router/CHANGELOG.md).

Lizenz: [MIT](LICENSE), © 2026 DieGrünis.
