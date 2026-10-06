# EL2 ownership, handoff and restoration

## The initial state

On the tested firmware Linux enters EL1 while native Samsung UH owns EL2. The observed native context included:

| Register / region | Value |
| --- | --- |
| `HCR_EL2` | `0x84000003` (RW, TVM, VM, SWIO) |
| `SCTLR_EL2` | `0x30cd1835` (MMU, caches, WXN enabled) |
| `VBAR_EL2` | `0x8701c000` |
| `TTBR0_EL2` | `0x87022000` |
| `TCR_EL2` | `0x80823f18` |
| `MAIR_EL2` | `0x01090825004400ff` |
| Native SP on CPU n | `0x87048000 + n * 0x2000` |

An older Exynos technique using a late `SMC 0xc2000400` returned `-1` here. Instead, the gateway intercepts native UH's existing HVC exception path.

## Audited layout

These are physical addresses for **A515FXXU5EUJ4 only**. An address in the ELF payload maps to file offset `0x1000 + PA - 0x87000000` inside the GREENTEA container.

| Region | Purpose |
| --- | --- |
| `0x870010a8` | Original `BL` to native init; changed to call our publisher wrapper |
| `0x870129c0` | Native UH initialization, kept byte-for-byte |
| `0x8701b190` | 1,132-byte gateway in audited NOP padding |
| `0x8701b700` | 44-byte successful-init publisher |
| `0x8701b780` | 16-byte marker `KVMEL2HAND_V1\0\0\0` |
| `0x8701c000 + slot * 128` | First branch of each of 16 native vector slots |
| `0x87045700..0x87045f00` | Eight 256-byte per-CPU native-context records |
| `0x87045610` | End of the native ELF BSS |
| `0x87046000` | Beginning of native stack allocation |
| `0x87100000` | Shared UH log, readable from EL1 |

The native entry zeros the BSS page; the context records fit between the existing BSS and stack. Padding was inspected for references during development. Exact input and output hashes are the packer's strongest guard: it never ports these offsets automatically to another firmware.

## Advertise through shared memory

The publisher calls native init unchanged and publishes the marker into the shared log only when init returns success. It preserves its callee-saved register and return address. Linux probes the shared log, rather than UH private text. An earlier EL1 read of the private text triggered **`TIMA_RKP_VMM_PANIC`**, even with Linux `CONFIG_UH_RKP` disabled.

`is_hyp_mode_available()` becomes true through this backend only after the exact shared marker is detected. Ordinary ARM KVM paths retain their existing behavior when the backend is inactive.

## HVC interface

Call `HVC #0` with **x0 = `0xc3004b56`**, x1 = command. Success returns **w0 = `0xc0de4b56`**; rejection returns -1. x0–x18 may be clobbered; x19–x30 are preserved. The custom handler only accepts the AArch64 lower-EL synchronous HVC vector. After takeover, a nonzero `VTTBR_EL2` routes guest calls into KVM instead of this host control interface.

| Command | Inputs / result |
| --- | --- |
| 0 | Diagnostic: CurrentEL, HCR, MPIDR, SCTLR, VBAR |
| 1 | Translation diagnostic: TTBR0, TCR, MAIR, native SP |
| 2 | x2: physical Hyp init entry; x3: Hyp PGD PA; x4: Hyp stack VA; x5: fixed UH VBAR; x6: per-CPU KVM vector prefix |
| 3 | Restore the native EL2 snapshot and disable forwarding |

Each record stores 16 EL2 registers, the native SP and the KVM forwarding pointer. CPU indexing uses MPIDR affinity fields for the four CPUs in each of the two clusters.

## Enter real KVM

Command 2 checks native TTBR0, alignment and forwarding state, snapshots the native context and cleans the metadata to the point of coherency. It disables native stage-2, clears native traps, enables host timer access and turns off the old EL2 MMU before jumping to the physical kernel Hyp initialization entry.

`__kvm_exynos_hyp_init` lives in the kernel's real Hyp idmap code. It installs KVM's page tables, memory attributes and stack, keeps the firmware VBAR and returns to the original host HVC by `ERET`. Linux then initializes `TPIDR_EL2` with the actual per-CPU offset before use of KVM's per-CPU state.

KVM maps the UH gateway pages RX and the context page RW in its private Hyp address space. A51 uses a non-extended Hyp idmap; the added identity-mapping helper refuses an extended idmap rather than silently constructing an unsupported layout.

## Preserve the firmware VBAR

EL3 firmware can restore its fixed UH VBAR during CPU power transitions. Keeping `VBAR_EL2 = 0x8701c000` avoids relying on a Linux VBAR value surviving those transitions.

Each UH vector enters a wrapper that saves x16/x17 and records the slot. Before takeover it restores the scratch registers and branches to the unchanged native handler. After takeover it selects the per-CPU KVM forwarding table. Each 2 KiB forwarding table restores x16/x17 and branches into the real KVM vector for that CPU, including its selected branch-predictor mitigation vector.

Command 3 clears the forwarding pointer before changing MMU state, cleans the metadata, restores the native registers and SP, invalidates old EL2 translations, then re-enables native MMU and returns to EL1. The backend replaces KVM's per-CPU Hyp init/reset operations, including CPU_PM paths. The synthetic harness checks four transitions; the phone test exercises the same VM across observed CPU deep-idle entries and migrations.

## Fix the timer IRQ ownership

The first successful EL2 handoff still failed to create `/dev/kvm`:

```text
genirq: Flags mismatch irq 4 (kvm guest timer) vs (arch_timer)
kvm_arch_timer: can't request interrupt 4 (-16)
```

Samsung's device tree sets `use-clocksource-only`. The architectural timer driver skips clock-event setup and IRQ enablement but previously still requested its unused virtual timer PPI. The host's clock events are supplied by `mct_tick0..7`.

The patch skips IRQ reservation in the counter-only mode, retaining counter registration, user-access configuration, errata and CPU_PM/hotplug callbacks. Error cleanup frees the IRQ only if it was requested. KVM can then own PPI27 and deliver a real virtual timer interrupt through VGICv2.

## Boundaries

The implementation is deliberately A51-specific. The published patch matches the tested sources, including its diagnostic observer. It is not a general backend for every configuration of this kernel tree. The HVC interface and guest-call guard have functional tests; this project makes no claim of a hardened, multi-tenant hypervisor security audit. Device firmware protection and trust assumptions differ once native UH yields EL2 to Linux.
