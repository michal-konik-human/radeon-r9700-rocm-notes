# Don't assume which device index is your discrete GPU

**The common advice:** "exclude the integrated GPU, it'll be the last device."

**What actually happened on my machine:**

```
$ llama-cli --list-devices
Available devices:
  ROCm0: AMD Radeon AI PRO R9700 (32624 MiB, 32558 MiB free)
  ROCm1: AMD Radeon Graphics (30959 MiB, 30955 MiB free)
```

The discrete card took index **0**. The integrated GPU got **1** — the opposite of the
assumption. Confirmed independently through HIP:

```
hipGetDeviceCount = 2
  HIP dev 0 : AMD Radeon AI PRO R9700  arch=gfx1201  VRAM=31.9 GiB  pciBus=03:00.0
  HIP dev 1 : AMD Radeon Graphics      arch=gfx1036  VRAM=30.2 GiB  pciBus=11:00.0
```

**Why this is dangerous rather than merely annoying.** Had I followed the guide and set
`HIP_VISIBLE_DEVICES=1`, I would have benchmarked the **integrated GPU**. It would have
run. It would have produced a number. That number would have been roughly **10× too low**
and looked entirely plausible.

Note also the iGPU reports ~30 GiB of "VRAM" (it's shared system memory), so a size check
wouldn't have caught the mistake either.

**Fix.** Map it explicitly, every time, and set the variable rather than relying on a
default:

```bash
amd-smi static --json | python3 -c 'import json,sys
for g in json.load(sys.stdin)["gpu_data"]:
    a=g["asic"]; print(g["gpu"], a["market_name"], a["target_graphics_version"])'
export HIP_VISIBLE_DEVICES=0     # whatever the real index turned out to be
```

**Re-check after every hardware change** — adding a card renumbers the PCI bus and can
reorder devices. See [PCI renumbering](pci-renumbering.md).
