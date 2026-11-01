# CodeLinaro import

This branch only holds a GitHub Actions workflow. On push it fetches the Qualcomm
(CodeLinaro) kernel techpacks pinned by the waipio Android 17 manifests and pushes
each one, as a single snapshot commit, to a `clo/<name>` branch of this repository.
