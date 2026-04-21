# Build a .NET project/solution and return structured output.
# Usage: dotnet-build.ps1 <project-or-solution-path>

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Target
)

$ErrorActionPreference = 'Continue'

Write-Output "::build-start::"
Write-Output "target: $Target"

$output = & dotnet build $Target 2>&1
$exitCode = $LASTEXITCODE

$output | ForEach-Object { Write-Output $_ }

Write-Output "::build-end::"
Write-Output "exit-code: $exitCode"

exit $exitCode
