---
name: Reproduction or bug report
about: Report a build, offline test, or hardware validation problem
title: ''
labels: ''
assignees: ''
---

**Device and firmware**
Model, Android version, firmware build, bootloader revision. Omit serials and other unique device identifiers.

**Source and tools**
Repository revision, kernel base commit, compiler versions, host OS.

**Failure**
Command, expected result, actual result and a minimal sanitized log excerpt.

**Validation scope**
Offline QEMU / minimal hardware guest / full guest OS. Does `make check` pass?

**Recovery state, if applicable**
Which original images were saved and whether recovery / Download Mode remains accessible. Do not attach partition images or personal ramdisks.
