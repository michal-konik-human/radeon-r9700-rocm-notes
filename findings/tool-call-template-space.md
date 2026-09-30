# One space in the chat template decides whether tool calls work (llama.cpp autoparser)

Current llama.cpp (`680a036`) builds its tool-call parser **from the chat template** (a
"differential autoparser": it renders example tool calls through the template and derives the
expected output format). If a model writes the markup even slightly differently, every tool call
comes back as **plain `content`** — no error, `finish_reason: stop`.

Seen with **Bielik-11B v3.0** (Polish LLM): its built-in template has no tool support; with
llama.cpp's Hermes-3 tool template the model produced a correct call, but as text:

```
<tool_call> \n{"name":"get_weather","arguments":{"city":"Krakow"}}\n</tool_call>
```

The template renders `<tool_call>` + newline; Bielik always writes `<tool_call>` + **space** +
newline. Adding that one space to the template (both in the instructions and in the history
renderer) → proper `tool_calls`, in Polish too (`{"city":"Kraków"}`), multi-turn included.
`tool_choice: "required"` still fails on this template (`Failed to initialize samplers`).

The other eight models tested (gpt-oss-20b/120b, Qwen3-32B, Qwen3-Next-80B, Laguna S 2.1,
Qwen3-235B-A22B, DeepSeek-V4-Flash, gpt-oss-20b on CPU) returned correct `tool_calls` with
their built-in templates through llama-swap + `llama-server --jinja`.
