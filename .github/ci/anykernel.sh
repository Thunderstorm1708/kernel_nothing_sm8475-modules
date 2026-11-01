### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers
## Nothing Phone (2) "Pong": 6.12 kernel, LineageOS inline build (test)

### AnyKernel setup
# global properties
properties() { '
kernel.string=Pong 6.12 inline build @RELEASE@ (CI run @RUN@, @SHA@) - test kernel, no KernelSU
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=Pong
device.name2=pong
device.name3=
device.name4=
device.name5=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties


### AnyKernel install
# Only the kernel of the boot image is replaced. Pong boots a GKI boot image
# (header v4): the ramdisk stays untouched, the dtb lives in vendor_boot and
# the modules in vendor_boot/vendor_dlkm, all of which stay the ROM's. Meant
# for a ROM running redducc's 6.12 kernel (PenguinOS), whose modules have the
# same symbol versions as this kernel.

# boot shell variables
BLOCK=boot;
IS_SLOT_DEVICE=1;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

# boot install: replace the kernel, skip the ramdisk unpack/repack
split_boot;

flash_boot;
## end boot install
