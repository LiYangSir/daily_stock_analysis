$ErrorActionPreference = 'Stop'

Write-Host 'Building React UI (static assets)...'
Push-Location 'apps\dsa-web'
if (!(Test-Path 'node_modules')) {
  npm install
}
npm run build
Pop-Location

if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
  Write-Host 'uv not found. Installing via pip...'
  $bootstrapPython = $env:PYTHON_BIN
  if ([string]::IsNullOrWhiteSpace($bootstrapPython)) {
    $bootstrapPython = 'python'
  }
  & $bootstrapPython -m pip install --user uv
  if ($LASTEXITCODE -ne 0) {
    throw 'Failed to install uv via pip; please install uv manually.'
  }
}

if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
  throw 'uv installation completed but uv executable is not on PATH.'
}

function Invoke-UvPython {
  param([Parameter(ValueFromRemainingArguments = $true)] [string[]]$Args)
  & uv run python @Args
}

function Test-UvPythonCode {
  param([string]$Code)
  try {
    & uv run python -c $Code *> $null
    return ($LASTEXITCODE -eq 0)
  } catch {
    return $false
  }
}

Write-Host 'Verifying static asset references (source)...'
Invoke-UvPython "${PSScriptRoot}\check_static_assets.py" 'static'
if ($LASTEXITCODE -ne 0) {
  throw "Static asset sanity check failed for source static/. See GitHub #1064."
}

Write-Host 'Installing backend dependencies (uv sync --frozen)...'
& uv sync --frozen
if ($LASTEXITCODE -ne 0) {
  throw "uv sync --frozen failed with exit code $LASTEXITCODE."
}

Write-Host 'Ensuring PyInstaller is available...'
if (-not (Test-UvPythonCode -Code "import PyInstaller")) {
  & uv pip install pyinstaller
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to install pyinstaller via uv pip."
  }
}

Write-Host 'Checking python-multipart availability...'
if (-not (Test-UvPythonCode -Code "import multipart, multipart.multipart")) {
  throw 'python-multipart is not importable in the uv environment.'
}

Write-Host 'Checking AlphaSift adapter availability...'
if (-not (Test-UvPythonCode -Code "import alphasift.dsa_adapter")) {
  throw 'alphasift.dsa_adapter is not importable after uv sync.'
}

if (Test-Path 'dist\backend') {
  Remove-Item -Recurse -Force 'dist\backend'
}
New-Item -ItemType Directory -Path 'dist\backend' | Out-Null

if (Test-Path 'dist\stock_analysis') {
  Remove-Item -Recurse -Force 'dist\stock_analysis'
}

if (Test-Path 'build\stock_analysis') {
  Remove-Item -Recurse -Force 'build\stock_analysis'
}

$hiddenImports = @(
  'multipart',
  'multipart.multipart',
  'json_repair',
  'tiktoken',
  'tiktoken_ext',
  'tiktoken_ext.openai_public',
  'api',
  'api.app',
  'api.deps',
  'api.v1',
  'api.v1.router',
  'api.v1.endpoints',
  'api.v1.endpoints.analysis',
  'api.v1.endpoints.history',
  'api.v1.endpoints.stocks',
  'api.v1.endpoints.health',
  'api.v1.endpoints.alphasift',
  'alphasift',
  'alphasift.dsa_adapter',
  'api.v1.schemas',
  'api.v1.schemas.analysis',
  'api.v1.schemas.history',
  'api.v1.schemas.stocks',
  'api.v1.schemas.common',
  'api.middlewares',
  'api.middlewares.error_handler',
  'src.services',
  'src.services.task_queue',
  'src.services.analysis_service',
  'src.services.history_service',
  'src.services.alphasift_service',
  'uvicorn.logging',
  'uvicorn.loops',
  'uvicorn.loops.auto',
  'uvicorn.protocols',
  'uvicorn.protocols.http',
  'uvicorn.protocols.http.auto',
  'uvicorn.protocols.websockets',
  'uvicorn.protocols.websockets.auto',
  'uvicorn.lifespan',
  'uvicorn.lifespan.on'
)
$hiddenImportArgs = $hiddenImports | ForEach-Object { "--hidden-import=$_" }

