param([string]$Installer = (Join-Path $PSScriptRoot '..\install.ps1'))
$ErrorActionPreference = 'Stop'
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
$root = Join-Path ([IO.Path]::GetTempPath()) ('bonsai-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
try {
  $tokens = $null; $errors = $null
  [Management.Automation.Language.Parser]::ParseFile($Installer, [ref]$tokens, [ref]$errors) | Out-Null
  Assert (-not $errors.Count) "Installer parse errors: $errors"
  $src = Join-Path $root 'source'
  New-Item -ItemType Directory -Path $src | Out-Null
  $code = @'
using System;
using System.IO;
class Server {
  static int Main() {
    if (Environment.GetEnvironmentVariable("BONSAI_TEST_FAIL_DEST") == "1" &&
        AppDomain.CurrentDomain.BaseDirectory.Contains("prism-")) return 1;
    Console.WriteLine("version: installer-test"); return 0;
  }
}
'@
  $cs = Join-Path $root 'server.cs'
  [IO.File]::WriteAllText($cs, $code)
  $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
  & $csc /nologo /target:exe "/out:$src\llama-server.exe" $cs
  Assert ($LASTEXITCODE -eq 0) 'Test server compilation failed'
  Set-Content -LiteralPath (Join-Path $src 'llama.dll') -Value 'fork-fixture'
  $testHome = Join-Path $root 'home'
  $family = 'llama.cpp-win-x86_64-nvidia-cuda12-avx2'
  $engine = Join-Path $testHome "extensions\backends\$family-2.50.0"
  $oldEngine = Join-Path $testHome "extensions\backends\$family-2.41.0"
  $pref = Join-Path $testHome '.internal'
  New-Item -ItemType Directory -Force -Path $engine, $oldEngine, $pref | Out-Null
  Set-Content (Join-Path $oldEngine 'untouched') 'old runtime'
  $manifest = '{"engine":"llama.cpp","platform":"win","cpu":{"architecture":"x86_64"},"gpu":{"framework":"CUDA"},"engine_protocol_server":{"runtime_kind":"llama-server","executable_relative_path":"llama-server.exe"},"unknown_field":{"keep":true}}'
  $artifact = '{"schema_version":1,"runtime_kind":"llama-server","executable_relative_path":"llama-server.exe","files":[{"relative_path":"llama-server.exe","executable":true},{"relative_path":"llama.dll","executable":false}]}'
  $mPath = Join-Path $engine 'backend-manifest.json'
  $aPath = Join-Path $engine 'engine-protocol-server-artifacts.json'
  Set-Content $mPath $manifest
  Set-Content $aPath $artifact
  Set-Content (Join-Path $engine 'llama.dll') 'stock-fixture'
  Set-Content (Join-Path $pref 'backend-preferences-v1.json') "[{`"model_format`":`"gguf`",`"name`":`"$family`",`"version`":`"2.50.0`"}]"
  $mHash = (Get-FileHash $mPath).Hash
  $aHash = (Get-FileHash $aPath).Hash
  $cache = Join-Path $root 'cache'
  $options = @{ LMStudioHome = $testHome; SourceDir = $src; Asset = 'cuda12.4'; CacheDir = $cache }
  & $Installer @options -DryRun
  Assert (-not (Test-Path $cache)) 'DryRun created a cache'
  Assert ((Get-FileHash $mPath).Hash -eq $mHash) 'DryRun changed the engine'
  $failed = $false
  $wrongOptions = $options.Clone(); $wrongOptions.Asset = 'vulkan'
  try { & $Installer @wrongOptions -DryRun } catch { $failed = $_ -match 'does not match engine backend' }
  Assert $failed 'Backend mismatch was accepted'
  $env:BONSAI_TEST_FAIL_DEST = '1'
  $failed = $false
  try { & $Installer @options } catch { $failed = $true }
  $env:BONSAI_TEST_FAIL_DEST = $null
  Assert $failed 'Failed copied server was accepted'
  Assert ((Get-FileHash $mPath).Hash -eq $mHash) 'Startup failure changed the manifest'
  Assert (-not @(Get-ChildItem $engine -Directory -Filter 'prism-*').Count) 'Startup failure left a runtime directory'
  $lock = [IO.File]::Open($aPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
  $failed = $false
  try { & $Installer @options } catch { $failed = $true } finally { $lock.Dispose() }
  Assert $failed 'Locked metadata was accepted'
  Assert ((Get-FileHash $mPath).Hash -eq $mHash -and (Get-FileHash $aPath).Hash -eq $aHash) 'Metadata failure was not rolled back'
  Assert (-not @(Get-ChildItem $engine -Directory -Filter 'prism-*').Count) 'Metadata failure left a runtime directory'
  & $Installer @options
  $m = Get-Content $mPath -Raw | ConvertFrom-Json
  $a = Get-Content $aPath -Raw | ConvertFrom-Json
  Assert ($m.unknown_field.keep) 'Unknown manifest fields were lost'
  Assert ($m.engine_protocol_server.executable_relative_path -eq $a.executable_relative_path) 'Server paths disagree'
  Assert ($a.executable_relative_path -match '^prism-local-.*?/llama-server.exe$') 'Server is not isolated'
  Assert ((Get-Content (Join-Path $engine 'llama.dll')).Trim() -eq 'stock-fixture') 'Stock DLL was overwritten'
  Assert ((Get-Content (Join-Path $oldEngine 'untouched')).Trim() -eq 'old runtime') 'Unselected version was changed'
  $bk = Join-Path $cache "backup\$family-2.50.0"
  Assert ((Get-FileHash (Join-Path $bk 'backend-manifest.json')).Hash -eq $mHash) 'Original backup was not preserved'
  & $Installer @options
  Assert (@(Get-ChildItem $engine -Directory -Filter 'prism-*').Count -eq 1) 'Re-run duplicated runtime files'
  Assert ((Get-FileHash (Join-Path $bk 'backend-manifest.json')).Hash -eq $mHash) 'Re-run replaced the original backup'
  # A corrupt cached archive must be rejected before engine metadata changes.
  $badCache = Join-Path $root 'bad-cache'
  $dl = Join-Path $badCache 'dl\prism-b10743-adfffbe'
  New-Item -ItemType Directory -Force -Path $dl | Out-Null
  Set-Content (Join-Path $dl 'llama-prism-b10743-adfffbe-bin-win-cuda-12.4-x64.zip') 'corrupt archive'
  $installedHash = (Get-FileHash $mPath).Hash
  $failed = $false
  try { & $Installer -EngineDir $engine -Asset cuda12.4 -CacheDir $badCache } catch { $failed = $_ -match 'SHA-256 mismatch' }
  Assert $failed 'Corrupt download was not rejected'
  Assert ((Get-FileHash $mPath).Hash -eq $installedHash) 'Corrupt archive changed the manifest'
  $env:BONSAI_NO_PAUSE = '1'
  & (Join-Path (Split-Path $Installer -Parent) 'fix.bat') -EngineDir $engine -Asset invalid -DryRun
  Assert ($LASTEXITCODE -ne 0) 'Batch launcher hid installer failure'
  & (Join-Path (Split-Path $Installer -Parent) 'fix.bat') -EngineDir $engine -Asset cuda12.4 -DryRun
  Assert ($LASTEXITCODE -eq 0) 'Batch launcher rejected a successful dry run'
  Write-Host 'PASS: selection, dry run, backend guard, rollback, DLL isolation, backups, rerun, archive integrity, launcher exit codes.'
} finally {
  $env:BONSAI_TEST_FAIL_DEST = $null
  $env:BONSAI_NO_PAUSE = $null
  # Only this test's GUID directory under the OS temporary directory is removed.
  Remove-Item -LiteralPath $root -Recurse -Force
}
