# Fan control on RDNA4 requires amdgpu overdrive — and the stock curve lets 4 cards hit 110 °C

**Symptom:** under a real 4-card inference load, three of four R9700s reached **100–110 °C
junction** while their fans ran at **40–57 %**. GDDR6 stayed at ≤ 78 °C, so nothing was damaged,
but 110 °C is the card's own slowdown point. The firmware curve is tuned for noise.

**You cannot change fan speed from Linux by default:**
- no `pwm1_enable` in hwmon, and `fan1_enable` returns `EINVAL`;
- the only interface is `/sys/class/drm/cardN/device/gpu_od/fan_ctrl/fan_curve` (5 points,
  hotspot °C → fan %), which **does not exist** unless the kernel parameter
  `amdgpu.ppfeaturemask` has bit **0x4000** (PP_OVERDRIVE_MASK) set.
- zero-RPM mode is not offered on these cards (`fan_zero_rpm_enable` is empty).

**Fix used here:**
1. `amdgpu.ppfeaturemask=0xfff7ffff` (the default `0xfff7bfff` plus only `0x4000`) in
   `GRUB_CMDLINE_LINUX_DEFAULT`, `update-grub`, reboot. Side effects: the kernel marks itself
   "tainted" (a label), and the power-cap ceiling rises from 300 to **330 W**.
2. [`tuning/gpu-tuning.sh`](../tuning/gpu-tuning.sh) + [`gpu-tuning.service`](../tuning/gpu-tuning.service):
   at every boot, for every card with PCI ID `0x7551`, writes the power cap and the curve
   (clamped to the range the firmware reports), then commits with `c`. Settings in sysfs do
   not survive a reboot.

**Results, same 5-minute 4-card full load (Qwen3-32B prefill, one process per card, 250 W cap):**

| | junction max | fan max | idle fan |
|---|---|---|---|
| stock curve, 300 W (real workload) | 100–110 °C | 40–57 % | ~890 rpm |
| `50→35 %, 60→50, 70→65, 80→85, 90→100` | 78–81 °C | 78–85 % | ~1210 rpm (louder at idle) |
| **`55→min, 65→30, 75→55, 82→80, 90→100`** | **81–83 °C** | 74–81 % | **~890 rpm** (stock) |

The last curve is the one kept: quiet while cold, steep when hot.

**Traps met on the way:** `/sys/class/drm/card[0-9]*` also matches connectors (`card2-DP-9`);
and **`cardN` numbers change across reboots** (the iGPU became `card0`) — select cards by PCI ID
or address, never by `cardN`.
