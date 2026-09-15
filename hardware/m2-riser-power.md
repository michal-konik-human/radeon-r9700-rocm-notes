# M.2→PCIe adapters supply no slot power

Short, but it's the kind of detail that destroys hardware.

If you plan to hang GPUs off M.2 slots (see [lane plan](pcie-lane-plan.md)):

**The adapter provides no power to the card.** An M.2 slot cannot deliver the 75 W a PCIe
slot normally supplies. The adapter needs **its own 6/8-pin PCIe 12 V feed** from the PSU.

**Never power such an adapter from SATA.** SATA-powered PCIe adapters are a documented
cause of fires — a SATA connector and its wiring are not rated for the current a GPU-adjacent
rail draws, and the failure mode is thermal, not a clean shutdown.

Cheap part, expensive failure mode. Check this at purchase time, not at assembly time.

## Related power notes for a multi-GPU build

- **Check whether your PSU starts in multi-rail mode.** Mine (be quiet! Dark Power Pro 13)
  boots with six independent 12 V rails, each with its own over-current protection. Under
  four GPUs a transient on one rail trips the protection and drops the machine — mid-run,
  with a filesystem mounted. It has to be switched to single-rail with the supplied jumper.
  **This is not visible from software**; it's a physical check.
- **12V-2×6 connectors must be fully seated.** Incomplete insertion raises contact
  resistance, which heats locally and can destroy the connector. Keep ~35 mm of straight
  cable before the first bend, and inspect for a gap after connecting.
- **Budget the real number.** Both a dense and an MoE model pushed a single card to
  288–300 W sustained ([thermals](thermals.md)), and the
  [power cap floor is 210 W](../findings/power-cap-floor.md) — so four capped cards still
  means ≥840 W of GPU alone.
