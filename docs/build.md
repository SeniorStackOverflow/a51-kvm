# Build guide

The handset result used Linux 4.14.113, Samsung's A515FXXU5EUJ4 source, Android Clang 6.0.1 and the Android GCC 4.9 cross toolchain. Use Linux or WSL Ubuntu on an x86-64 host. `make check` needs only modern GNU cross tools; the Samsung kernel needs the legacy toolchains below.

## 1. Build and test our code

```sh
sudo apt-get update
sudo apt-get install -y make python3 git binutils-aarch64-linux-gnu gcc-aarch64-linux-gnu qemu-system-arm \
  gcc-11 g++-11 bc bison flex libssl-dev libelf-dev curl xz-utils
make check
```

Outputs are in `build/`. QEMU uses a synthetic EL3/native-UH environment with MMU, stage-2 and WXN enabled. Its test executable is not a phone image.

## 2. Fetch the pinned kernel

```sh
python3 tools/prepare_kernel.py build/kernel-src
```

Base: [`3e3749345369b80e6ea3614fcb06081254faefa8`](https://github.com/UtsavBalar1231/kernel_samsung_universal9611/commit/3e3749345369b80e6ea3614fcb06081254faefa8). The script uses a shallow fetch, verifies HEAD, normalizes CRLF in the patch targets, checks the patch, then applies it. The compact published patch reproduces all modified files from the hardware-tested worktree after newline normalization. Do not apply it to the mirror's latest branch.

The full tested configuration is `kernel/a51.config`. Core settings include `CONFIG_KVM=y`, `CONFIG_UH=y`, `CONFIG_SOC_EXYNOS9610=y`, branch predictor hardening enabled, and `CONFIG_UH_RKP` disabled. The native UH binary still enforces private-memory protection even with that last Linux option off.

## 3. Prepare the legacy toolchains

The exact downloads and SHA-256 checksums are recorded in [provenance.md](provenance.md). These archives are external dependencies, not included in the release. A sample setup follows; download verification is required before extraction.

```sh
mkdir -p build/downloads build/toolchains/{clang-4639204,gcc-aarch64-4.9,compat}
curl -fL 'https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/c9cc9e7d29b8970d8ddb734c88fb62d01e0b7279/clang-4639204.tar.gz' \
  -o build/downloads/clang.tar.gz
curl -fL 'https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/+archive/961622e926a1b21382dba4dd9fe0e5fb3ee5ab7c.tar.gz' \
  -o build/downloads/gcc.tar.gz
echo 'b238b6e31f42cba3e85c5fd57b3e0913a1fa67a3338bde8a806274ed1132c9e2  build/downloads/clang.tar.gz' | sha256sum -c -
echo 'be057c809355f940b0802407a2ac9b7d7ea8cc43f9da6b92b8e47579c6d97a7c  build/downloads/gcc.tar.gz' | sha256sum -c -
tar -xzf build/downloads/clang.tar.gz -C build/toolchains/clang-4639204
tar -xzf build/downloads/gcc.tar.gz -C build/toolchains/gcc-aarch64-4.9
```

Clang's executable may be `bin/clang.real`; the build script also accepts `bin/clang`. These old binaries need `libtinfo.so.5`. On hosts without it, extract a compatible Ubuntu `libtinfo5` package under `build/toolchains/compat` with `dpkg-deb -x`. The exact package used is linked in the provenance document; verify its checksum first. The script extends `LD_LIBRARY_PATH` only for this build, so no system library replacement is needed.

```sh
export TOOLCHAINS="$PWD/build/toolchains"
export KERNEL_SRC="$PWD/build/kernel-src"
export KERNEL_OUT="$PWD/build/kernel-out"
export JOBS=8
bash scripts/build-kernel.sh
```

The script refuses an already configured output directory, checks the patch in reverse, copies the full config, runs `olddefconfig`, confirms critical settings and builds `Image`. The tested environment used `HOSTCC='gcc-11 -fcommon'`, `HOSTCXX=g++-11`, `ARCH=arm64`, `PLATFORM_VERSION=11`, `ANDROID_MAJOR_VERSION=r`, `LOCALVERSION=-22755563` and `KCFLAGS=-I<source-directory>`.

The patch also carries fixes needed for this build: Clang 6's missing AArch64 `S` constraint, RKP-disabled page-table symbols, out-of-tree firmware dependencies and modern host `PF_MAX` headers. These are separate from the UH backend and timer change.

## 4. Prepare your own firmware pair

Create `private/` and place **your own original** full boot and UH partition backups there. Keep a second copy outside the build directory. Dumps are ignored by Git. The UH tool accepts either the 2 MiB full original partition or its canonical 284,056-byte signed container. Both must match the audited firmware hash.

```sh
python3 tools/uh_image.py rollback private/original-uh.img --out private/restore-original-uh.tar
python3 tools/uh_image.py pack private/original-uh.img --out private/uh-kvm.img
python3 tools/boot_image.py private/original-boot.img build/kernel-out/arch/arm64/boot/Image \
  --system-map build/kernel-out/System.map --out private/boot-kvm.img
sha256sum private/*.img private/*.tar
```

Prepare rollback **first**. Each output must be a new filename. The tools never write partitions or overwrite existing files.

UH packing verifies original hash, NOP padding, all 16 vector branches, the native init call, shared marker, publisher size, the QEMU result and the exact final tested UH hash. Only the audited patch sites change. Modifying the payload invalidates Samsung's signature; successful loading of this modified UH was observed on the unlocked test phone after a rooted raw partition write. Modified-UH flashing through Download Mode was not tested.

Boot packing replaces the uncompressed arm64 kernel in the tested Android boot-v2 layout. It preserves your ramdisk, DTB, 64-byte Samsung footer and the original header fields except kernel length and the derived Android boot ID. It verifies the original DTB hash, kernel markers, Clang/version banner, Hyp idmap size, handoff-entry bounds, vector alignment/range and partition size. It is intentionally restricted to this layout, rather than a general Android image repacker.

Your boot hash will differ if your ramdisk, compiler build environment or kernel timestamp differs. The reference boot was a local rooted image and is not redistributed. Firmware compatibility comes from using the audited firmware and layout, not requiring someone else's personal ramdisk hash.

Next: [installation and recovery](install.md).

For native containers on the same KVM backend, use the separate
[Docker build profile](docker.md). It supplies its own full config and optional
cpuset compatibility patch; `KERNEL_PROFILE=kvm` remains the default.
