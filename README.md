# Bonsai 2 won't load in LM Studio — one-click fix

**Symptom:** LM Studio fails to load Bonsai 2 GGUF models:

```
Failed to load model
error loading model: llama_model_loader: failed to load model from ...Ternary-Bonsai...gguf
```

The real reason is in LM Studio's `server-logs`:

```
gguf_init_from_reader: tensor 'output.weight' has invalid ggml type 143. should be in [0, 43)
```

**Why:** Bonsai 2's ternary quants — `PTQ1_0` (ggml type 143) and `PQ2_0` (type 142) — exist only in
[PrismML's llama.cpp fork](https://github.com/PrismML-Eng/llama.cpp). Every engine LM Studio ships is
stock llama.cpp and refuses those types outright. No setting, no re-download, no engine update fixes it.

**Fix:** this script swaps PrismML's prebuilt Windows binaries into LM Studio's engine folder —
it backs up the originals first, then verifies the engine actually starts.

## One-liner

```powershell
irm https://raw.githubusercontent.com/SenjuWoo/bonsai2-lmstudio-fix/main/install.ps1 | iex
```

Or download [`fix.bat`](https://github.com/SenjuWoo/bonsai2-lmstudio-fix/raw/main/fix.bat) and
double-click it. Or clone the repo and run `.\install.ps1`.

Then load your model in LM Studio — no restart needed.

> **After LM Studio updates its inference engines, re-run the script.** Updates restore the stock
> files and fork-only models stop loading again.

## What it does

1. Finds the engine your LM Studio uses (from `backend-preferences-v1.json`) — plus its other installed versions
2. Downloads the matching PrismML build — pinned release `prism-b10709-9a9394a` —
   CUDA 13.3 / CUDA 12.4 / Vulkan / HIP-Radeon / CPU auto-detected from your GPU
3. Backs up the original engine files to `%LOCALAPPDATA%\PrismML-LMStudio\backup\`
4. Swaps in the fork binaries and checks that `llama-server.exe` starts

## Requirements

- Windows x64 + LM Studio (recent version), used at least once
- ~1 GB free disk per installed engine version (the CUDA runtime DLLs are copied into each; downloads are cached for re-runs)

## Options

```
.\install.ps1 [-DryRun] [-Asset cuda12.4|cuda13.3|vulkan|hip-radeon|cpu]
              [-SourceDir <folder>] [-EngineDir <folder>]
              [-CacheDir <dir>] [-BackupDir <dir>] [-Force]
```

`-DryRun` shows exactly what would be patched without writing anything.

## Rollback

Copy everything from `%LOCALAPPDATA%\PrismML-LMStudio\backup\<engine folder>\` back into
`%USERPROFILE%\.lmstudio\extensions\backends\<engine folder>\` — or just let LM Studio
re-download the engine.

## Notes

- Works for any model using PrismML's `PTQ1_0`/`PQ2_0` quants, not just Bonsai 2
- Verified on Windows 11 x64, LM Studio 0.4.25, engine `llama.cpp-win-x86_64-nvidia-cuda12-avx2@2.41.0`, RTX 4080 SUPER (CUDA 13.3 build) — including a full load + generation test
- NVIDIA CUDA path is tested; Vulkan / CPU / HIP-Radeon builds are wired up but untested — issues welcome
- Prefer not to touch LM Studio? The fork's `llama-server.exe` (in `%LOCALAPPDATA%\PrismML-LMStudio\bin-<asset>`) runs standalone:
  `llama-server.exe -m model.gguf -ngl 99 -c 8192 --flash-attn on --jinja`
- Not affiliated with LM Studio or PrismML. llama.cpp is MIT-licensed; this repo is just the installer.

MIT License
