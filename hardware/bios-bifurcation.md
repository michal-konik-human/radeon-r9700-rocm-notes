# Finding an undocumented BIOS option by decompiling the firmware

**The question.** Can this board split its x16 slot into x8/x8? The whole four-GPU plan
depends on the answer.

**The problem.** The manual doesn't mention bifurcation. Vendor support didn't know.
Forum answers contradicted each other. For a purchase decision that's not good enough.

**What I did.** Decompiled the shipping BIOS image and read the setup questions directly
out of the binary.

**The answer.** The option exists — `PCIEX16 Bifurcation`, under Settings → IO Ports, with
these modes:

```
Auto  /  PCIE x8x8  /  PCIE x8x4x4  /  PCIE x4x4x4x4
```

(A `PCIE x4x4` entry also exists but is APU-gated.)

**And the important part: you don't need it.** On this board the x16 slot drops to x8
**automatically** when the second slot is populated — an onboard mux handles it. Leave
`PCIEX16 Bifurcation` on `Auto`. **No bifurcation riser required.**

Worth knowing: users have confirmed `x8x4x4` works, but I could find **nobody reporting
`x4x4x4x4` actually running** on this board. If your plan depends on that mode, treat it
as unverified.

## The other BIOS setting that actually matters

**`Above 4GB MMIO Limit`** (with `Above 4G Decoding` enabled) determines whether four
32 GB cards can all initialise — that's 128 GB of BAR space to map.

On my board this turned out to be a non-issue: `/proc/iomem` showed a 64-bit window of
**~950 GiB**, so four cards need a small fraction of the available space. Check yours
before assuming:

```bash
sudo grep -i "PCI Bus 0000:00" /proc/iomem | tail -1
```

If a card goes missing from `amd-smi` on a multi-card build, this is the first setting to
raise.

## Generalisable point

When a hardware capability is undocumented and forum answers conflict, the firmware itself
is authoritative and readable. It's less work than a week of guessing, and the answer is
definitive.
