load("@bazel_skylib//rules:write_file.bzl", "write_file")

common_configs = [
	"CONFIG_SPECTRA_ISP=y",
	"CONFIG_SPECTRA_ICP=y",
	"CONFIG_SPECTRA_SENSOR=y",
]

dependency_config = [
	"CONFIG_INTERCONNECT_QCOM=y",
]

project_configs = select({
    # Project-specific configs
    ":no_project": [],
    ":pineapple": dependency_config,
    ":sun": dependency_config + [
       "CONFIG_SPECTRA_SECURE_DYN_PORT_CFG=y",
    ],
    ":lahaina": [],
    ":canoe": [],
    ":parrot": [
	"CONFIG_SPECTRA_TFE=y",
	"CONFIG_SPECTRA_CRE=y",
    ],
    ":taro": [
        "CONFIG_SPECTRA_JPEG=y",
        "CONFIG_SPECTRA_CUSTOM=y",
    ],
})

# Per-target extras for builds without a project flag
target_configs = {
    # CamX encodes snapshots on the JPEG HW
    "waipio": ["CONFIG_SPECTRA_JPEG=y"],
}

"""
Return a label which defines a project-specific defconfig snippet to be
applied on top of the platform defconfig.
"""

def get_project_defconfig(target, variant):
    rule_name = "{}_{}_project_defconfig".format(target, variant)

    write_file(
        name = rule_name,
        out = "{}.generated".format(rule_name),
        content = common_configs + project_configs + target_configs.get(target, []) + [""],
    )

    return rule_name
