# 24 PCIe lanes, four GPUs — the lane plan

On a consumer AM5 platform the limiting resource isn't slots. It's **lanes**.

The CPU provides **24 usable PCIe 5.0 lanes**. Four GPUs have to come out of that, and you
want all of them **CPU-attached** — a chipset hop adds latency and shares bandwidth, which
matters when every inter-GPU byte already crosses PCIe (there's
[no XGMI on this card](../findings/multi-gpu-notes.md)).

## The plan

| Device | Slot | Width | Source |
|---|---|---|---|
| GPU 1 | `PCIEX16` | x8 | CPU |
| GPU 2 | `PCIEX8` | x8 | CPU |
| GPU 3 | `M2A_CPU` via M.2→PCIe adapter | x4 | CPU |
| GPU 4 | `M2B_CPU` via M.2→PCIe adapter | x4 | CPU |

8 + 8 + 4 + 4 = **24 lanes, all Gen5, all CPU-attached, no chipset hop.**

## The two things that make this work

**1. The x16 slot drops to x8 automatically.** On this board (Gigabyte B850 AI TOP) an
onboard mux splits the lanes when the second slot is populated. **You do not need a
bifurcation riser** — which is not documented anywhere, see
[BIOS bifurcation](bios-bifurcation.md).

**2. The CPU M.2 slots are real PCIe 5.0 x4 and independent of the graphics slots.** They
keep full width with both GPUs installed. That's what makes a 4-GPU plan possible on a
consumer board at all.

## The consequences you have to accept

- **The boot drive has to move.** Both CPU M.2 slots are now GPUs, so the OS drive goes to
  the chipset-fed slot — PCIe 4.0 x2 instead of 5.0 x4. Verified after the move:
  `16.0 GT/s PCIe`, width 2. Slower boot, but the lanes are worth more as GPU lanes.
- **The third PCIe slot is unusable anyway.** It's chipset-fed x2, and physically blocked
  by a dual-slot card in the x8 slot — only one slot pitch between them.
- **M.2 adapters need their own power** — see [M.2 riser power](m2-riser-power.md).
- **GPU 1 will drop from x16 to x8** the moment GPU 2 goes in. That's expected. Benchmark
  it before and after so the cost is measured rather than assumed.

## Why not other layouts

- **A x4x4x4x4 riser in the x16 slot** would give four x4 cards and leave the x8 slot
  empty — strictly worse, and I could find nobody reporting that mode actually working on
  this board.
- **x8x4x4 + the x8 slot** gives the same split as the plan above but wastes the M.2 slots
  and adds a riser. More parts, same result.

The x8/x8/x4/x4 plan is both optimal and the simplest.
