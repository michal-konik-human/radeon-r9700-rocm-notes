# The R9700 always reports x16 — read the root port instead

**Symptom:** every card reports `current_link_width = 16` at `32.0 GT/s`, even the ones on M.2
risers that physically cannot be wider than x4. Tools that read the GPU's own link (the
`bench.py` of this project, until 30 Sep 2026, and many monitoring scripts) report "x16 Gen5"
for every card.

**Cause:** the Radeon AI PRO R9700 carries **its own PCIe switch**. The path is

```
root port (CPU) ──x8/x4──> switch upstream port ──x16──> switch downstream port ──x16──> GPU
```

The GPU endpoint talks to the switch on the same board, so its link is always a full x16.
The slot link — the one that matters — is the first hop, at the CPU root port.

**Measured on the 4-card build (under load):**

| GPU | Root port | Root-port link | Endpoint says |
|---|---|---|---|
| `03:00.0` (PCIEX16) | `00:01.1` | **x8 Gen5** | x16 |
| `06:00.0` (M.2 riser) | `00:01.2` | **x4 Gen5** | x16 |
| `09:00.0` (PCIEX8) | `00:01.4` | **x8 Gen5** | x16 |
| `19:00.0` (M.2 riser) | `00:02.2` | **x4 Gen5** | x16 |

**How to read it** (no root needed):

```bash
for d in $(readlink -f /sys/bus/pci/devices/0000:06:00.0 | grep -oE "[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-9]"); do
  echo "$d x$(cat /sys/bus/pci/devices/$d/current_link_width) $(cat /sys/bus/pci/devices/$d/current_link_speed)"
done
```

Take the narrowest link on the path. Read it under load — links downtrain at idle.
