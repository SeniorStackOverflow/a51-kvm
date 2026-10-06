# Native Docker kernel profile

The Docker profile adds native cgroups, namespaces, OverlayFS, veth, bridge,
netfilter and seccomp to the working A51 KVM kernel. Its features are built into
the kernel, rather than supplied by a VM or an emulation layer. The tested target
is **SM-A515F, Android 11, A515FXXU5EUJ4**.

`kernel/docker.config` is the full configuration. `kernel/docker.features.json`
lists 81 required built-in settings, including the existing KVM/UH requirements.
The default `kvm` profile retains the original configuration and patch.

## Build

Use the toolchains and environment in [build.md](build.md), with a fresh source
and output directory:

```sh
python3 tools/prepare_kernel.py build/docker-src --profile docker
export KERNEL_PROFILE=docker
export KERNEL_SRC="$PWD/build/docker-src"
export KERNEL_OUT="$PWD/build/docker-out"
# Set TOOLCHAINS as described in build.md.
bash scripts/build-kernel.sh
python3 tools/boot_image.py private/original-boot.img build/docker-out/arch/arm64/boot/Image \
  --system-map build/docker-out/System.map --out private/boot-docker.img
```

The kernel remains paired with the same audited KVM UH image. Preserve your
working boot rollback and follow [install.md](install.md). This profile adds
`CFQ_GROUP_IOSCHED` and `BLK_DEV_THROTTLING` so blkio exposes both weight and
throttle controls.

## Android cpuset compatibility

Android mounts its existing cpuset hierarchy with `noprefix`, exposing `cpus`
and `mems`. Docker's CPU availability check expects `cpuset.cpus` and
`cpuset.mems`. `kernel/docker-cpuset.patch` adds the optional
`CONFIG_A51_CPUSET_PREFIX_ALIAS`: both names invoke the same native controller
callbacks. Aliases are created and removed with each cgroup, only for legacy
cpuset mounts using `noprefix`. Normal mounts and cgroup v2 are unchanged.

Hardware validation checks writes through both names, nested cgroup creation,
Docker's `--cpuset-cpus 0,1`, and CPU quota. Android keeps its original names
and task assignments. The profile does not remount or rename Android's cpuset.

## Android internal-error warning

This firmware's FCM4 matrix requires `CONFIG_SYSVIPC=n`; native Docker IPC
requires `CONFIG_SYSVIPC=y`. Android reported a VINTF kernel-contract mismatch
after the first Docker boot. The fingerprints matched; the kernel configuration
was the incompatible part.

Before installing the correction, save your original matrix locally:

```sh
adb -s "$SERIAL" pull /system/etc/vintf/compatibility_matrix.4.xml private/
python3 tools/prepare_docker_vintf.py private/compatibility_matrix.4.xml \
  --out build/docker-vintf-module
adb -s "$SERIAL" push build/docker-vintf-module /data/local/tmp/a51-docker-vintf
adb -s "$SERIAL" shell su -c 'test ! -e /data/adb/modules/a51_docker_vintf && cp -a /data/local/tmp/a51-docker-vintf /data/adb/modules/a51_docker_vintf && chmod 755 /data/adb/modules/a51_docker_vintf/post-fs-data.sh'
```

The generator requires the audited original XML hash and changes exactly one
tristate value. The Magisk module bind-mounts that matrix only on the Docker
kernel, exact firmware and original matrix hash. Removing/disabling the module
restores the original contract on reboot; booting the baseline KVM kernel skips
the correction. The system partition is unchanged. This is a custom kernel
contract, not a claim of stock Android VTS certification.

The native Android verifier returned `VINTF_RESULT=0` after reboot, with no repeat
compatibility-warning entries. Its reflection-based probe is in
`probes/docker/VintfProbe.java` and can be compiled to dex using JDK and Android
D8, then run as root with `app_process`. SELinux remained `Enforcing`.

## Reproduce the isolated native-container test

