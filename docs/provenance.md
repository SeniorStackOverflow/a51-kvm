# Source provenance and attribution

## Kernel

Linux and Samsung kernel code retain their original authors and license notices. The published patch applies to Samsung's A515FXXU5EUJ4 4.14.113 source as mirrored by [UtsavBalar1231/kernel_samsung_universal9611](https://github.com/UtsavBalar1231/kernel_samsung_universal9611), commit [`3e3749345369b80e6ea3614fcb06081254faefa8`](https://github.com/UtsavBalar1231/kernel_samsung_universal9611/commit/3e3749345369b80e6ea3614fcb06081254faefa8).

The repository publishes the patch and complete tested configuration, with scripts to fetch and build the pinned corresponding source. It does not redistribute a complete kernel binary or the upstream source tree. New gateway, probe, tool and documentation work is published under **GPL-2.0-only**. Existing notices are preserved; see [LICENSE](../LICENSE).

## Prior research

[sleirsgoevy/exynos-kvm-patch](https://github.com/sleirsgoevy/exynos-kvm-patch) is prior Exynos KVM research. Its early EL2 bootstrap and firmware vector considerations informed investigation. The tested A51 firmware required a native-UH HVC gateway, native-context snapshots and CPU_PM restoration instead of the older late-SMC approach. Do not assume a patch for another Exynos model is interchangeable.

## Tested kernel toolchains

| Dependency | Pinned source / artifact | SHA-256 |
| --- | --- | --- |
| Android Clang 4639204, version 6.0.1 | [Android archive](https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/c9cc9e7d29b8970d8ddb734c88fb62d01e0b7279/clang-4639204.tar.gz), commit `c9cc9e7d29b8970d8ddb734c88fb62d01e0b7279` | `b238b6e31f42cba3e85c5fd57b3e0913a1fa67a3338bde8a806274ed1132c9e2` |
| Android aarch64 GCC 4.9 | [Android archive](https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/+archive/961622e926a1b21382dba4dd9fe0e5fb3ee5ab7c.tar.gz), commit `961622e926a1b21382dba4dd9fe0e5fb3ee5ab7c` | `be057c809355f940b0802407a2ac9b7d7ea8cc43f9da6b92b8e47579c6d97a7c` |
| Ubuntu libtinfo5 compatibility library | [Ubuntu package](https://archive.ubuntu.com/ubuntu/pool/universe/n/ncurses/libtinfo5_6.3-2ubuntu0.3_amd64.deb) | `4df4288404108f1a156d014e8764a064e977e34e6d44931ab60451694c03c90d` |

These hashes were measured from the archives used locally. Download availability can change. Substitute compiler versions are not validated by this experiment. GNU cross assembler/linker, GCC and QEMU build the small independent probes and offline harness; CI uses Ubuntu packages for those.

The original local boot packing used [Magisk's magiskboot](https://github.com/topjohnwu/Magisk). The public project includes a restricted Python packer for this exact uncompressed boot-v2 layout, checked against the local working image; it needs no redistributed magiskboot binary.

## Firmware and data

Samsung UH and boot/recovery dumps are proprietary or may contain user-specific content. They are not included. UH is patched only from a user-supplied original with the exact audited hash; the project's license does not grant rights to Samsung firmware. The signed original-UH restore container is generated locally, preserving its footer and removing only zero partition padding.

Published handset evidence includes model, firmware, kernel version, benchmark-free functional results and hashes. Device serials, DID, chip identifiers, boot UUID values, personal paths and unrelated Android logs are excluded.
