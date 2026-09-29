# Large models hang on load — it's ROCm, not VRAM

**Symptom.** Loading a large (~50+ GiB) GGUF across multiple GPUs looks like it's working —
VRAM fills correctly, split evenly across cards — then goes quiet forever:

```bash
$ HIP_VISIBLE_DEVICES=0,1,2 ./llama-cli -m gpt-oss-120b-MXFP4.gguf -ngl 999 \
    --split-mode layer --tensor-split 1,1,1 -p "hi" -n 1
```

- VRAM: 22.7 / 20.1 / 19.0 GiB across the three cards — correct, matches the model size
- `gfx_activity`: 3-5% on every card, unmoving, for 5+ minutes
- One CPU thread pinned near 80-95%
- No OOM, no swap storm (`free -h` stays flat), no dmesg errors, no AER/ECC events
- Identical behaviour whether split across 2 or 3 cards — **the card count is not the
  variable**

Four earlier attempts on 2 cards concluded "this model needs a third card" (58.9 GiB of
weights in 63.7 GiB of 2-card VRAM leaves only ~4.7 GiB for KV-cache). That conclusion was
**wrong** — adding a third card reproduced the exact same hang.

## Root cause

This is a known ROCm bug, not a llama.cpp bug and not a capacity problem:
[ggml-org/llama.cpp#19482](https://github.com/ggml-org/llama.cpp/issues/19482) — "large
model loading on ROCm hangs." The HSA runtime (`libhsa-runtime64.so`) gets pathologically
slow (effectively hung) registering very large `mmap`'d host buffers as userptr memory for
the GPU. Confirmed across unrelated hardware in that thread: Strix Halo APUs, RX 7900
XT/XTX, RX 6900 XT, and — the closest match to this rig — **another 4×R9700 report**,
all with the same backtrace through `libhsa-runtime64.so` / `libamdhip64.so`.

**Rebuilding llama.cpp does not fix it.** We rebuilt from commit `987498f` (2026-09-15) to
`680a036` (2026-09-28, 264 commits later, including several HIP/MoE-specific fixes) and the
hang reproduced identically on the new build.

## Fix

Skip the mmap path entirely:

```bash
--load-mode dio
```

This llama.cpp build uses `--load-mode <auto|none|mmap|mlock|mmap+mlock|dio>` (default
`auto`, which picks `mmap`). Older llama.cpp releases use `--no-mmap` instead — check
`llama-cli --help | grep -i mmap` on your build before assuming the flag name.

**Result with the fix:** the same `gpt-oss-120b` load that hung for 5+ minutes now
completes in **~20 seconds** and generates real tokens (89-96 tok/s on 3×R9700, `-sm layer
-ts 1,1,1`).

## What looks wrong and isn't — and what's a separate bug

- **This is not a sign the new card is unhealthy.** All three cards' own health (PCIe link,
  AER, ECC) was independently verified clean — see
  [card-verification.md](../hardware/card-verification.md). The hang is a software/driver
  issue, orthogonal to hardware condition.
- **`llama-bench --load-mode dio` fails immediately, `llama-cli` with the identical flags
  works.** `llama-bench` reports `error: failed to load model` in under a second (not a
  hang) as soon as more than one GPU is visible with this same model + `dio`. Single-GPU
  `--load-mode dio` in `llama-bench` works fine (confirmed on `gpt-oss-20b`). This looks
  like a second, distinct bug specific to `llama-bench`'s own load path — not yet reported
  upstream. Use `llama-cli` (or `llama-server`, untested but expected to match `llama-cli`)
  for multi-GPU + `dio` + large-model measurements until this is isolated further.

## If you hit this on a different model or card count

Per the upstream thread, the practical threshold is roughly "large enough to matter" (tens
of GiB), not a specific number, and it has reproduced on both discrete multi-GPU rigs and
unified-memory APUs. Add `--load-mode dio` (or `--no-mmap` on older builds) as the first
thing you try before concluding a model needs more/different hardware.
