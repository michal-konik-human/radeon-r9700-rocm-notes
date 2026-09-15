# The power cap has a firmware floor — 210 W, not whatever you planned

**The plan.** Cap each card at 200 W. Costs a few percent of throughput, saves 400 W across
four cards. Sensible.

**Reality.**

```
$ amd-smi static -g 0 | grep -A3 PPT0
    PPT0:
        MAX_POWER_LIMIT: 300 W
        MIN_POWER_LIMIT: 210 W
        SOCKET_POWER_LIMIT: 300 W
```

**`MIN_POWER_LIMIT: 210 W`.** 200 W is not settable — `amd-smi` rejects it outright. Four
cards cannot go below **840 W** combined, not the 800 W the plan assumed.

```bash
sudo amd-smi set -g 0 --power-cap 210     # works
sudo amd-smi set -g 0 --power-cap 200     # rejected
```

**Why it matters more than 40 W of arithmetic.** Measurement showed both a dense and an MoE
model pushing this card to **288–300 W sustained**, with junction temperature still climbing
past 83 °C at the 60-second mark ([thermals](../hardware/thermals.md)). Capping isn't an
optimisation here, it's what makes a four-card box thermally plausible — and the floor is
higher than you'd plan for.

**Also:** the same model measured at 300 W and at 210 W are **two different measurements**.
Record the cap with every number, or the results aren't comparable. There's a config for
measuring the cost directly in the companion harness repo (`configs/power-cap.json`).
