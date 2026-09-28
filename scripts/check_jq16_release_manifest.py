#!/usr/bin/env python3
"""Exercise the shared release-manifest jq filters with the runner's jq."""

from pathlib import Path
import os
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = ROOT / "templates/steps/release/build-manifest.yml.erb"
RESERVED = (
    "label|if|then|else|elif|end|as|def|reduce|foreach|try|catch|import|"
    "include|and|or|not|loc"
)


def extract(pattern: str, source: str, description: str) -> str:
    match = re.search(pattern, source, re.DOTALL)
    if not match:
        raise SystemExit(f"Could not extract {description} from {TEMPLATE}")
    return match.group("filter")


def run_jq(jq: str, filter_text: str, args: list[str]) -> str:
    result = subprocess.run(
        [jq, "-nc", *args, filter_text],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.rstrip("\n")


def main() -> None:
    jq = os.environ.get("JQ", "jq")
    source = TEMPLATE.read_text()

    # Keep the jq 1.6 reserved-word regression visible if somebody reintroduces
    # a reserved name in --arg/--argjson across actions, workflows, or scripts.
    offenders = []
    for base in (ROOT / "actions", ROOT / "templates", ROOT / ".github", ROOT / "scripts"):
        for path in base.rglob("*"):
            if path.suffix not in {".yml", ".yaml", ".sh", ".erb"}:
                continue
            text = path.read_text(errors="replace")
            if re.search(rf"--arg(?:json)?\s+(?:{RESERVED})\b", text):
                offenders.append(str(path.relative_to(ROOT)))
    if offenders:
        raise SystemExit("jq reserved-word argument names found:\n  " + "\n  ".join(offenders))

    package_filter = extract(
        r'--arg pkg_label "\$LABEL".*?--arg github_release "\$GITHUB_RELEASE"\s*\\\s*'
        r"'(?P<filter>.*?)'\)",
        source,
        "package manifest jq filter",
    )
    args = [
        "--arg", "pkg_label", "Synthetic SDK",
        "--arg", "emoji", "",
        "--arg", "tag", "v0.22.0",
        "--arg", "prev_release", "v0.21.0",
        "--arg", "pr_list", "PR #12: Add feature\nPR #13: Fix bug",
        "--arg", "notes", "U3ludGhldGljIHJlbGVhc2Ugbm90ZXMK",
        "--arg", "github_release", "true",
    ]
    output = run_jq(jq, package_filter, args)
    if '"label":"Synthetic SDK"' not in output or '"emoji"' in output:
        raise SystemExit(f"Unexpected package manifest output: {output}")

    registry_filter = extract(
        r"(?P<filter>\{name:\$name,.*?else \. end)'\)",
        source,
        "registry manifest jq filter",
    )
    registry = run_jq(
        jq,
        registry_filter,
        [
            "--arg", "name", "@example/widget",
            "--arg", "version", "0.22.0",
            "--arg", "url", "https://registry.example.test/@example%2Fwidget/v/0.22.0",
            "--arg", "channel", "latest",
            "--arg", "ap", "true",
        ],
    )
    if '"already_published":true' not in registry:
        raise SystemExit(f"Unexpected registry manifest output: {registry}")

    print(f"Passed release manifest jq compatibility checks with {subprocess.check_output([jq, '--version'], text=True).strip()}.")


if __name__ == "__main__":
    main()
