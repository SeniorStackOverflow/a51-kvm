# Installation and recovery

This records the procedure used on an **unlocked SM-A515F / A515FXXU5EUJ4**, Android 11, bootloader revision 5. Other firmware, variants and a locked bootloader are outside the tested scope. Kernel and modified UH must be treated as a pair. Writes to the wrong partition or an incompatible UH can prevent Android boot.

## Establish recovery before installation

1. Have the phone physically available, with a charged battery and a reliable USB cable.
2. Verify that your installed recovery works. The test phone kept **TWRP 3.5.0_10-A11_1b1** throughout this experiment.
3. Verify manual Download Mode entry independently of Android.
4. Save full original `boot`, `uh`, `recovery`, `dtbo`, `uhcfg`, `vbmeta` and `vbmeta_samsung` partition backups locally, along with SHA-256 checksums. Preserve another copy outside this repository.
5. Prepare the canonical signed original-UH restore archive with `tools/uh_image.py rollback` and keep the original boot image ready.

Check actual partition symlinks on your phone. The tested device used `/dev/block/by-name/boot` and `/dev/block/by-name/uh`. Select the handset explicitly with `adb -s YOUR_SERIAL`; never rely on whichever device adb selects by default.

## The tested write path

Modified UH was written as a **full 2 MiB raw partition image** from an already rooted environment. The kernel was written as a **full 61,865,984-byte boot image**, preserving the original ramdisk and DTB. The exact build was booted and checked on the phone; no changes to recovery, DTBO, UH configuration or either vbmeta partition were needed for this experiment.

The commands below write real partitions. They are reference steps for someone who has completed the recovery preparation and verified the exact target; this repository provides no automatic flashing or repartitioning script.

```sh
adb -s YOUR_SERIAL shell 'getprop ro.product.model; getprop ro.bootloader'
adb -s YOUR_SERIAL shell "su -c 'ls -l /dev/block/by-name/boot /dev/block/by-name/uh'"
adb -s YOUR_SERIAL push private/boot-kvm.img /data/local/tmp/boot-kvm.img
adb -s YOUR_SERIAL push private/uh-kvm.img /data/local/tmp/uh-kvm.img
# Compare these hashes with the local files before proceeding.
adb -s YOUR_SERIAL shell "su -c 'sha256sum /data/local/tmp/boot-kvm.img /data/local/tmp/uh-kvm.img'"

# Write both members of the pair before rebooting.
adb -s YOUR_SERIAL shell "su -c 'dd if=/data/local/tmp/boot-kvm.img of=/dev/block/by-name/boot bs=4096 && sync'"
adb -s YOUR_SERIAL shell "su -c 'dd if=/data/local/tmp/uh-kvm.img of=/dev/block/by-name/uh bs=4096 && sync'"
adb -s YOUR_SERIAL shell "su -c 'sha256sum /dev/block/by-name/boot /dev/block/by-name/uh'"
adb -s YOUR_SERIAL reboot
```

Stop if a write or readback fails. Compare both complete partition hashes before reboot. The modified UH expected by this repository is `d05d6cdfc282c953d3b048c42fdc77279c2f996a2ed76e36c87fd4c9ff21273a`; the boot hash depends on your build and original ramdisk.

After Android has booted and root is available:

```sh
python3 tools/validate_device.py --serial YOUR_SERIAL
```

It transfers only our probes, verifies transfer hashes and runs minimal guests. It neither writes partitions nor reboots the phone. For reboot validation, save the result, perform a normal reboot manually, and run it again to a different output filename.

## Return to TWRP

On the test phone, with USB connected to the computer, hold **Volume Down + Power** until the screen turns off, then immediately switch from Volume Down to **Volume Up**, continuing to hold Power. Hold until recovery starts; release Power at the logo if needed while keeping Volume Up. Timing matters. A failed Android boot does not by itself mean recovery was overwritten.

From a functioning TWRP environment, restore the original full boot and UH partition images using the same verified partition paths and readback checks. Restoring only boot leaves the modified UH in place; restoring both returns the pair to its original state.

## Download Mode and `SECURE CHECK FAIL (UH)`

For the powered-off handset, hold **both volume buttons** while connecting USB to the computer, then accept the Download Mode prompt with Volume Up. For a stuck handset, force a restart with Volume Down + Power, then use both volume buttons during USB connection when it powers off. Avoid the long-press bootloader-unlock flow; the device is already unlocked.

Download Mode was available before native UH initialization on the tested handset. Its availability and original-UH restoration were checked during the work.

**The full raw UH partition dump is not the signed download file.** Samsung's signer lookup uses `file_end - 0x210`. The audited image has:

| Field | Size / offset |
| --- | --- |
| GREENTEA header | `0x1000` bytes |
| Payload | `0x44388` bytes |
| Signer metadata + RSA footer | `0x210` bytes |
| End of canonical signed file | `0x45598` = **284,056 bytes** |
| Full UH partition | **2,097,152 bytes**, remaining tail zero |

Sending all 2 MiB placed the expected signer footer at the wrong relative position and produced `SECURE CHECK FAIL (UH)`. Removing **only the zero partition tail**, preserving the original payload and complete signer footer, yielded an accepted original-UH restore. Android boot and the full original partition hash were verified afterward.

```sh
python3 tools/uh_image.py rollback private/original-uh.img --out private/original-uh-signed.bin
python3 tools/uh_image.py rollback private/original-uh.img --out private/restore-original-uh.tar
```

The tar contains a single **`uh.bin`** member of 284,056 bytes, suitable as the signed original-UH component for your Samsung download flashing tool. Use your known working model-specific tool setup; the original project used a narrowly scoped custom Download protocol sender. That transport and full proprietary restore images are not distributed here. Do not enable repartitioning or format data as part of this restore.

Canonical original UH SHA-256: `9006b493765b1c57214e5b1f9370066a7e86ca2f620961c53f030edb230b922f`.

Full original UH partition SHA-256 after restoration: `ebdf765c5087cd1953b2e4a11878a65611b2705618c0a31ed05b1419c4571574`.

Download Mode acceptance of the **modified** UH was not tested. Its payload no longer has a valid Samsung signature. The successful modified-UH installation used a rooted raw partition write; the successful signed Download restore used the **original** UH.
