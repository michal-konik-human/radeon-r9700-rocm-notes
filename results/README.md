# Benchmark results — Radeon AI PRO R9700, one card

All numbers measured with [llm-bench-harness](https://github.com/<you>/llm-bench-harness),
which records the conditions alongside every result. **Three independent OS processes per
model**, not `llama-bench -r 3` — [why](../findings/bimodal-throughput.md).

Conditions common to everything below unless stated otherwise:

| | |
|---|---|
| GPU | Radeon AI PRO R9700, `gfx1201`, 64 CU, 32 GB GDDR6 (ECC active) |
| Link | x16 Gen5 (`LnkSta: Speed 32GT/s, Width x16`), read under load |
| Power cap | **300 W (stock)** |
| CPU / RAM | Ryzen 7 9700X · 64 GB DDR5-6000 |
| Software | Ubuntu 24.04.5, kernel 7.0, ROCm 7.2.4, `llama.cpp 987498f` |
| Build flags | `GGML_HIP=ON`, `GGML_VULKAN=OFF`, `GPU_TARGETS=gfx1201`, `Release` |
| ECC / AER | unchanged before and after every run |

---

## Throughput — short test (`-p 512 -n 128`)

| Model | Weights in VRAM | Params | prefill `pp512` | decode `tg128` | Spread |
|---|---|---|---|---|---|
| **gpt-oss-20b** MXFP4 (MoE) | 11.27 GiB | 20.91 B | **6050** tok/s | **149.9** tok/s | 0.2 % / 0.1 % |
| **Qwen3-32B** Q4_K_M (dense) | 18.40 GiB | 32.76 B | **1030** tok/s | **27.98** tok/s | 0.0 % / 0.1 % |

**MoE decodes 5.4× faster and prefills 5.9× faster.** The reason is architectural, not
quality: decode is memory-bandwidth bound, and an MoE model reads only a fraction of its
weights per token. A dense 32 B model must move all 18.4 GiB through the memory controller
for **every** token.

Per-run values (gpt-oss-20b `tg128`): 149.88 / 149.96 / 149.95.
Per-run values (Qwen3-32B `tg128`): 27.97 / 27.99 / 27.97.

**Spread stayed under 0.25 % across independent processes, so the documented bimodality
did not appear** in this configuration. The methodology stays regardless — see the
findings note.

## Throughput — long test (`-p 4096 -n 1024`)

| Model | prefill `pp4096` | decode `tg1024` | Peak junction | Peak power |
|---|---|---|---|---|
| gpt-oss-20b | 5792 tok/s | 150.7 tok/s | 57 °C | **288 W** |
| Qwen3-32B | 1005 tok/s | 27.9 tok/s | 83 °C and rising | **300 W** |

Two things worth noting:

**Decode throughput holds at long generation.** `tg1024` 150.7 vs `tg128` 150.0 for the MoE
model — no degradation over 8× more tokens. Prefill drops slightly (5792 vs 6050).

**Only the long test gives valid thermal numbers.** On the short test gpt-oss-20b reports a
peak of 19 W at 30 °C, which is an artifact — its whole computation finishes faster than the
telemetry sampling period. [Full explanation](../findings/short-test-telemetry-artifact.md).

---

## Thermals under sustained load

Qwen3-32B, sampled every 15 s, stock 300 W cap:

```
t+15s  gfx 100%  300W  edge 44C  junction 64C  vram 54C  fan 2078rpm
t+30s  gfx 100%  300W  edge 53C  junction 73C  vram 64C  fan 2099rpm
t+45s  gfx 100%  300W  edge 60C  junction 79C  vram 72C  fan 2104rpm
t+60s  gfx 100%  299W  edge 64C  junction 83C  vram 76C  fan 2659rpm
        <- run ended here; temperatures were STILL RISING
```

**The card sits at its full 300 W limit continuously**, and had not reached thermal
equilibrium at 60 seconds. For comparison, a synthetic FMA stress test only drew 279 W in
bursts — **real inference is a heavier load than the stress test used to validate the
card.** [More](../hardware/thermals.md).

Cooling itself behaved correctly: the fan ramped 2078 → 2721 RPM and brought the card from
83 °C to 40 °C within two minutes of the load ending.

---

## Bandwidth and link

| Measurement | Value |
|---|---|
| Host→device, pageable | **54.5 GB/s** |
| Link under load | x16 @ 32.0 GT/s |
| Link at idle | downtrains to 2.5 GT/s |

54.5 GB/s against a ~63 GB/s theoretical maximum for x16 Gen5 confirms the link *performs*
as x16, not merely that it *reports* x16.

---

## What fits on one 32 GB card

| Weights | Verdict |
|---|---|
| up to ~14 GB | Lots of headroom: long context, concurrent requests |
| 14–24 GB | Fits, context to ~32k. **The quality ceiling for one card** |
| 24–32 GB | Fits, but KV cache competes for space |
| over 32 GB | Spills to host RAM — you'd be measuring PCIe, not the GPU |

**Practical ceiling is ~24 GB of weights, not 32.** KV cache needs the rest, and it grows
with context length.

---

## Not measured yet

- **TTFT (time to first token)** — arguably the metric that matters most for interactive
  agents. `llama-bench` measures throughput.
- **The cost of the 210 W cap** — config exists, run pending.
- **x16 → x8** once a second card is installed. Will be measured, not assumed.
- **Multi-GPU anything.** [Collected notes](../findings/multi-gpu-notes.md), no measurements.
- **Answer quality.** Throughput says nothing about whether the output is usable.

## Reproducing this

```bash
git clone https://github.com/<you>/llm-bench-harness.git
cd llm-bench-harness
bench-model <your-model>
```

Raw machine-readable output (`results.json`, `results.csv`) for each run lives in the
harness repo under `results/<run_id>/`.
