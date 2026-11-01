def register_modules(registry):
    registry.register(
        name = "drivers/nothing_thermal/simulated_ntc",
        out = "simulated_ntc.ko",
        config = "CONFIG_NOTHING_SIMULATED_NTC",
        srcs = [
            # do not sort
            "drivers/nothing_thermal/simulated_ntc.c",
        ],
    )
