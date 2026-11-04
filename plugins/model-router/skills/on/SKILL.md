---
name: on
description: Switches model-router on — the routing protocol is injected again before every prompt. User command only.
disable-model-invocation: true
allowed-tools: Bash(bash "${CLAUDE_PLUGIN_ROOT}/hooks/state.sh" *)
---

Run exactly this command:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/state.sh" on
```

Relay its output to the user in German in one or two sentences. Mention that the change applies from the next prompt on (the current prompt was already processed without the protocol). Do nothing else; do not route anything in this turn.
