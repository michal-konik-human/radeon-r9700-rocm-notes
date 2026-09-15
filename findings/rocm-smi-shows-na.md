# `rocm-smi` shows N/A for the discrete GPU — and nothing is wrong

**Symptom.** Fresh install, card seated, and this:

```
Device  Node  IDs             Temp    Power   SCLK  MCLK     Fan  Perf     VRAM%  GPU%
0       1     0x7551, 44423   N/A     N/A     N/A   N/A      0%   unknown  0%     0%
1       2     0x13c0, 2562    35.0°C  0.008W  N/A   3000Mhz  0%   auto     24%    0%
```

Device 0 is the Radeon AI PRO R9700. Device 1 is the CPU's integrated GPU. **The expensive
card reports nothing; the integrated one reports fine.** It reads like a dead card.

**Cause.** With no display attached and no compute clients, the kernel parks the discrete
GPU in **D3hot** via runtime power management. sysfs reads then fail:

```bash
$ cat /sys/bus/pci/devices/0000:03:00.0/power/runtime_status
suspended
$ cat /sys/bus/pci/devices/0000:03:00.0/power_state
D3hot
$ cat /sys/bus/pci/devices/0000:03:00.0/hwmon/hwmon4/temp1_input
cat: ...: Device or resource busy          # EBUSY
```

`rocm-smi` reads sysfs, so it renders `EBUSY` as `N/A`. On my machine the card had spent
935 s suspended against 46 s active since boot — which is why it's suspended nearly every
time you look.

**Fix.** Use **`amd-smi`**. It wakes the card by a different path and always returns real
values:

```bash
$ amd-smi metric -g 0 | grep -E "SOCKET_POWER|hotspot"
    SOCKET_POWER: 37 W
```

`lm-sensors` also reads it — but unreliably: on a suspended card I saw `junction` vanish
entirely and `vddgfx` report a nonsense 0.025 V. **`amd-smi` is the only source I'd trust
for an idle discrete card.**

**Don't disable runtime PM.** It saves ~15 W idle per card. Keep it and use the right tool.

**The second-order consequence** is worse than the cosmetic one — see
[netdata silently skips the dGPU](netdata-misses-dgpu.md).
