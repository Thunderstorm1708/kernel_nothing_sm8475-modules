## Pong kernel, LineageOS inline build
```
kernel/nothing/sm8475 306283e04 ANDROID: Pong: Find the vendor uapi headers for LineageOS' headers_install
kernel/nothing/sm8475-modules e7e67e0 sde: crtc: Drop the UDFPS FOD plane bring-up logging
kernel/nothing/sm8475-devicetrees 27f93fe Pong: Build with the soc-repo dt-bindings in make builds
device/nothing/Pong 78dee8a Pong: fingerprint: Give the FOD illumination 50 ms to settle
```
```
clang clang-r596125, rust 1.93.1
clang: clang-r596125, rust: 1.93.1, libclang: /home/runner/work/kernel_nothing_sm8475-modules/kernel_nothing_sm8475-modules/tree/prebuilts/clang/host/linux-x86/clang-r584948b/lib
```
### Steps
```
==== Building Kernel Config (08:10:46)
==== Building Kernel Image (Image) (08:10:53)
==== Building DTBs (08:26:53)
==== Building Kernel Modules (08:27:33)
==== Installing Kernel Modules (08:28:15)
==== Building and Installing External Kernel Modules (08:28:17)
==== Packaging out/target/product/Pong/vendor_dlkm (08:39:59)
500 modules, 349 in modules.load -> out/target/product/Pong/vendor_dlkm
==== Packaging vendor_ramdisk (08:40:01)
267 modules, 98 in modules.load -> out/target/product/Pong/vendor_ramdisk
==== Packaging recovery (08:40:03)
267 modules, 0 in modules.load -> out/target/product/Pong/recovery/root
==== Building dtb.img (08:40:04)
==== Building dtbo.img (08:40:52)
==== Done: kernel 6.12.81-4k-g306283e045f6 (08:41:41)
==== Test Image without CONFIG_MODULE_SIG_PROTECT (for other ROMs' modules) (08:41:41)
```
### Comparison with redducc's build
```
ours 500 modules, prebuilt 451
only prebuilt: dispcc_waipio gcc_waipio regmap_ram regmap_raw_ram
only ours: 8021q 9pnet 9pnet_fd aes_neon_blk asix ax88179_178a can_bcm can_dev can_gw cctrng cdc_ether cdc_ncm efivarfs exynos_hvm ftdi_sio gnss gzvm ieee802154_socket kheaders macsec netfs nhc_dest nhc_fragment nhc_hop nhc_ipv6 nhc_mobility nhc_routing nhc_udp open_dice pps_core pstore_blk pstore_zone ptp ptp_kvm r8153_ecm rust_binder slcan snd_hda_codec_hdmi snd_soc_audio_graph_card snd_soc_simple_card_utils tipc_diag usbmon usbserial vcan vcpu_stall_detector virtio_balloon virtio_blk virtio_console virtio_pci virtio_pci_legacy_dev virtio_pci_modern_dev vmw_vsock_virtio_transport wwan
   bluetooth: imports only ours=[] only ref=['memmove']
   mpam_msc_slc: imports only ours=[] only ref=['memcpy']
   msm_eva: depends ours=['frpc_adsprpc', 'llcc_qcom', 'mdt_loader', 'mem_buf_dev', 'minidump', 'msm_mmrm', 'qcom_scm', 'qcom_va_minidump', 'synx_driver'] ref=['frpc_adsprpc', 'llcc_qcom', 'mdt_loader', 'msm_mmrm', 'qcom_scm', 'synx_driver']
   msm_eva: imports only ours=['mem_buf_dma_buf_copy_vmperm', 'msm_minidump_add_region', 'msm_minidump_enabled', 'msm_minidump_remove_region', 'qcom_va_md_add_region', 'qcom_va_md_enabled'] only ref=[]
   qcom_stats: imports only ours=['__copy_overflow'] only ref=[]
   qti_battery_charger: imports only ours=[] only ref=['__warn_printk']
   slhc: imports only ours=[] only ref=['__warn_printk']
   tornado_mod: imports only ours=[] only ref=['__fortify_panic']
   tz_log_dlkm: depends ours=['qcom_scm', 'tmecom_intf'] ref=['qcom_scm', 'tmecom_intf_dlkm']
{'compared': 447, 'imports': 7, 'depends': 2}
dtb.img vs cape-v2 + cape + capep: identical
dtbo.img vs reference (without its AVB padding): identical
protected GKI modules without a signature: none
signed vendor (non-GKI) modules: 0 (a kleaf build signs none)
```
### Last lines of the build log
```
  AR      drivers/staging/built-in.a
  LD [M]  drivers/android/binder/rust_binder.o
  AR      drivers/built-in.a
  AR      built-in.a
  AR      vmlinux.a
  LD      vmlinux.o
  OBJCOPY modules.builtin.modinfo
  GEN     modules.builtin
  GEN     .vmlinux.objs
  MODPOST Module.symvers
  GEN     vmlinux.symvers
  CC      .vmlinux.permitted-imports.o
  UPD     include/generated/utsversion.h
  CC      init/version-timestamp.o
  KSYMS   .tmp_vmlinux0.kallsyms.S
  AS      .tmp_vmlinux0.kallsyms.o
  LD      .tmp_vmlinux1
  BTF     .tmp_vmlinux1.btf.o
  NM      .tmp_vmlinux1.syms
  KSYMS   .tmp_vmlinux1.kallsyms.S
  AS      .tmp_vmlinux1.kallsyms.o
  LD      .tmp_vmlinux2
  NM      .tmp_vmlinux2.syms
  KSYMS   .tmp_vmlinux2.kallsyms.S
  AS      .tmp_vmlinux2.kallsyms.o
  LD      vmlinux
  BTFIDS  vmlinux
WARN: multiple IDs found for 'inode': 322, 30922 - using 322
WARN: multiple IDs found for 'module': 257, 30964 - using 257
WARN: multiple IDs found for 'vm_area_struct': 588, 31039 - using 588
WARN: multiple IDs found for 'task_struct': 435, 31047 - using 435
WARN: multiple IDs found for 'cgroup': 503, 31060 - using 503
WARN: multiple IDs found for 'seq_file': 519, 31076 - using 519
WARN: multiple IDs found for 'file': 248, 31090 - using 248
WARN: multiple IDs found for 'path': 2025, 31176 - using 2025
  NM      System.map
  SORTTAB vmlinux
  OBJCOPY arch/arm64/boot/Image
make[1]: Leaving directory '/home/runner/work/kernel_nothing_sm8475-modules/kernel_nothing_sm8475-modules/tree/out/target/product/Pong/obj/KERNEL_OBJ'
make: Leaving directory '/home/runner/work/kernel_nothing_sm8475-modules/kernel_nothing_sm8475-modules/tree/kernel/nothing/sm8475'
```
