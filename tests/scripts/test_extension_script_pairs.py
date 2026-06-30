"""G4: extension-script twin existence + declaration parity.

Golden rule #4 was only enforced for `support_scripts/`. This guards the extension's
own `fx-to-dotnet/scripts/`: every `bash/*.sh` has a PowerShell `powershell/*.ps1` twin
(and vice-versa), and whenever a command declares one twin it declares the other too.

Twin matching is name-shape tolerant: the bash side is kebab-case
(`mcp-connectivity-check.sh`) and the PowerShell side may be Pascal/verb-noun
(`Mcp-ConnectivityCheck.ps1`), so both names are reduced to a canonical key by removing
hyphens and lowercasing.
"""

from __future__ import annotations

from pathlib import Path


def _canonical(stem: str) -> str:
    return stem.replace("-", "").lower()


def _bash_dir(extension_dir: Path) -> Path:
    return extension_dir / "scripts" / "bash"


def _pwsh_dir(extension_dir: Path) -> Path:
    return extension_dir / "scripts" / "powershell"


def test_every_bash_script_has_ps1_twin(extension_dir: Path) -> None:
    ps1_keys = {_canonical(p.stem) for p in _pwsh_dir(extension_dir).glob("*.ps1")}
    missing: list[str] = []
    for sh in sorted(_bash_dir(extension_dir).glob("*.sh")):
        if _canonical(sh.stem) not in ps1_keys:
            missing.append(sh.name)
    assert not missing, "Bash scripts without a PowerShell twin:\n  " + "\n  ".join(missing)


def test_every_ps1_script_has_sh_twin(extension_dir: Path) -> None:
    sh_keys = {_canonical(p.stem) for p in _bash_dir(extension_dir).glob("*.sh")}
    missing: list[str] = []
    for ps1 in sorted(_pwsh_dir(extension_dir).glob("*.ps1")):
        if _canonical(ps1.stem) not in sh_keys:
            missing.append(ps1.name)
    assert not missing, "PowerShell scripts without a bash twin:\n  " + "\n  ".join(missing)


def test_declared_twins_are_declared_together(extension_dir: Path, extension_yml: dict) -> None:
    """If a command declares one twin, it must declare the other (matched by canonical key)."""
    errors: list[str] = []
    for cmd in extension_yml["provides"]["commands"]:
        scripts = [s.replace("\\", "/") for s in (cmd.get("scripts") or [])]
        bash_keys = {_canonical(Path(s).stem) for s in scripts if s.startswith("scripts/bash/")}
        pwsh_keys = {_canonical(Path(s).stem) for s in scripts if s.startswith("scripts/powershell/")}
        for key in bash_keys - pwsh_keys:
            errors.append(f"{cmd['name']}: bash script '{key}' declared without its PowerShell twin")
        for key in pwsh_keys - bash_keys:
            errors.append(f"{cmd['name']}: PowerShell script '{key}' declared without its bash twin")
    assert not errors, "Twin not declared alongside its pair:\n  " + "\n  ".join(sorted(errors))
