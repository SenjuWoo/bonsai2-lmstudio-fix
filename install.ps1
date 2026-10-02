<#
  Bonsai 2 / PrismML GGUF runtime for LM Studio (Windows x64).
  Usage: .\install.ps1 [-DryRun] [-Asset cuda12.4|cuda13.3|vulkan|hip-radeon|cpu]
                      [-Latest] [-SourceDir <folder>] [-EngineDir <folder>]
                      [-LMStudioHome <folder>] [-CacheDir <folder>] [-BackupDir <folder>] [-Force]
  Fork binaries stay separate from LM Studio's native libraries. Only the
  selected runtime's two server manifests change; original manifests are backed up.
#>
[CmdletBinding()]
param(
  [string]$EngineDir,
  [string]$SourceDir,
  [string]$Asset,
  [string]$LMStudioHome = $env:LMSTUDIO_HOME,
  [string]$CacheDir = (Join-Path $env:LOCALAPPDATA 'PrismML-LMStudio'),
  [string]$BackupDir,
  [switch]$Latest,
  [switch]$Force,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if ($env:PRISM_DRYRUN -eq '1') { $DryRun = $true }
$Tag = 'prism-b10743-adfffbe'
# GitHub release asset digests, checked 2026-10-02. Windows x64 builds currently
# use CUDA 12.4 and 13.3; a newer Toolkit does not imply a newer fork build.
$Hashes = @{
  'cpu' = 'd0b3016c9cc4bc1385de68be034adee570277ba952dd94292ba3888b7f18cc44'
  'cuda12.4' = '1b849f713bee42fda258de83770cd422e8f48dd631ce370eb0641f6458c69d87'
  'cuda13.3' = 'c4f937e2a873180db5cceafca08fae73b5fa0b3fbbf020aeb555c2efe424c7bb'
  'vulkan' = 'd66e0c4d11ea937c8cb197d6c59ffc8c41599bd30ea58057e7e6a4d5a3ced466'
  'hip-radeon' = '457ea7ed54a11f4ec68180c637fffa120506545b4201a6e7e5343adbb9796d15'
  'runtime12.4' = '8c79a9b226de4b3cacfd1f83d24f962d0773be79f1e7b75c6af4ded7e32ae1d6'
  'runtime13.3' = '1462a050eb4c684921ba51dcc4cc488a036674c3e73e9945ee705b854808d03e'
}

function Say($Message) { Write-Host $Message }
function Fail($Message) { throw $Message }
function Test-Server($Path) {
  $savedPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue' # Windows PowerShell 5.1 native stderr
    $output = (& $Path --version 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $output -notmatch 'version:') { throw "Server startup failed: $Path`n$output" }
    Say "  Engine starts: $(($output -split "`r?`n" | Where-Object { $_ -match 'version:' } | Select-Object -First 1).Trim())"
  } finally { $ErrorActionPreference = $savedPreference }
}
function Write-Json($Path, $Value) {
  [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 30), (New-Object Text.UTF8Encoding($false)))
}

