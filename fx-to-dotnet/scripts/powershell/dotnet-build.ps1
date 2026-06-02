# Build a .NET project/solution and return structured output.
# Runs restore and build as separate phases so restore errors (NU*) can be
# distinguished from compile errors (CS*/BC*/FS*).
# Usage: dotnet-build.ps1 <project-or-solution-path> [-RestoreOnly] [-NoRestore]

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Target,

    [Parameter()]
    [switch]$RestoreOnly,

    [Parameter()]
    [switch]$NoRestore
)

$ErrorActionPreference = 'Continue'

if ($RestoreOnly) {
    # Restore-only mode: run dotnet restore and report restore errors
    Write-Output "::restore-start::"
    Write-Output "target: $Target"

    $output = & dotnet restore $Target 2>&1
    $exitCode = $LASTEXITCODE

    $output | ForEach-Object { Write-Output $_ }

    Write-Output "::restore-end::"
    Write-Output "exit-code: $exitCode"

    exit $exitCode
}

if ($NoRestore) {
    # Build-only mode: skip restore, only compile
    Write-Output "::build-start::"
    Write-Output "target: $Target"

    $output = & dotnet build $Target --no-restore 2>&1
    $exitCode = $LASTEXITCODE

    $output | ForEach-Object { Write-Output $_ }

    Write-Output "::build-end::"
    Write-Output "exit-code: $exitCode"

    exit $exitCode
}

# Default: combined restore + build (original behavior)
Write-Output "::build-start::"
Write-Output "target: $Target"

$output = & dotnet build $Target 2>&1
$exitCode = $LASTEXITCODE

$output | ForEach-Object { Write-Output $_ }

Write-Output "::build-end::"
Write-Output "exit-code: $exitCode"

exit $exitCode
