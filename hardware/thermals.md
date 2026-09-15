# Sustained inference is a heavier load than a stress test

**The assumption.** Validate cooling with a synthetic stress test, then trust it.

**What the stress test said.** A hand-written HIP FMA burner: **279 W in bursts**, junction
peaking at 65 °C. Comfortable.

**What real inference said.** Dense-model inference (Qwen3-32B Q4_K_M), telemetry sampled
every 15 s, stock 300 W cap:

```
t+15s  gfx 100%  300W  edge 44C  junction 64C  vram 54C  fan 2078rpm
t+30s  gfx 100%  300W  edge 53C  junction 73C  vram 64C  fan 2099rpm
t+45s  gfx 100%  300W  edge 60C  junction 79C  vram 72C  fan 2104rpm
t+60s  gfx 100%  299W  edge 64C  junction 83C  vram 76C  fan 2659rpm
        <- the run ended here; temperatures were STILL RISING
```

Three things to take from that:

**1. The card sits at its full 300 W limit continuously**, not in bursts. Real inference on
a dense model is a *heavier* load than the synthetic test used to validate the cooling.

**2. Temperatures had not plateaued at 60 seconds.** Junction reached 83 °C and was still
climbing. A longer measurement series goes higher.

**3. MoE is not gentler, despite first appearances.** Under a long test gpt-oss-20b draws
**288 W at 57 °C** — close to the dense model. My earlier "MoE barely heats the card"
conclusion was [a measurement artifact](../findings/short-test-telemetry-artifact.md), not a
property of the architecture.

## Where the real limits are

Read from the card itself, not from a spec sheet:

```
SLOWDOWN_EDGE_TEMPERATURE:    110 °C      SHUTDOWN_EDGE:    115 °C
SLOWDOWN_HOTSPOT_TEMPERATURE: 110 °C      SHUTDOWN_HOTSPOT: 115 °C
SLOWDOWN_VRAM_TEMPERATURE:    108 °C      SHUTDOWN_VRAM:    113 °C
```

**But the limit that should govern your alerting is lower than any of those.** GDDR6
degrades **permanently** above ~100 °C — it doesn't fail, it quietly loses characteristics.
Waiting for the 108 °C firmware threshold is waiting too long. My alert thresholds are
therefore VRAM warn 85 / critical 95, and junction warn 90 / critical 100
([monitoring](../monitoring/)).

## The cooling itself was fine

Worth separating the two conclusions: the fan responded correctly, ramping 2078 → 2721 RPM
and bringing the card from 83 °C to 40 °C within two minutes of the load ending. This is a
**power draw** finding, not a cooling defect.

## Practical consequences

- **Set the power cap before a measurement series, not after** — and record it with every
  number, because the same model at 300 W and 210 W are two different measurements.
- **Watch VRAM temperature, not just junction.** It rose faster than edge temperature and
  it's the one with the permanent-degradation threshold.
- For a four-card build, uncapped means **~1200 W of GPU alone**, with this thermal
  behaviour per card.
