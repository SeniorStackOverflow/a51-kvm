# Contributing

Start with `make check`. Keep changes to firmware layout explicit and backed by an original-image hash, disassembly review and a verified recovery path. Please do not broaden firmware/model acceptance without hardware evidence.

For a kernel change, report the exact base commit, configuration, compiler version and patch application result. For device testing, use `tools/validate_device.py`, describe what was tested before and after reboot, and distinguish minimal guests from a full guest OS. Remove device identifiers and unrelated logs before attaching evidence.

Do not upload firmware dumps, personal ramdisks, device serials, keys or credentials. Functional tests on one handset do not establish compatibility with another firmware or model. Keep synthetic QEMU checks and hardware results labeled separately.
