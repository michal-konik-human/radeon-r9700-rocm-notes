# netdata silently refuses to monitor a discrete AMD GPU

**The worst kind of monitoring failure: the one that looks like success.**

**Symptom.** Install netdata, it auto-detects your GPUs and draws `amdgpu.*` charts.
Dashboard looks great. Then check *which* charts exist:

- integrated GPU (`card2`): temperature, power, clocks, utilisation, memory — **complete**
- Radeon AI PRO R9700 (`card1`): **memory charts only.** No temperature. No power. No fan.

The only component in the machine that can physically burn was unmonitored, right next to
a healthy-looking temperature graph for a harmless iGPU.

**Cause.** Same as [`rocm-smi shows N/A`](rocm-smi-shows-na.md): the built-in collector
reads sysfs hwmon, the runtime-suspended card returns `EBUSY`, and **netdata does not
report an error — it simply doesn't create the chart.** Nothing in the logs, nothing on the
dashboard, no gap to notice. The chart just isn't there.

**Fix.** Read GPU telemetry through `amd-smi` instead. There's a working collector in
[`../monitoring/`](../monitoring/) that does this, plus 22 alert rules.

Then disable the built-in one so it stops drawing misleading partial charts:

```
# /etc/netdata/netdata.conf
[plugin:proc]
    /sys/class/drm = no
```

**Generalisable lesson:** when you install monitoring, don't verify that charts *appeared* —
verify that the charts you actually need appeared, for the device you actually care about.
"It auto-detected everything" is not a check.