Say 'Bonsai 2 / PrismML runtime for LM Studio'
if (-not $LMStudioHome) { $LMStudioHome = Join-Path $env:USERPROFILE '.lmstudio' }
$engRoot = Join-Path $LMStudioHome 'extensions\backends'
if ($EngineDir) {
  $targets = @((Resolve-Path -LiteralPath $EngineDir).Path)
} else {
  $prefFile = Join-Path $LMStudioHome '.internal\backend-preferences-v1.json'
  if (-not (Test-Path -LiteralPath $prefFile)) { Fail "Cannot find $prefFile. Select a llama.cpp runtime in LM Studio, or pass -EngineDir." }
  $preferences = @(Get-Content -LiteralPath $prefFile -Raw | ConvertFrom-Json | Where-Object { $_.model_format -eq 'gguf' })
  $targets = @($preferences | ForEach-Object {
    if (-not $_.version -or $_.name -notmatch '^llama\.cpp-win-x86_64-[a-zA-Z0-9_-]+$' -or $_.version -notmatch '^\d+(\.\d+){1,3}$') { Fail 'Unsupported runtime preference. Select a Windows x64 llama.cpp runtime.' }
    Join-Path $engRoot "$($_.name)-$($_.version)"
  } | Select-Object -Unique)
}
if (-not $targets) { Fail 'No selected GGUF runtime found.' }
$manifests = @()
$artifacts = @()
$families = @()
foreach ($eng in $targets) {
  if (-not (Test-Path -LiteralPath $eng -PathType Container)) { Fail "Selected engine folder not found: $eng" }
  $m = Get-Content -LiteralPath (Join-Path $eng 'backend-manifest.json') -Raw | ConvertFrom-Json
  $a = Get-Content -LiteralPath (Join-Path $eng 'engine-protocol-server-artifacts.json') -Raw | ConvertFrom-Json
  if ($m.engine -ne 'llama.cpp' -or $m.platform -ne 'win' -or $m.cpu.architecture -ne 'x86_64' -or
      $m.engine_protocol_server.runtime_kind -ne 'llama-server' -or $a.runtime_kind -ne 'llama-server' -or $a.schema_version -ne 1) {
    Fail "Unsupported engine protocol in $eng. Update the LM Studio llama.cpp runtime first."
  }
  if ($m.engine_protocol_server.executable_relative_path -ne $a.executable_relative_path) { Fail "Engine manifests disagree about the server path in $eng." }
  $families += if ($m.gpu.framework -match 'CUDA') { 'cuda' } elseif ($m.gpu.framework -match 'Vulkan') { 'vulkan' } elseif ($m.gpu.framework -match 'HIP|ROCm') { 'hip-radeon' } elseif (-not $m.gpu) { 'cpu' } else { Fail "Unsupported backend in $eng" }
  $manifests += $m
  $artifacts += $a
}
if (@($families | Select-Object -Unique).Count -ne 1) { Fail 'Selected runtimes use different backends. Pass -EngineDir to patch one at a time.' }
$family = $families[0]
$cudaVer = $null
if ($family -eq 'cuda') {
  try {
    $hit = & nvidia-smi 2>$null | Select-String 'CUDA(?: UMD)? Version:\s*([0-9.]+)' | Select-Object -First 1
    if ($hit) { $cudaVer = [version]$hit.Matches[0].Groups[1].Value }
  } catch { }
}
if (-not $Asset) {
  $Asset = if ($family -eq 'cuda') { if ($cudaVer -and $cudaVer -ge [version]'13.3') { 'cuda13.3' } else { 'cuda12.4' } } else { $family }
}
if ($Asset -notin @('cuda12.4', 'cuda13.3', 'vulkan', 'hip-radeon', 'cpu')) { Fail "Unknown -Asset '$Asset'." }
$assetFamily = if ($Asset -like 'cuda*') { 'cuda' } else { $Asset }
if ($assetFamily -ne $family) { Fail "Build $Asset does not match engine backend $family. Select the matching runtime or pass its -EngineDir." }
if ($cudaVer -and $Asset -like 'cuda*' -and $cudaVer -lt [version]$Asset.Substring(4)) { Fail "NVIDIA driver supports CUDA $cudaVer; $Asset requires a newer driver." }
if ($Asset -eq 'vulkan') { Say 'Vulkan has no native PQ2_0 kernels; use PTQ1_0 or select CUDA / HIP / CPU for PQ2_0.' }

$release = $null
if ($Latest -and -not $SourceDir) {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $release = Invoke-RestMethod 'https://api.github.com/repos/PrismML-Eng/llama.cpp/releases/latest' -Headers @{ 'User-Agent' = 'bonsai2-lmstudio-fix' }
  if ($release.draft -or $release.prerelease -or $release.tag_name -notmatch '^prism-b[0-9]+-[a-f0-9]+$') { Fail 'Unexpected upstream release metadata.' }
  $Tag = $release.tag_name
}
$backendName = if ($Asset -like 'cuda*') { 'cuda-' + $Asset.Substring(4) } else { $Asset }
$packages = @([pscustomobject]@{ Name = "llama-$Tag-bin-win-$backendName-x64.zip"; Hash = $Hashes[$Asset] })
if ($Asset -like 'cuda*') { $packages += [pscustomobject]@{ Name = "cudart-llama-bin-win-$backendName-x64.zip"; Hash = $Hashes['runtime' + $Asset.Substring(4)] } }
if ($release) {
  foreach ($package in $packages) {
    $hits = @($release.assets | Where-Object { $_.name -eq $package.Name })
    if ($hits.Count -ne 1 -or $hits[0].digest -notmatch '^sha256:[a-f0-9]{64}$') { Fail "Missing asset or SHA-256 digest: $($package.Name)" }
    $package.Hash = $hits[0].digest.Substring(7)
  }
}
$Base = "https://github.com/PrismML-Eng/llama.cpp/releases/download/$Tag"
if (-not $BackupDir) { $BackupDir = Join-Path $CacheDir 'backup' }
$srcRoot = if ($SourceDir) { (Resolve-Path -LiteralPath $SourceDir).Path } else { Join-Path $CacheDir "bin-$Tag-$Asset" }
if ($SourceDir) { Say "User-supplied build: $Asset" } else { Say "PrismML release: $Tag; build: $Asset" }
$targets | ForEach-Object { Say "Selected engine: $_" }
Say "Binaries: $srcRoot"
Say "Backup: $BackupDir"
if ($DryRun) { Say 'DRY RUN - nothing was written.'; return }

