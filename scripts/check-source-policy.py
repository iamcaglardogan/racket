"""Repository guardrails, not a proof of runtime filesystem or network safety."""

from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
violations = []

for directory in (root / "RACKET", root / "Tests"):
    for path in sorted(directory.rglob("*.swift")):
        source = path.read_text()
        relative = path.relative_to(root)
        checks = [
            (r"\b(?:removeItem|unlink|unlinkat|rmdir)\s*\(", "permanent deletion API"),
            (r"\b(?:URLSession|NSURLConnection|NWConnection|NWListener)\b", "unapproved networking API"),
            (r"\bimport\s+(?:Network|CFNetwork)\b", "unapproved networking framework"),
        ]
        if relative != Path("RACKET/Core/Removal/RemovalEngine.swift"):
            checks.append((r"\btrashItem\s*\(", "Trash API outside RemovalEngine"))
        if relative.parts[:2] == ("RACKET", "Core"):
            checks.append((r"\bimport\s+(?:SwiftUI|AppKit)\b", "UI dependency in Core"))
        for pattern, description in checks:
            for match in re.finditer(pattern, source):
                line = source.count("\n", 0, match.start()) + 1
                violations.append(f"{relative}:{line}: {description}")

for path in sorted((root / "scripts").glob("*.sh")):
    for number, line in enumerate(path.read_text().splitlines(), 1):
        if not line.lstrip().startswith("#") and re.search(r"(?:^|[\s;|&])(?:rm|rmdir|unlink)(?:\s|$)", line):
            violations.append(f"{path.relative_to(root)}:{number}: destructive shell command")

if violations:
    print("\n".join(violations), file=sys.stderr)
    sys.exit(1)

print("Source safety guardrails passed. Runtime safety requires the dedicated test suites.")
