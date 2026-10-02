# Validation - 2026-10-02

## Upstream evidence

- LM Studio's [stable download page](https://lmstudio.ai/download) lists Windows 0.4.25.
- PrismML's [latest release](https://github.com/PrismML-Eng/llama.cpp/releases/tag/prism-b10743-adfffbe) is `prism-b10743-adfffbe`, published 2026-09-25. GitHub API asset names and SHA-256 digests were checked; the pinned digests in `install.ps1` match those records.
- Windows x64 assets include CUDA 12.4 and 13.3, CPU, Vulkan, and HIP/Radeon. Linux CUDA 12.8 and Windows ARM64 CUDA 13.4 assets are not Windows x64 packages.
- NVIDIA's [current Toolkit release notes](https://docs.nvidia.com/cuda/cuda-toolkit-release-notes/index.html) list CUDA 13.4 Update 1. This installer uses bundled runtime DLLs, not a locally installed Toolkit.
- [PrismML backend support](https://github.com/PrismML-Eng/Bonsai-demo/blob/main/BACKEND-SUPPORT.md) and [model formats](https://github.com/PrismML-Eng/Bonsai-demo/blob/main/MODEL-FORMATS.md) document the fork requirement, transforms, Vulkan PQ2_0 limitation, and legacy Q2_0 migration. The backend table's source audit is pinned to `prism-b10709-9a9394a`, not the new release; it is not a fresh device test.
- Selected local LM Studio runtime: Windows x64 CUDA 12 llama.cpp `2.50.0`. Its actual `backend-manifest.json` and `engine-protocol-server-artifacts.json` were inspected. The installer validates that server protocol and preserves unknown JSON fields. CPU and Vulkan 2.50.0 manifest layouts were also inspected.

## Installer checks

`tests/Test-Installer.ps1` passed under Windows PowerShell 5.1 and PowerShell 7. This is an offline installer test with an explicitly synthetic native test server; it is not a model/runtime test.

Covered: exact selected-version targeting; no-write dry run; backend mismatch; copied-server startup failure; rollback when the second manifest cannot be written; preservation of stock DLLs and unknown fields; original backup retention; identical reruns; rejection of a corrupt cached archive; batch argument forwarding and success/failure exit codes.

`git diff --check` passed. GitHub Actions runs the same checks with both shells; remote CI must be checked on the exact pushed commit separately.

## Real binaries and model generation

All four downloaded CUDA archives matched the release SHA-256 digests before extraction: CUDA 12.4 / 13.3 server binaries and each matching runtime-DLL bundle.

Both packages were installed into isolated test engine folders using the actual 2.50.0 manifest layouts. Original installed LM Studio engines/settings were not modified. Source and copied binaries reported `0.2.0-dev`, build `10743`, commit `adfffbe41`.

Hardware: Windows x64, RTX 4080 SUPER (compute capability 8.9), NVIDIA driver 617.14, driver-reported CUDA UMD capability 13.4.

Model: already-installed `Ternary-Bonsai-2-27B-Uncensored-Heretic-PQ2_0.gguf`, 8,137,314,784 bytes. This is a community Bonsai 2 derivative, not a test of every official model or packing.

The copied servers ran on localhost with `--device CUDA0 -ngl 99 -c 2048 --jinja --reasoning off --no-warmup -lv 4`. Process module inspection confirmed that each loaded its own isolated `ggml-cuda.dll`; both logs reported 65/65 layers offloaded to GPU. Each passed `/health`, then generated answers through `/v1/chat/completions` at temperature 0:

| Build | Capital of France | 7 times 8 |
|---|---|---|
| CUDA 12.4 | Paris | 56 |
| CUDA 13.3 | Paris | 56 |

Only processes launched for these tests were stopped afterward. This proves loading and basic generation for this model/hardware/build combination. No speed comparison or quality benchmark is claimed.

## Remaining integration coverage

The updated manifest routing has not been exercised through a fresh LM Studio UI/session. Standalone server tests do not prove the complete LM Studio bridge, vision/projector handling, embeddings, tool calling, reasoning controls, or other ordinary GGUF models. PTQ1_0, development Q2_0, CPU, HIP, Vulkan, ARM64, and other GPUs were not run here.

An existing v1.0.0 installation may have replaced LM Studio's native root libraries. This update preserves those files rather than silently restoring unknown state; restore the old complete backup or re-download the stock runtime before using the new isolated routing.

No new public GitHub release is published by this maintenance update. The historical v1.0.0 assets remain unchanged; the README directs users to current source.
