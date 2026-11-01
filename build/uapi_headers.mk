# SPDX-License-Identifier: GPL-2.0
#
# uapi directories of this repo that the kernel's headers_install exports
# (see android/vendor_headers.mk of kernel/nothing/sm8475), in order: later
# ones win. The techpack list is the ddk_uapi_headers of the kleaf build.
VENDOR_UAPI_DIRS := \
	soc-repo/include/uapi \
	qcom/opensource/audio-kernel/include/uapi \
	qcom/opensource/dataipa/drivers/platform/msm/include/uapi \
	qcom/opensource/display-drivers/include/uapi \
	qcom/opensource/securemsm-kernel/include/uapi \
	qcom/opensource/securemsm-kernel/smmu-proxy/include/uapi

# Last, the board uapi headers of the 6.12 build redducc's ROM ships
# (android_device_nothing_phone2-kernel kernel-headers): the legacy audio
# headers the HALs still include, and the board versions of the rest.
VENDOR_UAPI_DIRS += build/uapi-board
