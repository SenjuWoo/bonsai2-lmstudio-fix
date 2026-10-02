# Changelog

## 1.1.0 - 2026-10-02

- Update the PrismML baseline to `prism-b10743-adfffbe` and retain explicit CUDA 12.4 / 13.3 builds.
- Add `-Latest` with upstream asset discovery and SHA-256 checks; separate caches by release and build.
- Select the exact configured LM Studio runtime version and validate its server protocol.
- Keep PrismML DLLs separate from LM Studio's native libraries; back up and restore server manifests on failure.
- Make the batch launcher prefer its adjacent installer, forward options, fetch current source when standalone, and return failure codes.
- Correct model-format, Vulkan, legacy-format, restart, and verification guidance.
- Add runnable Windows PowerShell 5.1 / PowerShell 7 regression checks and CI.
