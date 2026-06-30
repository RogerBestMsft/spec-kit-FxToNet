"""G11: parity for the remaining support_scripts pairs.

`test_script_pairs_parity.py` covers version-check, cross-reference-audit,
generate-catalog and bump-version; `test_package_extensions.py` / `test_dotnet_build_*`
cover the rest. This file closes the remaining `support_scripts/` pairs:

* Every `.sh` has a `.ps1` twin and vice-versa (no unpaired support tool).
* `mcp-config-validate.{sh,ps1}` is run as a behavioral parity check (it is side-effect
  free). `deploy-extensions`, `remove-extensions` and `mcp-connectivity-check` are NOT
  executed here: they shell out to the external `specify` CLI / probe the network and
  mutate the host, so behavioral parity for them is intentionally out of scope.
"""

from __future__ import annotations

from pathlib import Path

from ._helpers import require_bash, require_pwsh, run


def _canonical(stem: str) -> str:
    return stem.replace("-", "").lower()


def _support(repo_root: Path) -> Path:
    return repo_root / "support_scripts"


def test_every_support_sh_has_ps1_twin(repo_root: Path) -> None:
    support = _support(repo_root)
    ps1_keys = {_canonical(p.stem) for p in support.glob("*.ps1")}
    missing = [p.name for p in sorted(support.glob("*.sh")) if _canonical(p.stem) not in ps1_keys]
    assert not missing, "support_scripts .sh without a .ps1 twin:\n  " + "\n  ".join(missing)


def test_every_support_ps1_has_sh_or_py_twin(repo_root: Path) -> None:
    support = _support(repo_root)
    other_keys = {_canonical(p.stem) for p in support.glob("*.sh")}
    other_keys |= {_canonical(p.stem) for p in support.glob("*.py")}
    missing = [p.name for p in sorted(support.glob("*.ps1")) if _canonical(p.stem) not in other_keys]
    assert not missing, "support_scripts .ps1 without a .sh/.py twin:\n  " + "\n  ".join(missing)


def test_mcp_config_validate_parity(repo_root: Path) -> None:
    bash = require_bash()
    pwsh = require_pwsh()
    sh = run([bash, str(_support(repo_root) / "mcp-config-validate.sh")], cwd=repo_root)
    ps = run(
        [pwsh, "-NoProfile", "-File", str(_support(repo_root) / "mcp-config-validate.ps1")],
        cwd=repo_root,
    )
    assert sh.returncode == ps.returncode == 0, (
        f"exit drift: sh={sh.returncode} ps={ps.returncode}\nsh:\n{sh.stdout}\n{sh.stderr}"
        f"\nps:\n{ps.stdout}\n{ps.stderr}"
    )
    assert "OK" in sh.stdout and "OK" in ps.stdout, (
        f"missing OK line:\nsh:\n{sh.stdout}\nps:\n{ps.stdout}"
    )
