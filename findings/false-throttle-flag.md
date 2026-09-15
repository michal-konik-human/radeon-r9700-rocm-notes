# `THROTTLE_STATUS: THROTTLED` at idle is meaningless on this card

**Observation.** `amd-smi` reports the card as `THROTTLED` while it is drawing **16 W** at
**33 °C** and doing nothing. The flag flips between `THROTTLED` and `UNTHROTTLED` with no
change in load, temperature or power.

Verified repeatedly at idle across many samples.

**Consequence.** If you build an alert on `throttle_status`, you have built a false-alarm
generator. It will fire constantly on a cold, idle card.

**What I did.** Chart the flag for visibility, **but no alert on it.** The alerts that
matter are on the physical quantities instead — junction temperature, VRAM temperature, and
a derived cooling-fault metric.

**If you inherit this setup:** don't add an alert on that field without first verifying the
firmware behaviour hasn't changed. It's an easy "obvious improvement" that makes the
monitoring worse.
