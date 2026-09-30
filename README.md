# Radeon AI PRO R9700 + ROCm — field notes

Running local LLMs on **RDNA4 / gfx1201** under ROCm, on a consumer AM5 platform.
Benchmark numbers, monitoring that actually works, and the traps that cost me time.

Everything here is measured on real hardware, not estimated. Where I got something wrong,
the wrong answer is left in with the correction — those entries are usually the useful ones.

Companion repo: **[llm-bench-harness](https://github.com/michal-konik-human/llm-bench-harness)** — the
measurement tooling these numbers come from.

---

## Hardware

| | |
|---|---|
| GPU | Radeon AI PRO R9700 — RDNA4, `gfx1201`, 64 CU, 32 GB GDDR6 with ECC |
| Board | Gigabyte B850 AI TOP (AM5) |
| CPU / RAM | Ryzen 7 9700X · 64 GB DDR5-6000 |
| OS | Ubuntu 24.04.5, kernel 7.0 · ROCm 7.2.4 (in-tree `amdgpu`, no DKMS) |
| Cards | **4 × R9700 = 128 GB VRAM**, PCIe x8 / x4 / x8 / x4 Gen5 (two slots + two M.2 risers), 250 W cap each (since 30 Sep 2026) |

---

## Benchmarks — one card, 32 GB

Stock 300 W cap, x16 Gen5, `llama.cpp 987498f`, ROCm 7.2.4, **3 independent processes** per
model (not `-r 3` — see [why](findings/bimodal-throughput.md)).

| Model | Weights in VRAM | prefill `pp512` | decode `tg128` | Spread |
|---|---|---|---|---|
| gpt-oss-20b MXFP4 (MoE) | 11.3 GiB | **6050** tok/s | **149.9** tok/s | 0.2 % |
| Qwen3-32B Q4_K_M (dense) | 18.4 GiB | **1030** tok/s | **27.98** tok/s | 0.0 % |

**MoE decodes 5.4× faster.** Not because it's a better model — decode is memory-bandwidth
bound, and MoE reads a fraction of the weights per token.

Longer runs (`-p 4096 -n 1024`):

| Model | prefill | decode | Peak junction | Peak power |
|---|---|---|---|---|
| gpt-oss-20b | 5792 tok/s | 150.7 tok/s | 57 °C | **288 W** |
| Qwen3-32B | 1005 tok/s | 27.9 tok/s | 83 °C+ | **300 W** |

Full data with recorded conditions: [`results/`](results/).

**Practical VRAM ceiling on one card is ~24 GB of weights**, not 32 — KV cache needs the
rest. A 63 GB model on one 32 GB card measures PCIe transfer, not the GPU.

---

## Benchmarks — four cards, 128 GB (30 Sep 2026)

`-sm layer -ts 1/1/1/1 --load-mode dio`, 250 W cap per card, `llama.cpp 680a036`, llama.cpp
default batch sizes, 3 independent processes each:

| Model | Size | prefill `pp512` | prefill `pp4096` | decode `tg128` | Spread |
|---|---|---:|---:|---:|---:|
| Qwen3-235B-A22B UD-Q3_K_XL (MoE 128/8) | 96.6 GiB | 619 | 583 | **32.7** | ≤ 1.0 % |
| DeepSeek-V4-Flash UD-IQ3_XXS (MoE 256/6) | 95.9 GiB | 517 | **1020** | **24.0** | ≤ 2.7 % |

With a tuned `--ubatch-size` (see below) prompt processing reaches 894 and 1135 tok/s.
Summed GPU power while doing this: ~400–490 W, not 1000 W — [why](findings/layer-split-power.md).

---

## Findings — start here

These are the entries that would have saved me time. Each one is short and self-contained.

### Things that look broken and aren't

| Finding | One-line summary |
|---|---|
| [`rocm-smi shows N/A`](findings/rocm-smi-shows-na.md) | An idle discrete GPU is parked in D3hot; sysfs returns `EBUSY`. **Use `amd-smi`.** |
| [`netdata silently skips the dGPU`](findings/netdata-misses-dgpu.md) | Same root cause. netdata doesn't error — it just **doesn't create the chart.** Your expensive card ends up unmonitored while the iGPU looks great |
| [`THROTTLED at idle`](findings/false-throttle-flag.md) | This card reports `THROTTLED` at 16 W and 33 °C. Don't alert on that field |

### Things that are silently wrong

| Finding | One-line summary |
|---|---|
| [`device index is not what you assume`](findings/device-index-order.md) | The dGPU took index **0** and the iGPU got **1** — the opposite of common advice. Guessing wrong benchmarks the iGPU: plausible, ~10× too low |
| [`adding a GPU renames your NICs`](findings/pci-renumbering.md) | PCI renumbering shifts every downstream device. Stale interface names return **empty**, not an error — which reads as "no cable" |
| [`power cap floor is 210 W`](findings/power-cap-floor.md) | `MIN_POWER_LIMIT: 210 W`. 200 W is not settable at all |
| [`the 19 W that wasn't`](findings/short-test-telemetry-artifact.md) | My own measurement bug: a fast MoE model's compute window is shorter than the telemetry sampling period |
| [`the card always says x16`](findings/pcie-endpoint-reports-x16.md) | The R9700 has its own PCIe switch; the GPU endpoint is always x16. The real slot link (x8 / x4) is at the root port |
| [`-ts 1,1,1,1 in llama-bench`](findings/llama-bench-tensor-split-syntax.md) | `llama-bench` separates the split with `/`; a comma is a sweep = whole model on GPU 0. Cost two days and a fake "multi-GPU bug" |
| [`one space breaks tool calling`](findings/tool-call-template-space.md) | llama.cpp derives the tool-call parser from the chat template; a model writing one extra space gets plain text back |

### Platform / assembly

| Finding | One-line summary |
|---|---|
| [`24 lanes, four GPUs`](hardware/pcie-lane-plan.md) | x8/x8/x4/x4, all CPU-attached, no chipset hop. The M.2 slots are the trick |
| [`undocumented BIOS bifurcation`](hardware/bios-bifurcation.md) | Not in the manual — I decompiled the BIOS image to find it. x8/x8 is automatic; no riser needed |
| [`M.2 risers supply no slot power`](hardware/m2-riser-power.md) | Needs its own 12 V PCIe feed. Never SATA |
| [`ROCm install, and skipping DKMS`](hardware/rocm-install.md) | Kernel 7.0 has in-tree gfx1201 support; DKMS is a risk, not a requirement. Plus a package in the official guide that doesn't exist |
| [`card 1 verification`](hardware/card-verification.md) | What to check after seating a card, and what good looks like |
| [`sustained inference thermals`](hardware/thermals.md) | Real inference is a heavier load than a synthetic stress test |
| [`fan control needs overdrive`](findings/fan-control-requires-overdrive.md) | Stock curve: 100–110 °C junction on 4 cards at 40–57 % fan. No fan control on RDNA4 without `ppfeaturemask` bit 0x4000; with it: 81–83 °C, quiet at idle. Script in [`tuning/`](tuning/) |

### Multi-GPU (measured on 4 cards, 28–30 Sep 2026)

| Finding | One-line summary |
|---|---|
| [`no XGMI on this card`](findings/multi-gpu-notes.md) | Every byte between cards crosses PCIe. P2P is documented to hang a 4-card host. `NCCL_PROTO=Simple` and `NCCL_P2P_DISABLE=1` are mandatory |
| [`ROCm mmap load hang`](findings/rocm-mmap-load-hang.md) | Models ≳ 50 GiB hang forever on load; `--load-mode dio` fixes it — independent of GPU count |
| [`ubatch per model`](findings/ubatch-per-model.md) | Default 512 was never best: +57 % (Qwen3-235B) … +4 % (dense), and 4096 costs DeepSeek −58 % |
| [`layer split power`](findings/layer-split-power.md) | 4 × 250 W cards draw ~470 W on a 235B model; the last card in the chain works hardest |

---

## Monitoring that works on a discrete AMD GPU

[`monitoring/`](monitoring/) — a netdata collector, alert rules, and a terminal status tool.

**Why it exists:** netdata's built-in `amdgpu` collector reads sysfs. An idle discrete card
returns `EBUSY`, and netdata responds by **not creating the chart at all** — no error, no
warning. On my box that produced full temperature/power/clock charts for the *integrated*
GPU and **memory charts only** for the R9700. The one component that can physically burn
was unmonitored, and the dashboard looked healthy.

This collector reads through `amd-smi` instead, and:

- reports **junction and VRAM temperature** separately (VRAM is the metric that limits you —
  GDDR6 degrades permanently above 100 °C, well before the 110 °C throttle point);
- checks `runtime_status` first so polling **doesn't** keep an idle card awake burning ~15 W;
- reads **PCIe AER counters unconditionally**, even while the card sleeps, because a link
  throwing errors must not become invisible just because the GPU is idle;
- derives a **cooling-fault** metric (fan at 0 RPM while junction ≥ 70 °C) — the clearest
  "act now" signal there is;
- ships 22 alert rules written as **templates on context**, so additional cards inherit
  them automatically.

It's specific to AMD + netdata but not to this card. See [`monitoring/README.md`](monitoring/README.md).

---

## A note on method

Every number here was produced by a harness that records the conditions alongside the
result: `llama.cpp` commit and build flags, ROCm version, power cap, PCIe link width read
*under load*, peak temperatures, the exact environment variables used, and ECC/AER counters
before and after. If the error counters moved during a run, the result was discarded rather
than adjusted.

That sounds like overkill until the first time you try to compare two numbers from
different weeks.

## Corrections welcome

If you have numbers that contradict these, open an issue — especially on multi-GPU, where
the numbers above are from one machine.

## License

MIT for code, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) for the notes.
