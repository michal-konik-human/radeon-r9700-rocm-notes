# `llama-bench -ts 1,1,1,1` puts the whole model on GPU 0

**Symptom:** a model larger than one card fails instantly in `llama-bench` on several GPUs
with a bare `error: failed to load model` — while `llama-cli` / `llama-server` with the
"same" flags work. Easy to misread as a multi-GPU bug (we did, for two days, and blamed
`--load-mode dio`).

**Cause:** different syntax.

| Tool | Even 4-way split |
|---|---|
| `llama-server`, `llama-cli` | `--tensor-split 1,1,1,1` |
| **`llama-bench`** | **`-ts 1/1/1/1`** |

In `llama-bench` a **comma means "sweep"**: run the test once per value. `-ts 1,1,1,1` is four
tests with split `1` — all layers on GPU 0 — which cannot load a 96 GiB model on a 32 GiB card.

**Verified 30 Sep 2026:** Qwen3-235B-A22B UD-Q3_K_XL (96.6 GiB), 4× R9700, `--load-mode dio`:
`-ts 1,1,1,1` → instant `failed to load model`; `-ts 1/1/1/1` → loads in ~30 s, 218 tok/s pp64.

**Knock-on:** measurements taken with the `llama-cli` workaround understated prompt processing
heavily (a 3-card Qwen3-235B Q2 run logged ~42 tok/s; the properly measured 4-card Q3 run does
619 tok/s pp512). `llm-bench-harness` now converts a comma `-ts` to slashes and rejects other
sweeps before running anything.
