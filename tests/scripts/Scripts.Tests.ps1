# Pester 5 PS-only assertions for fx-to-dotnet PowerShell scripts.
# Scope: parameter validation, error streams, $LASTEXITCODE propagation.
# Cross-platform behavior is covered by the pytest tier.

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:Support  = Join-Path $script:RepoRoot 'support_scripts'
    $script:FxScripts = Join-Path $script:RepoRoot 'fx-to-dotnet/scripts/powershell'
}

Describe 'bump-version.ps1' {
    It 'rejects non-semver via [ValidatePattern]' {
        $err = & pwsh -NoProfile -File (Join-Path $script:Support 'bump-version.ps1') -Version 'abc' 2>&1
        $LASTEXITCODE | Should -Not -Be 0
    }

    It 'requires the -Version parameter' {
        # Mandatory parameter without value should fail in non-interactive mode.
        $err = & pwsh -NoProfile -NonInteractive -File (Join-Path $script:Support 'bump-version.ps1') 2>&1
        $LASTEXITCODE | Should -Not -Be 0
    }
}

Describe 'version-check.ps1' {
    It 'exits 0 on a clean repo and prints the OK marker' {
        $out = & pwsh -NoProfile -File (Join-Path $script:Support 'version-check.ps1')
        $LASTEXITCODE | Should -Be 0
        ($out -join "`n") | Should -Match 'OK: all'
    }
}

Describe 'cross-reference-audit.ps1' {
    It 'exits 0 on a clean repo' {
        $null = & pwsh -NoProfile -File (Join-Path $script:Support 'cross-reference-audit.ps1')
        $LASTEXITCODE | Should -Be 0
    }
}

Describe 'generate-catalog.ps1' {
    It 'emits valid JSON with mandatory top-level keys' {
        $json = & pwsh -NoProfile -File (Join-Path $script:Support 'generate-catalog.ps1') | Out-String
        $LASTEXITCODE | Should -Be 0
        $data = $json | ConvertFrom-Json
        $data.PSObject.Properties.Name | Should -Contain 'extensions'
        $data.PSObject.Properties.Name | Should -Contain 'presets'
    }
}

Describe 'dotnet-build.ps1 (PS-specific)' {
    It 'requires the -Target parameter (Mandatory attribute)' {
        $out = & pwsh -NoProfile -NonInteractive -File (Join-Path $script:FxScripts 'dotnet-build.ps1') 2>&1
        $LASTEXITCODE | Should -Not -Be 0
    }
}
