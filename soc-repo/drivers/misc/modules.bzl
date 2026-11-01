load(":drivers/misc/isl97900_led/modules.bzl", register_isl97900_led = "register_modules")
load(":drivers/misc/lkdtm/modules.bzl", register_lkdtm = "register_modules")

def register_modules(registry):
    register_lkdtm(registry)
    register_isl97900_led(registry)

    registry.register(
        name = "drivers/misc/qseecom_proxy",
        out = "qseecom_proxy.ko",
        config = "CONFIG_QSEECOM_PROXY",
        srcs = [
            # do not sort
            "drivers/misc/qseecom_proxy.c",
        ],
    )

    registry.register(
        name = "drivers/misc/bootmarker_proxy",
        out = "bootmarker_proxy.ko",
        config = "CONFIG_BOOTMARKER_PROXY",
        srcs = [
            # do not sort
            "drivers/misc/bootmarker_proxy.c",
        ],
    )

    registry.register(
        name = "drivers/misc/frpc-adsprpc",
        out = "frpc-adsprpc.ko",
        config = "CONFIG_QTI_FASTRPC",
        srcs = [
            # do not sort
            "drivers/misc/fastrpc.c",
        ],
        deps = [
            # do not sort
            "drivers/firmware/qcom/qcom-scm",
        ],
    )

    registry.register(
        name = "drivers/misc/tps6286",
        out = "tps6286.ko",
        config = "CONFIG_TPS6286_STEP_DOWN_CONV",
        srcs = [
            # do not sort
            "drivers/misc/tps6286.c",
        ],
    )

    registry.register(
        name = "drivers/misc/ina234b",
        out = "ina234b.ko",
        config = "CONFIG_INA234_CURRENT_MONITOR",
        srcs = [
            # do not sort
            "drivers/misc/ina234b.c",
        ],
    )

    registry.register(
        name = "drivers/misc/slg4dc",
        out = "slg4dc.ko",
        config = "CONFIG_SLG4DC_SIGNAL_IC",
        srcs = [
            # do not sort
            "drivers/misc/slg4dc.c",
        ],
    )

    registry.register(
        name = "drivers/misc/haptic_hv/haptic",
        out = "haptic.ko",
        config = "CONFIG_AWINIC_HAPTIC_HV",
        srcs = [
            # do not sort
            "drivers/misc/haptic_hv/aw8692x.c",
            "drivers/misc/haptic_hv/haptic_hv.c",
            "drivers/misc/haptic_hv/haptic_hv.h",
            "drivers/misc/haptic_hv/haptic_hv_reg.h",
        ],
    )
    registry.register(
        name = "drivers/misc/hardware_id",
        out = "hardware_id.ko",
        config = "CONFIG_NT2_HWID",
        srcs = [
            # do not sort
            "drivers/misc/hardware_id.c",
        ],
    )
    registry.register(
        name = "drivers/misc/secure_state",
        out = "secure_state.ko",
        config = "CONFIG_NT_SECURE_STATE",
        srcs = [
            # do not sort
            "drivers/misc/secure_state.c",
        ],
    )
    registry.register(
        name = "drivers/misc/slot_status",
        out = "slot_status.ko",
        config = "CONFIG_NT_SLOT_STATE",
        srcs = [
            # do not sort
            "drivers/misc/slot_status.c",
        ],
    )