if (-not $SourceDir) {
  $dl = Join-Path $CacheDir "dl\$Tag"
  New-Item -ItemType Directory -Force -Path $srcRoot, $dl | Out-Null
  $complete = Join-Path $srcRoot '.complete'
  if ($Force -or -not (Test-Path -LiteralPath $complete)) {
    foreach ($package in $packages) {
      $zip = Join-Path $dl $package.Name
      if ($Force -or -not (Test-Path -LiteralPath $zip)) {
        $partial = "$zip.partial"
        Say "Downloading $($package.Name) ..."
        if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
          & curl.exe -L --fail --retry 2 -o $partial "$Base/$($package.Name)"
          if ($LASTEXITCODE -ne 0) { Fail "Download failed: $($package.Name)" }
        } else {
          [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
          Invoke-WebRequest "$Base/$($package.Name)" -OutFile $partial -UseBasicParsing
        }
        if ((Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash -ne $package.Hash) { Fail "SHA-256 mismatch: $($package.Name). Re-run with -Force." }
        Move-Item -LiteralPath $partial -Destination $zip -Force
      }
      if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne $package.Hash) { Fail "SHA-256 mismatch: $($package.Name). Re-run with -Force." }
      Expand-Archive -LiteralPath $zip -DestinationPath $srcRoot -Force
    }
    Set-Content -LiteralPath $complete -Value $Tag
  }
}
$srcFiles = @(Get-ChildItem -LiteralPath $srcRoot -Recurse -File | Where-Object { $_.Extension -in '.dll', '.exe' })
if (@($srcFiles | Group-Object Name | Where-Object Count -gt 1).Count) { Fail 'Source contains duplicate binary filenames. Use one extracted backend build.' }
$server = @($srcFiles | Where-Object Name -eq 'llama-server.exe')
if ($server.Count -ne 1) { Fail "Exactly one llama-server.exe is required in $srcRoot." }
$srcFiles | Unblock-File
Test-Server $server[0].FullName # Fail before changing any selected engine.

for ($i = 0; $i -lt $targets.Count; $i++) {
  $eng = $targets[$i]
  $name = Split-Path $eng -Leaf
  $metadata = @('backend-manifest.json', 'engine-protocol-server-artifacts.json')
  $currentPath = $artifacts[$i].executable_relative_path
  if ($currentPath -match '^prism-[^/]+/llama-server\.exe$') {
    $currentDir = Join-Path $eng ($currentPath -replace '/llama-server\.exe$', '')
    $matches = @($srcFiles | Where-Object {
      $existing = Join-Path $currentDir $_.Name
      -not (Test-Path -LiteralPath $existing) -or (Get-FileHash -LiteralPath $existing -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    })
    if (-not $matches.Count) { Test-Server (Join-Path $eng $currentPath); Say "Already installed: $name"; continue }
  }
  $bk = Join-Path $BackupDir $name
  foreach ($file in $metadata) {
    if (-not (Test-Path -LiteralPath (Join-Path $bk $file))) {
      New-Item -ItemType Directory -Force -Path $bk | Out-Null
      Copy-Item -LiteralPath (Join-Path $eng $file) -Destination (Join-Path $bk $file)
    }
  }
  $originalBytes = @{}
  foreach ($file in $metadata) { $originalBytes[$file] = [IO.File]::ReadAllBytes((Join-Path $eng $file)) }
  $buildId = if ($SourceDir) { 'local-' + (Get-FileHash -LiteralPath $server[0].FullName -Algorithm SHA256).Hash.Substring(0, 16).ToLower() } else { $Tag }
  # ponytail: retain one directory per changed build for rollback; remove obsolete
  # directories after restoring stock metadata if disk usage becomes a concern.
  $relDir = "prism-$buildId-$Asset-" + [guid]::NewGuid().ToString('N')
  $dest = Join-Path $eng $relDir
  try {
    New-Item -ItemType Directory -Path $dest | Out-Null
    foreach ($file in $srcFiles) { Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $dest $file.Name) }
    Test-Server (Join-Path $dest 'llama-server.exe')
    $m = $manifests[$i]
    $a = $artifacts[$i]
    $previousExe = $a.executable_relative_path
    $m.engine_protocol_server.executable_relative_path = "$relDir/llama-server.exe"
    $a.executable_relative_path = "$relDir/llama-server.exe"
    $a.files = @($a.files | Where-Object { $_.relative_path -ne $previousExe -and $_.relative_path -notmatch '^prism-[^/]+/' }) + @($srcFiles | ForEach-Object {
      [pscustomobject]@{ relative_path = "$relDir/$($_.Name)"; executable = ($_.Name -eq 'llama-server.exe') }
    })
    Write-Json (Join-Path $eng $metadata[0]) $m
    Write-Json (Join-Path $eng $metadata[1]) $a
    Say "Updated $name. Original DLLs and executables were preserved."
  } catch {
    $failure = $_
    try {
      foreach ($file in $metadata) {
        $path = Join-Path $eng $file
        if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) -ne [Convert]::ToBase64String($originalBytes[$file])) {
          [IO.File]::WriteAllBytes($path, $originalBytes[$file])
        }
      }
    } finally {
      # The unique directory was created by this attempt inside the resolved engine.
      if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
    }
    throw $failure
  }
}
Say 'Runtime configured. Restart LM Studio, then test model loading and generation.'
Say 'Server startup alone does not verify LM Studio integration or model correctness.'
Say "Rollback: restore the two JSON manifests from $BackupDir\<engine folder>, or re-download the runtime in LM Studio."
Say 'Re-run after LM Studio replaces or updates the selected runtime.'