The tested userspace is the official static **Docker 27.5.1 aarch64** archive
and official **runc 1.3.6 arm64** binary. Download them from
[Docker](https://download.docker.com/linux/static/stable/aarch64/docker-27.5.1.tgz)
and [runc](https://github.com/opencontainers/runc/releases/tag/v1.3.6).
The archive SHA256 is
`e6b53725a73763ab3f988c73f8772eaed429754c1a579db5ff11f21990fd1817`;
the runc binary SHA256 is
`6be27a061ef89bb14c6cb495405bba80f46cea213b8f79378a6086b1bac6b747`.
Extract the archive and replace its `runc` with the verified 1.3.6 binary.
The official runc 1.5.2 binary crashed in `libpathrs` on this handset; that
version was not used for the successful result.

```sh
make docker-probes
adb -s "$SERIAL" push docker /data/local/tmp/codex-a51-docker-bin
adb -s "$SERIAL" push build/docker-daemon-launcher /data/local/tmp/docker-daemon-launcher
adb -s "$SERIAL" push scripts/start-docker-test.sh /data/local/tmp/start-docker-test.sh
adb -s "$SERIAL" shell su -c 'chmod 755 /data/local/tmp/codex-a51-docker-bin/* /data/local/tmp/docker-daemon-launcher'
```

Create only the following new **regular file**, inside encrypted Android `/data`:

```sh
adb -s "$SERIAL" shell su -c 'test ! -e /data/local/tmp/codex-a51-docker-storage.ext4 && dd if=/dev/zero of=/data/local/tmp/codex-a51-docker-storage.ext4 bs=1048576 count=256 && chmod 600 /data/local/tmp/codex-a51-docker-storage.ext4 && mke2fs -t ext4 -F -O ^64bit,^metadata_csum /data/local/tmp/codex-a51-docker-storage.ext4'
adb -s "$SERIAL" shell su -c 'sh /data/local/tmp/start-docker-test.sh'
```

Inspect `/data/local/tmp/codex-a51-dockerd.log` and wait for API readiness before
running the validator. The launcher uses native `unshare`, mounts and `chroot`
to provide writable `/run` and a Linux directory layout for containerd. It
mounts ext4 from the dedicated file via a free loop device. Android's encrypted
F2FS directories cannot serve directly as OverlayFS upperdirs in this 4.14
kernel; ext4 supplies a supported persistent upperdir while the backing file
stays within encrypted `/data`.

The daemon has private mount and network namespaces. Existing Android cgroup
controllers are bound into its view; Docker adds its own subgroups. Android
tasks and its firewall stay in their existing namespaces. The test network
has a bridge and containers, with **no uplink to Android's internet connection**.
This launcher is a reproducible test setup, not a boot service or a production
network deployment.

```sh
python3 tools/validate_docker_device.py --serial "$SERIAL"
python3 tools/validate_device.py --serial "$SERIAL" --out build/docker-kvm.json
```

The Docker validator tests native namespace creation, OverlayFS copy-up, pids
enforcement, blkio control files, explicit seccomp syscall filtering, veth and
bridge setup, IPv4/IPv6 NAT rule insertion and per-bridge netfilter attributes.
It then imports a locally built static arm64 program and runs an actual Docker
container with PID1, default seccomp, writable overlay2, SYSV shared memory,
CPU affinity/quota, 32-task enforcement and a UDP round trip through veth/bridge.
Memory and memory+swap are both limited to 64 MiB, so only the over-limit child
is killed and Android's zRAM cannot absorb the test allocation.

Stop the test daemon through the PID in its own `dockerd.pid`, after verifying
the process command line uses this test socket. The launcher has no autostart.
Results and exact reference hashes are in [docker-summary.json](../evidence/docker-summary.json).

Moby 27.5.1's official `contrib/check-config.sh` reported every generally
necessary feature enabled. Its combined exit code was 1 because optional
features remain absent, including HugeTLB cgroups, the net_cls traffic classifier,
AppArmor, bridge VLAN filtering and alternative Btrfs/ZFS storage drivers.
Those results are recorded alongside the actual successful overlay2/container
tests; they do not imply every Docker plugin or deployment mode has been tested.
