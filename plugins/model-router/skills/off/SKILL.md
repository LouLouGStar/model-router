---
name: off
description: Switches model-router off — no routing protocol is injected until /model-router:on. User command only.
disable-model-invocation: true
allowed-tools: Bash(bash "${CLAUDE_PLUGIN_ROOT}/hooks/state.sh" *)
---

Run exactly this command:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/state.sh" off
```

Relay its output to the user in German in one or two sentences. Mention that the change applies from the next prompt on and that `/model-router:on` re-enables routing. Do nothing else; do not route anything in this turn.
