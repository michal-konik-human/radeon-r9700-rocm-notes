# Adding a GPU renamed every network interface

**Symptom.** After installing the first GPU, commands that had worked for days returned
nothing. Not an error — **nothing**.

**Cause.** Installing the card renumbered the PCI bus, and every downstream device shifted:

| Before | After | Device |
|---|---|---|
| `enp3s0` | `enp6s0` | 10GbE #1 (AQC113C) |
| `enp10s0` | `enp13s0` | 10GbE #2 |
| `wlp4s0` | `wlp7s0` | Wi-Fi |
| `0e:00.0` | `11:00.0` | integrated GPU |

Predictable in hindsight — `enpXsY` encodes the PCI bus number — but easy to forget when
the change is triggered by seating a GPU rather than by touching the network.

**Why it's nastier than a normal breakage.** A command against a non-existent interface
returns **empty output, not an error**:

```bash
$ ethtool enp3s0 | grep "Link detected"     # old name, card now removed from that bus
$                                            # nothing. reads exactly like "no cable"
```

I spent real time believing a cable was unplugged.

**Second-order effect.** A previously applied fix silently reverted, because it had been
applied to an interface name that no longer existed:

```bash
$ iw dev wlp7s0 get power_save
Power save: on          # the fix had targeted wlp4s0
```

**Fixes.**

1. Don't hardcode interface names in scripts. Discover them from the PCI device:
   ```bash
   ls /sys/bus/pci/devices/0000:06:00.0/net/     # -> enp6s0
   ```
   or match by driver / MAC rather than by name.
2. Expect renumbering **after every added card**, and re-verify device indices
   ([device index order](device-index-order.md)) and anything pinned to a PCI address.
3. Use predictable-name overrides (systemd `.link` files) if you need names to be stable.

## Recurrence, 2026-09-28 (installing the third card)

Happened again, same cause, different specific fallout: after seating the third GPU the
machine dropped off the network entirely — not just a renamed interface this time, `ping`
reported the host down. The box itself had booted fine (confirmed at the physical
display/keyboard); only the network side was affected.

**Fastest recovery on this occasion:** connect over Wi-Fi instead of chasing the new
ethernet interface name.
```bash
nmcli device wifi connect "studio" --ask
```
Came back up on the *same* DHCP-assigned IP as before (the router's lease is presumably
keyed to MAC, and the Wi-Fi and Ethernet NICs are different MACs — worth noting if you rely
on a fixed IP after a network path change following a card install; here it happened to
still work, but don't assume it always will).
