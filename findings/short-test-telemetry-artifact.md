# The 19 W that wasn't — a measurement bug of my own making

The most instructive mistake in this project, kept here in full.

**The claim I published.** gpt-oss-20b peaked at **19 W** with junction at **30 °C** — while
delivering 6050 tok/s prefill. A remarkable result: enormous throughput, almost no power.

**It was false.**

**Why.** At `-p 512 -n 128` the model's entire computation takes **under one second**:

- prefill 512 tokens at ~6050 tok/s → **~0.08 s**
- decode 128 tokens at ~150 tok/s → **~0.85 s**

The rest of the wall-clock time is loading 12 GB of weights from disk into VRAM. My
telemetry sampled every 2 s. **It never observed the load at all.** The "peak" it reported
was the idle draw between phases.

**The truth, from a longer test** (`-p 4096 -n 1024`, same model, same card):

| Test | Peak junction | Peak power |
|---|---|---|
| `-p 512 -n 128` | 30 °C | 19 W ← meaningless |
| `-p 4096 -n 1024` | **57 °C** | **288 W** ← real |

So the MoE model draws nearly as much as the dense one (300 W). The "MoE sips power"
conclusion was an artifact of my sampling interval, not a property of the architecture.

**What this means practically.**

- **Throughput from a short test is valid** — `llama-bench` times the computation itself.
- **Thermal and power numbers from a short test are not.**
- For thermal work, use a test that runs **much longer than your sampling period**.

**The fix I shipped.** The harness now flags any run whose peak power is implausibly low
relative to a valid throughput result, rather than presenting the number and letting the
reader draw the wrong conclusion:

```
⚠️ gpt-oss-20b / throughput: pp512 6049.8 tok/s, tg128 149.9 tok/s
   — peak power 19 W — TELEMETRY UNRELIABLE: compute window shorter than the 2.0 s
   sampling period; do not draw thermal conclusions, use a longer test
```

And `bench-model` always runs a long test alongside the short one.

**Generalisable lesson.** A sampled measurement is only valid when the sampling period is
much shorter than the phenomenon. That's obvious stated abstractly, and easy to miss when
the number that comes out is merely surprising rather than obviously absurd.
