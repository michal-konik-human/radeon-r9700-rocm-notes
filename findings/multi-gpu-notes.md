# Multi-GPU notes — collected, not yet measured

**Status: I have one card installed.** Everything below is from documentation, AMD issue
trackers and other people's reports. It's recorded here so it's ready when the remaining
cards arrive — and clearly marked as unverified by me.

If you have measured any of this, corrections are very welcome.

---

## There is no XGMI / Infinity Fabric on this card

AMD confirmed this directly for the R9700. **All collective traffic crosses plain PCIe.**
There is no high-speed inter-GPU link to fall back on, which shapes everything below.

One widely-cited "tensor parallel is broken on R9700" result appears to have been a
KVM/VFIO passthrough artifact rather than a hardware limit — worth knowing before you
repeat that claim.

## Two environment variables appear to be mandatory

**`NCCL_PROTO=Simple`** — without it, tensor-parallel with TP≥2 deadlocks on the first
all-reduce: both cards pin at 100 % utilisation with zero progress. Root cause reported as
RCCL's low-latency protocol path for gfx12 never receiving the RDNA4 memory-ordering fixes,
while LL is silently selected for small messages. Reported as patched upstream in mid-2026,
but set the variable unless you've verified your specific build.

**`NCCL_P2P_DISABLE=1`** — on a **four-card** box, direct P2P is documented to cause random
**whole-host hangs** under both llama.cpp and vLLM. `hipDeviceCanAccessPeer` returns 0
between cards on different root complexes anyway, so every inter-GPU byte is host-staged
regardless. Because traffic is host-staged, each GPU's own link is traversed twice per
exchange — which is why wider links on some cards still help.

Both are set in the multi-GPU template config in the companion harness repo.

## Prefer tensor-parallel over pipeline-parallel

Reported as the opposite of the usual advice for PCIe-only rigs: TP=4 is confirmed working,
while **pipeline-parallel "works but crashes under load"** on this hardware.

## For llama.cpp specifically

- **ROCm/HIP beats Vulkan for multi-GPU**, inverting the single-GPU result. Vulkan is
  reportedly ~35 % faster on a single card for small/MoE decode, but its multi-GPU split
  modes degrade badly, while HIP holds up from `-sm none` to `-sm layer`.
- `--split-mode row` is deprecated; use `layer`.
- `-ts` takes **ratios** (`1,1,1,1`), not gigabytes.

## Expect the platform to shift under you

Each added card renumbers the PCI bus — see [PCI renumbering](pci-renumbering.md) — and can
reorder compute device indices ([device index order](device-index-order.md)). Re-verify both
after every card, and re-measure the first card: it drops from x16 to x8 once the second
slot is populated, and you want that cost **measured rather than assumed**.
