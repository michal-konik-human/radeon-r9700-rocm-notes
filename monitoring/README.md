# Monitoring a discrete AMD GPU with netdata

A netdata collector, 22 alert rules, and a terminal status tool — for AMD GPUs where the
built-in collector silently doesn't work.

## The problem this solves

netdata's built-in `amdgpu` collector reads sysfs hwmon. A discrete card with no display
attached is parked in **D3hot** by runtime power management, and sysfs reads then return
`EBUSY`. netdata **does not report an error — it simply doesn't create the chart.**

On my machine that produced:

- integrated GPU: temperature, power, clocks, utilisation — **complete**
- discrete Radeon AI PRO R9700: **memory charts only.** No temperature. No power. No fan.

The one component that can physically burn was unmonitored, next to a healthy-looking
temperature graph for a harmless iGPU. Monitoring that fails by looking like success is
the worst kind.

Full write-up: [../findings/netdata-misses-dgpu.md](../findings/netdata-misses-dgpu.md)

## What this does differently

- **Reads through `amd-smi`**, which wakes the card by a different path and always returns
  real values.
- **Checks `runtime_status` first** — a cheap read that does *not* wake the card — and only
  polls `amd-smi` when the card is already active. Polling otherwise keeps every card awake
  burning ~15 W each. A `powerstate` chart shows which state each card is in, so a gap in
  the temperature chart is explained rather than mysterious.
- **Reads PCIe AER counters unconditionally**, even while the card sleeps. A link throwing
  errors must not become invisible because the GPU is idle.
- **Charts VRAM temperature separately from junction.** VRAM is the limiting metric —
  GDDR6 degrades permanently above ~100 °C, well before the 110 °C throttle point.
- **Derives a cooling-fault metric** (fan at 0 RPM while junction ≥ 70 °C) in the plugin,
  where RPM and temperature appear in the same sample. A cross-chart health expression
  would be fragile.
- **Auto-detects all GPUs and their PCI addresses.** Nothing is hardcoded.

## Install

```bash
# collector
sudo install -o root -g root -m 0755 amdgpu.plugin /usr/lib/netdata/plugins.d/amdgpu.plugin

# alert rules
sudo install -o root -g netdata -m 0640 health.d-amdgpu.conf /etc/netdata/health.d/amdgpu.conf

# terminal status tool (optional)
sudo install -o root -g root -m 0755 gpu-status /usr/local/bin/gpu-status

# NVMe SMART helper (optional; the only piece that needs root)
sudo install -o root -g root -m 0755 smart-helper /usr/local/sbin/smart-helper
sudo install -m 0644 smart-helper.service smart-helper.timer /etc/systemd/system/
sudo systemctl enable --now smart-helper.timer

# amd-smi needs GPU device access
sudo usermod -aG video,render netdata
```

Then in `/etc/netdata/netdata.conf`:

```ini
[plugins]
    amdgpu = yes

[plugin:proc]
    # disable the built-in collector - it draws misleading partial charts
    /sys/class/drm = no
```

```bash
sudo systemctl restart netdata
```

**Note:** `netdatacli reload-health` reports "Make sure the netdata service is running"
even when it is. Reload rules with `systemctl restart netdata`.

## Verify it actually works

Don't trust "the charts appeared". Two checks:

**1. Are the charts you need there, for the card you care about?**

```bash
curl -s http://127.0.0.1:19999/api/v1/charts \
  | python3 -c 'import json,sys;[print(c) for c in sorted(json.load(sys.stdin)["charts"]) if c.startswith("amdgpu")]'
```

You should see `temperature`, `power`, `fan`, `clocks`, `ecc`, `aer`, `cooling_fault` for
**each** GPU — not just memory charts for one of them.

**2. Does the alert chain actually fire?**

Install a rule that must trip, confirm it does, then remove it. "22 rules loaded" is not
the same as "alerting works":

```
template: TEST_alarm_chain
      on: amdgpu.temperature
  lookup: max -1m unaligned of edge
   every: 5s
    warn: $this > 5
    info: Test - must always fire. If you see this, the alert chain works.
      to: sysadmin
```

## Alert thresholds

Read off the card itself, with alert thresholds deliberately well below them:

| Metric | Warn | Critical | Firmware limit |
|---|---|---|---|
| Junction | 90 °C | 100 °C | throttle 110, shutdown 115 |
| **VRAM** | **85 °C** | **95 °C** | throttle 108, shutdown 113 |
| Edge | 85 °C | 95 °C | throttle 110, shutdown 115 |
| Cooling fault | — | **immediate** | — |
| ECC uncorrectable | — | **> 0** | — |
| PCIe AER fatal | — | **> 0** | — |
| PCIe link width | < x4 | < x2 | — |

VRAM has a *lower* threshold than the core on purpose: it degrades permanently above
100 °C. Link-width alerting starts below x4 so that a normal x16→x8 drop when you add a
second card doesn't fire.

**There is deliberately no alert on the throttle flag** — this card reports `THROTTLED` at
idle, at 16 W and 33 °C. See [../findings/false-throttle-flag.md](../findings/false-throttle-flag.md).

## The netdata trap that bit me

A `lookup` **without `of <dimension>` SUMS all the chart's dimensions.** My first NIC
temperature rule had no `of` and reported **80 °C from two controllers sitting at 39 °C
each** (39 + 39). It would have fired for no reason, and the number looked entirely
plausible — which is what made it dangerous.

Every rule in `health.d-amdgpu.conf` names its dimension explicitly. If you add rules,
do the same.

## Notifications

Alerts are visible in the dashboard and in `/var/log/netdata/health.log`. They do **not**
leave the machine unless you configure a channel in
`/etc/netdata/health_alarm_notify.conf` — Slack/Discord webhook, ntfy, Telegram or an
external SMTP relay. Without that, a cooling-fault alert is only visible if you're looking.
