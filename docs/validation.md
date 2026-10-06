# What was measured

The handset audit completed on **2026-10-06 at 06:58 UTC**. The firmware was A515FXXU5EUJ4, Android 11; the running kernel was `4.14.113-22755563`, build #7. Published JSON files are curated from local logs. Device serials, boot UUID values, full interrupt tables and unrelated Android logs were removed.

## Hardware evidence

| Evidence | What it establishes |
| --- | --- |
| [hardware-summary.json](../evidence/hardware-summary.json) | Final boot/root/KVM state, hashes, idle counters and validation scope |
| [guest-all-cpus.json](../evidence/guest-all-cpus.json) | 12 successful create/run/destroy cycles covering CPU0–7 |
| [guest-after-reboot.json](../evidence/guest-after-reboot.json) | Actual guest instructions execute after a normal reboot |
| [timer-before-reboot.json](../evidence/timer-before-reboot.json) | Guest timer IRQ on CPU0 and CPU4 |
| [timer-after-reboot.json](../evidence/timer-after-reboot.json) | The same timer checks after reboot |
| [original-uh-rollback.json](../evidence/original-uh-rollback.json) | Signed canonical original-UH Download restore, Android boot and partition hash |
| [kvm-boot-excerpt.txt](../evidence/kvm-boot-excerpt.txt) | All eight EL2 takeovers and successful KVM Hyp initialization |
| [publication-device.json](../evidence/publication-device.json) | Probes rebuilt from the public sources and checked again on the same handset |

### Execution probe

`probes/guest.c` opens `/dev/kvm`, checks API 12, creates a VM and vCPU, initializes ARM64 registers and installs 64 KiB of guest memory. Four guest instructions repeatedly write **42** to unmapped guest physical address `0x100000`. A successful `KVM_RUN` produces `KVM_EXIT_MMIO`; the probe checks address, width, direction and data. This proves guest instruction execution, beyond merely finding a device node.

Its `hold` mode keeps the same VM/vCPU alive, sleeps two seconds between runs, and migrates across CPU0–7, then CPU0 and CPU4. All ten runs passed on the phone. The observed `cpuidle/state1/usage` deltas were **3719, 3458, 4172, 4718, 2434, 2076, 1983, 1292** for CPU0–7 during the recorded audit. These show deep-idle activity during the test; they do not establish suspend-to-RAM or long-term stability.

### Virtual timer probe

`probes/timer.c` creates VGICv2 and loads `timer-guest.S`. The guest configures its GIC CPU interface, enables IRQs, programs the virtual timer for roughly 10 ms at the observed **26 MHz** counter frequency, and busy-waits. Its IRQ handler reads GIC IAR and reports the interrupt through MMIO. The probe requires **PPI27**. CPU0 and CPU4 passed before and after the normal reboot.

The host's `/proc/interrupts` guest-timer counter remained zero. With direct physical-IRQ mapping into VGIC, that counter is not a required success condition. The guest's actual IRQ-handler report is the evidence of timer delivery. No full guest OS was involved.

## Offline checks and CI

`make check` builds the exact gateway sources and links them into a synthetic firmware environment. QEMU starts at EL3, sets up native EL2 MMU, stage-2 translation, WXN, a read-only code mapping and writable stacks, then exercises four takeover/restore cycles. The physical KVM initialization entry starts unmapped by native EL2. The harness checks native/KVM vector routing and preservation of x16, x17 and x19.

The real and synthetic gateway bytes must match except for the 16 original-native-handler branch relocations. Host-side tests check rejection of foreign images and AArch64 branch encoding boundaries. A separate CI job fetches the exact upstream kernel commit and checks application of the published patch.

CI does **not** build the full legacy Samsung kernel, boot a handset or validate a Samsung firmware image. Samsung firmware is not uploaded as a CI fixture.

## Reference hashes

| Artifact | SHA-256 |
| --- | --- |
| Hardware-tested raw kernel `Image` | `4fac1f274ae0303cbbd444f1f45ed28269625bfd8db5ebe9f6efeb0a305de20c` |
| Hardware-tested full boot partition | `97e486fb4f1ce8e5f420231a4e48369228b04398f022b1d3079bea3cdc5a7727` |
| Modified full UH partition | `d05d6cdfc282c953d3b048c42fdc77279c2f996a2ed76e36c87fd4c9ff21273a` |
| Original full UH partition | `ebdf765c5087cd1953b2e4a11878a65611b2705618c0a31ed05b1419c4571574` |
| Original signed UH download file | `9006b493765b1c57214e5b1f9370066a7e86ca2f620961c53f030edb230b922f` |
| Tested kernel config | `7ddc76d6eb32ea8fe67c53a5e3fb922ed4558c5d5b06324b87bde363811aa59c` |

The UH packer reproduces the exact modified-UH hash. The boot and kernel hashes identify the original local experiment: build timestamps, hostnames and user-supplied ramdisks can change them. Full partition images are not release assets.

## Remaining work

- Boot a full Linux guest and test sustained I/O.
- Validate multi-vCPU guests and simultaneous VMs.
- Measure longer load/idle sessions and system suspend/resume.
- Audit guest isolation and the firmware handoff interface for security.
- Port only after auditing another firmware's layout and recovery path.
