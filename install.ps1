<#
  Bonsai 2 / PrismML GGUF fix for LM Studio - one-click engine swap
  =================================================================
  Symptom (LM Studio): "Failed to load model" for Bonsai 2 GGUFs; the server log says:
      gguf_init_from_reader: tensor 'output.weight' has invalid ggml type 143. should be in [0, 43)
  Cause: PTQ1_0 (ggml type 143) and PQ2_0 (type 142) exist only in PrismML's llama.cpp fork.
         Every engine LM Studio ships is stock llama.cpp and refuses them.
  Fix:   swap PrismML's prebuilt fork binaries into LM Studio's engine folder
         (original files are backed up first; engine startup is verified afterwards).

  Re-run this script after LM Studio updates its engines (updates restore stock files).

  Usage:
    irm https://raw.githubusercontent.com/SenjuWoo/bonsai2-lmstudio-fix/main/install.ps1 | iex
    .\install.ps1 [-DryRun] [-Asset cuda12.4|cuda13.3|vulkan|hip-radeon|cpu]
                  [-SourceDir <folder>] [-EngineDir <folder>]
                  [-CacheDir <dir>] [-BackupDir <dir>] [-Force]
#>
[CmdletBinding()]
param(
  [string]$EngineDir,
  [string]$SourceDir,
  [string]$Asset,
  [string]$CacheDir  = (Join-Path $env:LOCALAPPDATA 'PrismML-LMStudio'),
  [string]$BackupDir,
  [switch]$Force,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
if ($env:PRISM_DRYRUN -eq '1') { $DryRun = $true }

$Tag    = 'prism-b10709-9a9394a'
$Base   = "https://github.com/PrismML-Eng/llama.cpp/releases/download/$Tag"
$Assets = [ordered]@{
  'cuda13.3'   = @("llama-$Tag-bin-win-cuda-13.3-x64.zip", "cudart-llama-bin-win-cuda-13.3-x64.zip")
  'cuda12.4'   = @("llama-$Tag-bin-win-cuda-12.4-x64.zip", "cudart-llama-bin-win-cuda-12.4-x64.zip")
  'vulkan'     = @("llama-$Tag-bin-win-vulkan-x64.zip")
  'hip-radeon' = @("llama-$Tag-bin-win-hip-radeon-x64.zip")
  'cpu'        = @("llama-$Tag-bin-win-cpu-x64.zip")
}

function Say($m)  { Write-Host $m }
function Fail($m) { throw $m }

Say ''
Say 'Bonsai 2 / PrismML fix for LM Studio'
Say '==================================='

# ---- 1. find the LM Studio engine folder(s) --------------------------------------
$lms     = Join-Path $env:USERPROFILE '.lmstudio'
$engRoot = Join-Path $lms 'extensions\backends'
if (-not (Test-Path $engRoot)) { Fail "LM Studio engine folder not found: $engRoot`nInstall LM Studio and run it once first." }

if ($EngineDir) {
  if (-not (Test-Path $EngineDir)) { Fail "EngineDir not found: $EngineDir" }
  $targets = @((Resolve-Path $EngineDir).Path)
  $selName = Split-Path $EngineDir -Leaf
} else {
  $prefFile = Join-Path $lms '.internal\backend-preferences-v1.json'
  if (-not (Test-Path $prefFile)) { Fail "Cannot find $prefFile`nOpen LM Studio and load any model once, then re-run. (Or pass -EngineDir.)" }
  $families = @(Get-Content $prefFile -Raw | ConvertFrom-Json |
                Where-Object { $_.model_format -eq 'gguf' } |
                ForEach-Object { $_.name } | Select-Object -Unique)
  if (-not $families) { Fail "No llama.cpp engine selected in $prefFile - open LM Studio and load any model once, then re-run." }
  $targets = @()
  foreach ($fam in $families) {
    $targets += @(Get-ChildItem $engRoot -Directory -Filter "$fam-*" -ErrorAction SilentlyContinue |
                  Select-Object -Expand FullName)
  }
  $targets = @($targets | Select-Object -Unique)
  $selName = $families[0]
}
if (-not $targets) { Fail "No engine folders found under $engRoot - pass -EngineDir explicitly." }

# ---- 2. pick the matching PrismML build -------------------------------------------
if (-not $Asset) {
  $probeDir = $targets[0]
  if     ($selName -match 'vulkan')              { $Asset = 'vulkan' }
  elseif ($selName -match 'hip|radeon|rocm|amd') { $Asset = 'hip-radeon' }
  elseif (($selName -match 'cuda|nvidia') -or (Test-Path (Join-Path $probeDir 'ggml-cuda.dll'))) {
    $cudaVer = $null
    try {
      $hit = & nvidia-smi 2>$null | Select-String -Pattern 'CUDA(?: UMD)? Version:\s*([0-9.]+)' | Select-Object -First 1
      if ($hit) { $cudaVer = [version]$hit.Matches[0].Groups[1].Value }
    } catch { }
    if ($cudaVer -and $cudaVer -ge [version]'13.3') { $Asset = 'cuda13.3' } else { $Asset = 'cuda12.4' }
  }
  else { $Asset = 'cpu' }
}
if (-not $Assets.Contains($Asset)) { Fail "Unknown -Asset '$Asset'. Use one of: $(($Assets.Keys | Sort-Object) -join ', ')" }

if (-not $BackupDir) { $BackupDir = Join-Path $CacheDir 'backup' }

Say "LM Studio:      $lms"
Say "Engine family:  $selName"
Say "PrismML build:  $Asset"
Say "Engine folders to patch ($($targets.Count)):"
$targets | ForEach-Object { Say "  $_" }

# ---- 3. get the fork binaries -----------------------------------------------------
if ($SourceDir) {
  $srcRoot = (Resolve-Path $SourceDir).Path
  $srcNote = $srcRoot
} else {
  $bin     = Join-Path $CacheDir "bin-$Asset"
  $dl      = Join-Path $CacheDir 'dl'
  $srcRoot = $bin
  $srcNote = "$bin  (downloaded from PrismML's GitHub release if not cached)"
}

if ($DryRun) {
  Say ''
  Say 'DRY RUN - nothing was written.'
  Say "  Binaries:   $srcNote"
  Say "  Backup dir: $BackupDir"
  return
}

if (-not $SourceDir) {
  New-Item -ItemType Directory -Force -Path $bin, $dl | Out-Null
  if ($Force -or -not (Get-ChildItem $bin -Recurse -Filter llama-server.exe -ErrorAction SilentlyContinue)) {
    foreach ($f in $Assets[$Asset]) {
      $zip = Join-Path $dl $f
      if ($Force -or -not (Test-Path $zip)) {
        Say "Downloading $f ..."
        if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
          & curl.exe -L --fail -o $zip "$Base/$f"
          if ($LASTEXITCODE -ne 0) { Fail "Download failed: $Base/$f" }
        } else {
          Invoke-WebRequest "$Base/$f" -OutFile $zip
        }
      }
      Say "Extracting $f ..."
      try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $bin, $true)
      } catch {
        Expand-Archive -Path $zip -DestinationPath $bin -Force
      }
    }
    Get-ChildItem $bin -Recurse -File | Unblock-File
  } else {
    Say "Using cached binaries: $bin"
  }
}

