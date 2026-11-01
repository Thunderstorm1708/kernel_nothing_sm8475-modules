def register_modules(registry):
    registry.register(
        name = "drivers/nothing_stability/nothing_bootloader_log",
        out = "nothing_bootloader_log.ko",
        config = "CONFIG_NOTHING_BOOTLOADER_LOG",
        srcs = [
            # do not sort
            "drivers/nothing_stability/nothing_bootloader_log.c",
            "drivers/nothing_stability/include/nothing_secure_element.h",
        ],
    )
    registry.register(
        name = "drivers/nothing_stability/nothing_restart_handler",
        out = "nothing_restart_handler.ko",
        config = "CONFIG_NOTHING_RESTART_HANDLER",
        srcs = [
            # do not sort
            "drivers/nothing_stability/nothing_restart_handler.c",
            "drivers/nothing_stability/include/nothing_secure_element.h",
        ],
    )
    registry.register(
        name = "drivers/nothing_stability/nothing_task_meminfo",
        out = "nothing_task_meminfo.ko",
        config = "CONFIG_NOTHING_TASK_MEMINFO",
        srcs = [
            # do not sort
            "drivers/nothing_stability/nothing_task_meminfo.c",
            "drivers/nothing_stability/include/nothing_secure_element.h",
        ],
    )
    registry.register(
        name = "drivers/nothing_stability/nothing_secure_element",
        out = "nothing_secure_element.ko",
        config = "CONFIG_NOTHING_SECURE_ELEMENT",
        srcs = [
            # do not sort
            "drivers/nothing_stability/nothing_secure_element.c",
            "drivers/nothing_stability/include/nothing_secure_element.h",
        ],
    )
