# What to check after seating a card — and what good looks like

Run this list before you trust a new card. Every value below is a real reading from a
working Radeon AI PRO R9700 in the x16 slot.

## PCIe link

```bash
sudo lspci -vv -s 03:00.0 | grep -E "LnkCap:|LnkSta:"
    LnkCap: Port #0, Speed 32GT/s, Width x16
    LnkSta: Speed 32GT/s, Width x16
```

`LnkSta` is what you actually got. **Read it under load** — at idle the link downtrains to
2.5 GT/s to save power, which looks alarming and isn't.

## Resizable BAR

```bash
sudo lspci -vv -s 03:00.0 | grep -A3 "Physical Resizable BAR"
	BAR 0: current size: 32GB, supported: 256MB 512MB 1GB 2GB 4GB 8GB 16GB 32GB
```

`current size: 32GB` means ReBAR is on and the whole framebuffer is host-visible. If it
shows a small size, enable **Re-Size BAR Support** in BIOS.

## VRAM and ECC

```bash
sudo dmesg | grep -E "VRAM:|RAM width|MEM ECC"
  amdgpu 0000:03:00.0: VRAM: 32624M 0x...
  amdgpu 0000:03:00.0: [drm] RAM width 256bits GDDR6
  amdgpu 0000:03:00.0: MEM ECC is active.
```

Then confirm the counters are zero:

```bash
amd-smi metric -g 0 | grep -A4 "    ECC:"
        TOTAL_CORRECTABLE_COUNT: 0
        TOTAL_UNCORRECTABLE_COUNT: 0
```

## Bus cleanliness after load

Run something heavy, then:

```bash
sudo dmesg | grep -iE "aer|correctable error|link down|amdgpu.*(error|fail|timeout|reset)"
```

Expect **nothing** attributable to the card. Benign entries you will see and can ignore:
`_OSC: OS now controls`, `RAS: Correctable Errors collector initialized`, and
`ataN: SATA link down` for empty SATA ports.

Also check the AER counters directly — they're readable without root and don't need the
card awake:

```bash
cat /sys/bus/pci/devices/0000:03:00.0/aer_dev_correctable
cat /sys/bus/pci/devices/0000:03:00.0/aer_dev_fatal
```

## It enumerates — but does it compute?

The check most people skip. Enumeration proves the driver bound; it proves nothing about
the compute stack.

Compile and **run** a trivial HIP kernel targeting your arch:

```bash
/opt/rocm/bin/hipcc --offload-arch=gfx1201 -O3 -o t t.cpp && ./t
device 0: AMD Radeon AI PRO R9700 (gfx1201)
vector add 2^24: PASS (bad=0)
H2D pageable bandwidth: 54.5 GB/s
```

54.5 GB/s host-to-device is consistent with x16 Gen5 (~63 GB/s theoretical) — which
confirms the link *performs* as x16, not merely that it *reports* x16.

## Things that look wrong and aren't

- `rocm-smi` showing `N/A` for the card — [explained here](../findings/rocm-smi-shows-na.md)
- `THROTTLED` at idle — [explained here](../findings/false-throttle-flag.md)
- HIP reporting 32 compute units where `dmesg` says 64 — RDNA counts WGPs vs CUs; 32 WGPs
  = 64 CUs. Not a fault.
- dmesg complaints about HDMI infoframes or `optc31_disable_crtc` — check the PCI address;
  on my box those were the **integrated** GPU's display path, unrelated to the R9700.
