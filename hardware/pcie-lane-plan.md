# 24 PCIe lanes, four GPUs — the lane plan

On a consumer AM5 platform the limiting resource isn't slots. It's **lanes**.

The CPU provides **24 usable PCIe 5.0 lanes**. Four GPUs have to come out of that, and you
want all of them **CPU-attached** — a chipset hop adds latency and shares bandwidth, which
matters when every inter-GPU byte already crosses PCIe (there's
[no XGMI on this card](../findings/multi-gpu-notes.md)).

## The plan (as designed)

| Device | Slot | Width | Source |
|---|---|---|---|
| GPU 1 | `PCIEX16` | x8 | CPU |
| GPU 2 | `PCIEX8` | x8 | CPU |
| GPU 3 | `M2A_CPU` via M.2→PCIe adapter | x4 (assumed) | CPU |
| GPU 4 | `M2B_CPU` via M.2→PCIe adapter | x4 (assumed) | CPU |

8 + 8 + 4 + 4 = **24 lanes, all Gen5, all CPU-attached, no chipset hop.**

## ⚠️ Correction — GPU 3 measured, not assumed (2026-09-28)

After actually installing GPU 3, the assumed x4 above is **wrong**. Measured live:

```bash
$ curl -s "http://127.0.0.1:19999/api/v1/data?chart=amdgpu_gpu2.pcie_width&after=-30&points=1"
```
returns width **8**, and the health-rule alarm confirms it:
```
amdgpu_gpu2.pcie_width.amdgpu_pcie_width_degraded CLEAR value=8
```
(`degraded` fires at <4, so 8 reads as healthy/full-width for this card, not degraded — the
number itself is what matters here, not the alarm state.) This is the CPU-facing link width
as amd-smi reports it; a raw `lspci -vvv -s 09:00.0` on the GPU function itself shows
`LnkSta: Speed 32GT/s, Width x16` — that's just the ADT-Link riser board's own internal
switch fanning back out to a full x16 slot for the card, **not** the actual upstream
bottleneck back to the CPU. Trust the amd-smi/netdata number (8), not the GPU's own
immediate-link `lspci` reading (16), when you want the true CPU-facing bandwidth.

So the real allocation, at least for GPU 3, is **the same x8 as GPU 1 and GPU 2** — not x4.

### What this means for the lane budget

If GPU 3 is genuinely taking x8 rather than x4, the arithmetic above no longer works:
8 + 8 + 8 = 24 lanes **already fully consumed by three cards**, before GPU 4 exists.

**This is flagged, not resolved.** GPU 4 hasn't been installed or measured yet, so it's
unknown whether:
- `M2A_CPU`/`M2B_CPU` actually only ever carry x4 each and the x8 reading above is
  measuring something else in the chain (e.g. the ADT-Link board's redriver presenting a
  wider link than the wire actually carries, or amd-smi reporting a different hop than
  intended), or
- the board's lane mux genuinely gives GPU 3 x8, in which case GPU 4 may be starved down
  to a much narrower link (or a chipset hop) when it's added, or
- the 24-lane budget itself needs revisiting for this specific board.

**Do not assume GPU 4 will get x4 (or any specific width) based on this plan.** Measure it
the same way (`amd-smi`/netdata `pcie_width`, not just `lspci` on the GPU function) as soon
as it's installed, and update this file with the real number before drawing conclusions
about the total lane budget.

## The two things that make this work

**1. The x16 slot drops to x8 automatically.** On this board (Gigabyte B850 AI TOP) an
onboard mux splits the lanes when the second slot is populated. **You do not need a
bifurcation riser** — which is not documented anywhere, see
[BIOS bifurcation](bios-bifurcation.md).

**2. The CPU M.2 slots are real PCIe 5.0 lanes and independent of the graphics slots.**
They keep GPU 1/2 at full width with GPU 3 installed. That's what makes a multi-GPU plan
possible on a consumer board at all — but see the correction above for what width they
actually deliver.

## The consequences you have to accept

- **The boot drive has to move.** Both CPU M.2 slots are now GPUs, so the OS drive goes to
  the chipset-fed slot — PCIe 4.0 x2 instead of 5.0 x4. Verified after the move:
  `16.0 GT/s PCIe`, width 2. Slower boot, but the lanes are worth more as GPU lanes.
- **The third PCIe slot is unusable anyway.** It's chipset-fed x2, and physically blocked
  by a dual-slot card in the x8 slot — only one slot pitch between them.
- **M.2 adapters need their own power** — see [M.2 riser power](m2-riser-power.md).
- **GPU 1 will drop from x16 to x8** the moment GPU 2 goes in. That's expected. Benchmark
  it before and after so the cost is measured rather than assumed.
- **GPU 1 and GPU 2 stayed at x8 after GPU 3 went in** — confirmed via the same
  amd-smi/netdata `pcie_width` metric, unchanged from their pre-GPU-3 readings. Adding a
  third CPU-attached card did not further degrade the first two.

## Why not other layouts

- **A x4x4x4x4 riser in the x16 slot** would give four x4 cards and leave the x8 slot
  empty — strictly worse, and I could find nobody reporting that mode actually working on
  this board.
- **x8x4x4 + the x8 slot** gives the same split as the plan above but wastes the M.2 slots
  and adds a riser. More parts, same result.

The x8/x8/x8(?)/x?? plan is still probably close to optimal — but the exact per-slot
numbers in this file were assumptions until measured, and one of them (GPU 3) turned out
different from the assumption. Measure, don't assume, for GPU 4 too.
