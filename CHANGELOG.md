# Changelog

## Unreleased

- Add the native Docker kernel profile with cgroups, namespaces, OverlayFS, veth, bridge, netfilter and seccomp, preserving the working KVM backend ([#1](https://github.com/SeniorStackOverflow/a51-kvm/pull/1)).
- Add cpuset prefix aliases for Docker while preserving Android's existing cpuset names and task assignments.
- Correct the Docker kernel's Android VINTF contract through a guarded Magisk module, resolving the internal-error warning with SELinux Enforcing.
- Add the private Docker launcher with ext4-backed overlay2 storage inside encrypted Android data; validate container CPU, memory, process and IPC controls.
- Connect Docker's private network namespace to Android's IPv4 internet route with a supervised veth uplink, scoped NAT and forwarding rules ([#2](https://github.com/SeniorStackOverflow/a51-kvm/pull/2)).
- Configure container DNS and use Android's system CA directories for verified registry HTTPS; support internet access on default and user-created bridges.
- Recover connectivity after route loss and remove the uplink and owned rules after daemon exit or explicit stop, restoring Android's original firewall, policy rules and forwarding state. Retain the offline `--isolated` mode and internal-network isolation.
- Add internet validation, ShellCheck in offline CI, updated setup instructions and [sanitized hardware evidence](evidence/docker-internet-summary.json). Verify registry downloads, DNS, HTTP(S), rejection of an untrusted certificate, package downloads and network cleanup on the A51 over Wi-Fi.
- Repeat KVM execution checks on all eight CPUs, held-vCPU idle/migration and VGICv2/PPI27 timer checks on CPU0 and CPU4 after enabling Docker internet access.

## v0.1.0 — 2026-10-06

- Preserve the hardware-tested A51 UH-to-KVM handoff and CPU power transition restoration.
- Include the native exception gateway, successful-init publisher, fixed-VBAR forwarding and real Hyp initialization patch.
- Fix the architectural timer's unused IRQ reservation in Samsung's clocksource-only mode.
- Publish the exact kernel configuration, pinned source and legacy toolchain provenance.
- Add standalone KVM instruction and VGICv2/PPI27 timer probes.
- Provide a QEMU EL2 harness, firmware guards, guarded local image preparation and offline CI.
- Document the verified original-UH Download restore and the padded-container `SECURE CHECK FAIL (UH)` failure.
- Publish sanitized handset evidence, English/Russian READMEs and recovery instructions.
