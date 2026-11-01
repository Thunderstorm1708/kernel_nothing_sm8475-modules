def register_modules(registry):
    registry.register(
        name = "drivers/input/touchscreen/cap1296",
        out = "cap1296.ko",
        config = "CONFIG_TOUCHSCREEN_CAP1296",
        srcs = [
            # do not sort
            "drivers/input/touchscreen/cap1296.c",
            "drivers/input/touchscreen/cap1296.h",
        ],
    )

    registry.register(
        name = "drivers/input/touchscreen/focaltech_touch/fts_tp",
        out = "fts_tp.ko",
        config = "CONFIG_TOUCHSCREEN_FTS",
        srcs = [
            # do not sort
            "drivers/input/touchscreen/focaltech_touch/focaltech_common.h",
            "drivers/input/touchscreen/focaltech_touch/focaltech_config.h",
            "drivers/input/touchscreen/focaltech_touch/focaltech_core.c",
            "drivers/input/touchscreen/focaltech_touch/include/firmware/FT3680_WXN_M146_V27_D01_20220706_app.h",
            "drivers/input/touchscreen/focaltech_touch/include/firmware/fw_sample.h",
            "drivers/input/touchscreen/focaltech_touch/focaltech_core.h",
            "drivers/input/touchscreen/focaltech_touch/focaltech_esdcheck.c",
            "drivers/input/touchscreen/focaltech_touch/focaltech_ex_fun.c",
            "drivers/input/touchscreen/focaltech_touch/focaltech_ex_mode.c",
            "drivers/input/touchscreen/focaltech_touch/focaltech_flash.c",
            "drivers/input/touchscreen/focaltech_touch/focaltech_flash.h",
            "drivers/input/touchscreen/focaltech_touch/focaltech_gesture.c",
            "drivers/input/touchscreen/focaltech_touch/focaltech_point_report_check.c",
            "drivers/input/touchscreen/focaltech_touch/focaltech_spi.c",
        ],
        deps = [
            "drivers/soc/qcom/panel_event_notifier",
        ],
    )
    registry.register(
        name = "drivers/input/touchscreen/goodix_berlin_driver/goodix_core",
        out = "goodix_core.ko",
        config = "CONFIG_TOUCHSCREEN_GOODIX_BRL",
        srcs = [
            # do not sort
            "drivers/input/touchscreen/goodix_berlin_driver/goodix_brl_fwupdate.c",
            "drivers/input/touchscreen/goodix_berlin_driver/goodix_brl_hw.c",
            "drivers/input/touchscreen/goodix_berlin_driver/goodix_brl_i2c.c",
            "drivers/input/touchscreen/goodix_berlin_driver/goodix_brl_spi.c",
            "drivers/input/touchscreen/goodix_berlin_driver/goodix_cfg_bin.c",
            "drivers/input/touchscreen/goodix_berlin_driver/goodix_replay.c",
            "drivers/input/touchscreen/goodix_berlin_driver/goodix_replay_type.h",
            "drivers/input/touchscreen/goodix_berlin_driver/goodix_ts_core.c",
            "drivers/input/touchscreen/goodix_berlin_driver/goodix_ts_core.h",
            "drivers/input/touchscreen/goodix_berlin_driver/goodix_ts_gesture.c",
            "drivers/input/touchscreen/goodix_berlin_driver/goodix_ts_inspect.c",
            "drivers/input/touchscreen/goodix_berlin_driver/goodix_ts_tools.c",
            "drivers/input/touchscreen/goodix_berlin_driver/goodix_ts_utils.c",
        ],
        deps = [
            "drivers/soc/qcom/panel_event_notifier",
        ],
        copts = ["-Wframe-larger-than=2560"],
    )
