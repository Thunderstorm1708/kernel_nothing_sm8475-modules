def register_modules(registry):
    registry.register(
        name = "drivers/input/fingerprint/goodix_fp",
        out = "goodix_fp.ko",
        config = "CONFIG_GOODIX_FINGERPRINT",
        srcs = [
            # do not sort
            "drivers/input/fingerprint/gf_spi.c",
            "drivers/input/fingerprint/gf_spi.h",
            "drivers/input/fingerprint/netlink.c",
            "drivers/input/fingerprint/platform.c",
        ],
        deps = [
            "drivers/soc/qcom/panel_event_notifier",
        ],
    )