if (-not (Get-ChildItem $srcRoot -Recurse -Filter llama-server.exe -ErrorAction SilentlyContinue)) {
  Fail "llama-server.exe not found in $srcRoot"
}
if ($SourceDir) {
  $srcFiles = @(Get-ChildItem $srcRoot -File | Where-Object { $_.Extension -in '.dll', '.exe' })
} else {
  $srcFiles = @(Get-ChildItem $srcRoot -Recurse -File | Where-Object { $_.Extension -in '.dll', '.exe' })
}
if (-not $srcFiles) { Fail "No .dll/.exe files found in $srcRoot" }
Say "Binaries:       $srcNote"
Say "Files to copy:  $($srcFiles.Count)"

# ---- 4. patch ---------------------------------------------------------------------
$problems = @()
foreach ($eng in $targets) {
  $name = Split-Path $eng -Leaf
  Say ''
  Say "== $name =="

  $bk = Join-Path $BackupDir $name
  if (Test-Path $bk) {
    Say "  backup already exists -> $bk"
  } elseif (Get-ChildItem $eng -Force) {
    New-Item -ItemType Directory -Force -Path $bk | Out-Null
    Copy-Item (Join-Path $eng '*') $bk -Recurse -Force
    Say "  backed up original files -> $bk"
  } else {
    Say '  (engine folder is empty - nothing to back up)'
  }

  $locked = @()
  foreach ($f in $srcFiles) {
    try { Copy-Item $f.FullName $eng -Force } catch { $locked += $f.Name }
  }
  if ($locked.Count) {
    Say "  FAILED to copy (files in use): $($locked -join ', ')"
    Say '  -> unload all models in LM Studio (or close it) and re-run.'
    $problems += $name
    continue
  }

  $out = ''
  $eap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'   # PS 5.1: native stderr through 2>&1 must not become a terminating error
  try { $out = (& (Join-Path $eng 'llama-server.exe') --version 2>&1 | Out-String).Trim() } catch { }
  $ErrorActionPreference = $eap
  if ($LASTEXITCODE -eq 0 -and $out -match 'version:') {
    Say "  OK - engine starts: $(($out -split "`r?`n")[0].Trim())"
  } else {
    Say "  FAILED - engine did not start. Restore the backup: copy $bk\* back into $eng"
    if ($out) { Say "  output: $out" }
    $problems += $name
  }
}

# ---- 5. done ----------------------------------------------------------------------
Say ''
if ($problems.Count) {
  Say "Finished with problems in: $($problems -join ', ')"
  Say 'Restore those folders from their backups and open an issue with the output above.'
} else {
  Say 'Done. Load your Bonsai 2 model in LM Studio now - no restart needed.'
  Say 'Re-run this script after LM Studio updates its inference engines.'
  Say "Rollback: copy the contents of $BackupDir\<engine folder> back into the engine folder."
}