$pyInstallerArgs = @(
  '-m', 'PyInstaller',
  '--name', 'stock_analysis',
  '--onedir',
  '--noconfirm',
  '--noconsole',
  '--add-data', 'static;static',
  '--add-data', 'strategies;strategies',
  '--collect-data', 'litellm',
  '--collect-data', 'tiktoken',
  '--collect-all', 'alphasift'
)
$pyInstallerArgs += $hiddenImportArgs
$pyInstallerArgs += 'main.py'

Write-Host "Running: uv run python $($pyInstallerArgs -join ' ')"
& uv run python @pyInstallerArgs
if ($LASTEXITCODE -ne 0) {
  throw "PyInstaller failed with exit code $LASTEXITCODE."
}

if (!(Test-Path 'dist\stock_analysis')) {
  throw 'PyInstaller finished but dist\stock_analysis was not generated.'
}

Copy-Item -Path 'dist\stock_analysis' -Destination 'dist\backend\stock_analysis' -Recurse -Force

Write-Host 'Verifying packaged AlphaSift importability...'
$packagedEntry = Join-Path 'dist\backend\stock_analysis' 'stock_analysis.exe'
if (-not (Test-Path $packagedEntry)) {
  throw "Packaged backend entrypoint not found: $packagedEntry"
}
$previousProbe = $env:DSA_PACKAGED_ALPHASIFT_IMPORT_PROBE
try {
  $env:DSA_PACKAGED_ALPHASIFT_IMPORT_PROBE = '1'
  $probeProcess = Start-Process -FilePath $packagedEntry -Wait -PassThru
  if ($probeProcess.ExitCode -ne 0) {
    throw "Packaged backend cannot import alphasift.dsa_adapter; probe exited with code $($probeProcess.ExitCode)."
  }
} finally {
  if ($null -eq $previousProbe) {
    Remove-Item Env:DSA_PACKAGED_ALPHASIFT_IMPORT_PROBE -ErrorAction SilentlyContinue
  } else {
    $env:DSA_PACKAGED_ALPHASIFT_IMPORT_PROBE = $previousProbe
  }
}

Write-Host 'Verifying static asset references (packaged)...'
$packagedStatic = Join-Path 'dist\backend\stock_analysis' '_internal\static'
if (-not (Test-Path $packagedStatic)) {
  $packagedStatic = Join-Path 'dist\backend\stock_analysis' 'static'
}
if (Test-Path $packagedStatic) {
  & uv run python "${PSScriptRoot}\check_static_assets.py" $packagedStatic
  if ($LASTEXITCODE -ne 0) {
    throw "Static asset sanity check failed for packaged $packagedStatic. See GitHub #1064."
  }
} else {
  Write-Warning "Could not locate packaged static directory under dist\backend\stock_analysis; skipping post-package check."
}

Write-Host 'Verifying packaged built-in strategies...'
$sourceStrategyCount = @(Get-ChildItem -Path 'strategies' -Filter '*.yaml' -File).Count
$packagedStrategies = Join-Path 'dist\backend\stock_analysis' '_internal\strategies'
if (-not (Test-Path $packagedStrategies)) {
  $packagedStrategies = Join-Path 'dist\backend\stock_analysis' 'strategies'
}
if (-not (Test-Path $packagedStrategies)) {
  throw 'Packaged strategies directory not found under dist\backend\stock_analysis.'
}
$packagedStrategyCount = @(Get-ChildItem -Path $packagedStrategies -Filter '*.yaml' -File).Count
if ($packagedStrategyCount -ne $sourceStrategyCount) {
  throw "Packaged strategies count mismatch: expected $sourceStrategyCount, got $packagedStrategyCount."
}

Write-Host 'Backend build completed.'
