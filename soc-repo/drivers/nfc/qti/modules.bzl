def register_modules(registry):
    registry.register(
        name = "drivers/nfc/qti/nfc_i2c",
        out = "nfc_i2c.ko",
        config = "CONFIG_NFC_QTI_I2C",
        srcs = [
            # do not sort
            "drivers/nfc/qti/ese_cold_reset.c",
            "drivers/nfc/qti/ese_cold_reset.h",
            "drivers/nfc/qti/nfc_common.c",
            "drivers/nfc/qti/nfc_common.h",
            "drivers/nfc/qti/nfc_i2c_drv.c",
            "drivers/nfc/qti/nfc_i2c_drv.h",
        ],
        deps = [
            "kernel/trace/qcom_ipc_logging",
        ],
    )
