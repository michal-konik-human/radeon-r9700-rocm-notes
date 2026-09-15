# Why every benchmark run should be its own process

**The documented behaviour.** Decode throughput on this class of AMD card is described as
**bimodal**: the card settles into one of two operating modes and **stays there for the
lifetime of the process**.

**The consequence for benchmarking.** `llama-bench -r 3` runs three measurements **inside
one process** — therefore inside one mode. You get three nearly identical numbers, a tiny
standard deviation, and a completely false sense of precision. The flag measures repeatability
*within* a mode, not the variance you actually care about.

Only **separate OS processes** can land in different modes.

**What I do instead:** one process per run, with a cooldown between them so each starts from
a comparable temperature, and the **spread** reported as prominently as the mean.

```bash
for i in 1 2 3; do
  ./llama-bench -m "$M" -ngl 999 -sm none -p 512 -n 128 -r 1
  sleep 45
done
```

**My result: the bimodality did not appear.** Across 3 independent processes the spread was
**under 0.25 %** for both models tested:

| Model | run 1 | run 2 | run 3 | spread |
|---|---|---|---|---|
| gpt-oss-20b `tg128` | 149.88 | 149.96 | 149.95 | 0.1 % |
| Qwen3-32B `tg128` | 27.97 | 27.99 | 27.97 | 0.1 % |

**I kept the method anyway**, for two reasons: it costs nothing, and the alternative is
variance you never notice. The behaviour may depend on model, driver version, or workload
shape — absence in one configuration isn't evidence of absence generally.

**How to read spread when it does appear:**

- below ~2 % → the mean is a sensible number to quote;
- above ~10 % **with results in two clusters** → that's the bimodality. **Report both
  modes, not their mean** — the mean describes a state the card is never in.
