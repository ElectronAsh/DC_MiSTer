param(
    [Parameter(Mandatory = $true)]
    [string]$SourceDir,
    [Parameter(Mandatory = $true)]
    [string]$DestDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $SourceDir)) {
    Write-Host "Vsimtop cache: source not found: $SourceDir"
    exit 0
}

if (-not (Test-Path -LiteralPath $DestDir)) {
    New-Item -ItemType Directory -Path $DestDir | Out-Null
}

$sourceFiles = Get-ChildItem -LiteralPath $SourceDir -Filter "Vsimtop*.cpp" -File
$sourceFiles += Get-ChildItem -LiteralPath $SourceDir -Filter "Vsimtop*.h" -File

$sourceNames = @{}
foreach ($src in $sourceFiles) {
    $sourceNames[$src.Name] = $true
    $dstPath = Join-Path $DestDir $src.Name
    $copy = $true

    if (Test-Path -LiteralPath $dstPath) {
        $srcHash = (Get-FileHash -LiteralPath $src.FullName -Algorithm SHA256).Hash
        $dstHash = (Get-FileHash -LiteralPath $dstPath -Algorithm SHA256).Hash
        if ($srcHash -eq $dstHash) {
            $copy = $false
        }
    }

    if ($copy) {
        Copy-Item -LiteralPath $src.FullName -Destination $dstPath -Force
    }
}

# Remove stale files in cache dir
Get-ChildItem -LiteralPath $DestDir -Filter "Vsimtop*.*" -File | ForEach-Object {
    if (-not $sourceNames.ContainsKey($_.Name)) {
        Remove-Item -LiteralPath $_.FullName -Force
    }
}
