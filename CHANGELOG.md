# Changelog

## v0.1.0 — 2026-10-06

- Preserve the hardware-tested A51 UH-to-KVM handoff and CPU power transition restoration.
- Include the native exception gateway, successful-init publisher, fixed-VBAR forwarding and real Hyp initialization patch.
- Fix the architectural timer's unused IRQ reservation in Samsung's clocksource-only mode.
- Publish the exact kernel configuration, pinned source and legacy toolchain provenance.
- Add standalone KVM instruction and VGICv2/PPI27 timer probes.
- Provide a QEMU EL2 harness, firmware guards, guarded local image preparation and offline CI.
- Document the verified original-UH Download restore and the padded-container `SECURE CHECK FAIL (UH)` failure.
- Publish sanitized handset evidence, English/Russian READMEs and recovery instructions.
