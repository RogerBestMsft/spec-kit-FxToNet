"""G12: bash compatibility lint for every .sh in the repo.

Mirrors the PowerShell 5.1 lint on the bash side: every shell script must parse cleanly
(`bash -n`) and protect against masked pipe failures (`set -o pipefail`). Thin
`exec`-delegator wrappers are exempt from the strict-mode requirement because they hand
off to another script that owns it.
"""

from __future__ import annotations

import re
from pathlib import Path

from ._helpers import require_bash, run


PIPEFAIL_RE = re.compile(r"set\s+-[a-zA-Z]*o?\s*pipefail|set\s+-o\s+pipefail")
EXEC_DELEGATOR_RE = re.compile(r"^\s*exec\s+\S", re.MULTILINE)


def _all_sh(repo_root: Path) -> list[Path]:
    roots = [repo_root / "fx-to-dotnet" / "scripts", repo_root / "support_scripts"]
    files: list[Path] = []
    for root in roots:
        if root.is_dir():
            files.extend(p for p in root.glob("**/*.sh") if p.is_file())
    return sorted(files)


def test_all_sh_parse_clean(repo_root: Path) -> None:
    bash = require_bash()
    bad: list[str] = []
    for p in _all_sh(repo_root):
        res = run([bash, "-n", str(p)], cwd=repo_root)
        if res.returncode != 0:
            bad.append(f"{p.relative_to(repo_root)}: {res.stderr.strip()}")
    assert not bad, "bash -n syntax errors:\n  " + "\n  ".join(bad)


def test_all_sh_set_pipefail(repo_root: Path) -> None:
    bad: list[str] = []
    for p in _all_sh(repo_root):
        text = p.read_text(encoding="utf-8")
        if PIPEFAIL_RE.search(text):
            continue
        if EXEC_DELEGATOR_RE.search(text):
            continue  # thin wrapper; the delegated script owns strict mode
        bad.append(str(p.relative_to(repo_root)))
    assert not bad, (
        "Shell scripts must `set -o pipefail` (or be exec-delegators):\n  " + "\n  ".join(bad)
    )
