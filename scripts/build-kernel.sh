#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
: "${KERNEL_SRC:?Set KERNEL_SRC to the source prepared by tools/prepare_kernel.py}"
: "${KERNEL_OUT:?Set KERNEL_OUT to a fresh output directory}"
: "${TOOLCHAINS:?Set TOOLCHAINS to the toolchain directory described in docs/build.md}"
src=$(realpath "$KERNEL_SRC")
out=$(realpath -m "$KERNEL_OUT")
tc=$(realpath "$TOOLCHAINS")
[[ "$src" != "$out" ]] || { echo 'Source and output must differ' >&2; exit 1; }
[[ ! -e "$out/.config" ]] || { echo 'Output already configured; choose a fresh directory' >&2; exit 1; }
[[ $(git -C "$src" rev-parse HEAD) == $(cat "$repo/kernel/base-commit.txt") ]] || { echo 'Wrong kernel base' >&2; exit 1; }
git -C "$src" apply --reverse --check "$repo/kernel/a51-kvm.patch"
export ARCH=arm64 PLATFORM_VERSION=11 ANDROID_MAJOR_VERSION=r
export LD_LIBRARY_PATH="$tc/compat/lib/x86_64-linux-gnu:$tc/compat/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
cc="$tc/clang-4639204/bin/clang.real"
[[ -x "$cc" ]] || cc="$tc/clang-4639204/bin/clang"
"$cc" --version | grep -q 'clang version 6.0.1'
args=(O="$out" LOCALVERSION=-22755563 CC="$cc" CROSS_COMPILE="$tc/gcc-aarch64-4.9/bin/aarch64-linux-android-" HOSTCC='gcc-11 -fcommon' HOSTCXX=g++-11 KCFLAGS="-I$src")
case "${KERNEL_PROFILE:-kvm}" in
    kvm) config="$repo/kernel/a51.config" ;;
    docker)
        git -C "$src" apply --reverse --check "$repo/kernel/docker-cpuset.patch"
        config="$repo/kernel/docker.config"; args+=(LOCALVERSION=-22755563-docker)
        ;;
    *) echo 'KERNEL_PROFILE must be kvm or docker' >&2; exit 1 ;;
esac
mkdir -p "$out"
cp "$config" "$out/.config"
make -C "$src" "${args[@]}" olddefconfig
if [[ "${KERNEL_PROFILE:-kvm}" == docker ]]; then
    python3 "$repo/tools/check_docker_config.py" "$out/.config"
fi
for required in 'CONFIG_KVM=y' 'CONFIG_UH=y' '# CONFIG_UH_RKP is not set' 'CONFIG_SOC_EXYNOS9610=y' 'CONFIG_HARDEN_BRANCH_PREDICTOR=y'; do
    grep -qxF "$required" "$out/.config" || { echo "Missing $required" >&2; exit 1; }
done
make -C "$src" -j"${JOBS:-$(nproc)}" "${args[@]}" Image 2>&1 | tee "$out/build.log"
sha256sum "$out/arch/arm64/boot/Image"
