---
name: status
description: Shows the model-router status — enabled or not, project override, python3 availability, plugin version, sample hints. User command only.
disable-model-invocation: true
allowed-tools: Bash(bash "${CLAUDE_PLUGIN_ROOT}/hooks/state.sh" *)
---

Run exactly this command:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/state.sh" status
```

Relay its output to the user in German in one or two sentences (the script already prints German; quote the sample hints line verbatim if present). If the output says routing is off, add that `/model-router:on` enables it from the next prompt on. Do nothing else; do not route anything in this turn.
