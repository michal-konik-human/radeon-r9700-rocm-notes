# Installing ROCm on a very new kernel — and skipping DKMS on purpose

**Setup:** Ubuntu 24.04.5, kernel 7.0, Radeon AI PRO R9700 (`gfx1201`), ROCm 7.2.4.

## The deliberate deviation

Guides tell you to install with `--usecase=rocm,graphics` and let DKMS build AMD's
`amdgpu` module. I installed:

```bash
sudo amdgpu-install --usecase=rocm --no-dkms
```

**Why `--no-dkms`.** Kernel 7.0 already ships an **in-tree `amdgpu`** with `gfx1201`
support (RDNA4 landed in-tree around 6.12). DKMS would replace that working driver with
AMD's out-of-tree build, which may not compile against a kernel this new. Skipping DKMS
**removes** the failure mode rather than solving it.

Verified the in-tree driver is what's bound:

```bash
$ lspci -nnk -s 03:00.0 | grep 'Kernel driver'
	Kernel driver in use: amdgpu
```

**Why no `graphics`.** That sub-usecase replaces the graphics stack that the desktop runs
on. For inference (llama.cpp, vLLM) it isn't needed, and on a headless-ish compute box
it's risk without benefit.

**If a card doesn't show up after assembly**, this is the first thing to reverse: install
with `--usecase=rocm,graphics` (with DKMS) on an older kernel.

## A package in the official procedure that does not exist

The documented steps include installing `linux-modules-extra-$(uname -r)`.

**For this kernel that package does not exist.** And because it sits on the same
`apt install` line as everything else, it takes the **entire command** down with it:

```
E: Unable to locate package linux-modules-extra-7.0.0-31-generic
```

The module it was meant to provide is already in the kernel image:

```bash
find /lib/modules/$(uname -r) -name 'amdgpu.ko*'
```

Read the error, not the guide.

## What I verified, rather than assuming it worked

"The packages installed" is not the same as "ROCm works". What I actually checked:

| Check | Result |
|---|---|
| Install log errors | 0 |
| Version | `/opt/rocm/.info/version` → 7.2.4, HIP 7.2.53211 |
| Kernel driver | `amdgpu`, in-tree, no DKMS |
| Compiler knows RDNA4 | `llc -march=amdgcn -mcpu=help` lists `gfx1201` |
| **A real compute kernel** | Own HIP kernel compiled with `--offload-arch=gfx1201` and **executed**: vector add over 2²⁴ elements, `bad=0` |
| Tuned libraries present | rocBLAS: 56 `gfx1201` files; hipBLASLt: 297 |

That last-but-one row is the one that matters. Compiling and *running* a kernel proves the
compiler, runtime, kernel launch and memory copies all work — package presence proves none
of it.

## Two more small things

- **User must be in `render` and `video` groups**, or `/dev/kfd` is inaccessible and ROCm
  fails from a normal user account.
- **`sensors-detect` finding "no sensors" is expected** on some boards — Super-I/O may be
  unreadable while `k10temp` and PCI-attached sensors work fine. Don't chase it.
