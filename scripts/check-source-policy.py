"""Repository guardrails, not a proof of runtime filesystem or network safety."""

from pathlib import Path
import re
import shlex
import sys


def has_destructive_shell_command(line: str) -> bool:
    """Recognize selected literal commands, not arbitrary shell evaluation.

    Preserve quotes while separating control operators so quoted printf data
    is not treated as another command. Expansion, eval, heredocs, and indirect
    execution still require review; this is not a complete shell parser.
    """
    lexer = shlex.shlex(line, posix=False, punctuation_chars=";&|()")
    lexer.whitespace_split = True
    lexer.commenters = "#"
    try:
        tokens = list(lexer)
    except ValueError:
        # Multiline quoting is outside this line-oriented guardrail.
        return False

    segments = [[]]
    for token in tokens:
        if re.fullmatch(r"[;&|()]+", token):
            segments.append([])
        else:
            segments[-1].append(token)

    for segment in segments:
        words = []
        for token in segment:
            try:
                decoded = shlex.split(token, comments=False, posix=True)
            except ValueError:
                decoded = [token]
            words.append(decoded[0] if len(decoded) == 1 else token)
        index = 0
        while index < len(words):
            word = words[index]
            if word in {"if", "then", "elif", "else", "do", "!", "{"} or re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", word):
                index += 1
                continue
            command = Path(word).name
            if command not in {"sudo", "command", "env", "exec", "nohup", "builtin"}:
                break
            index += 1
            while index < len(words) and words[index].startswith("-"):
                option = words[index]
                index += 1
                if option == "--":
                    break
                if command == "sudo" and option in {"-u", "-g", "-h", "-p", "-C", "-T", "-D", "-R"}:
                    index += 1
        if index == len(words) or index > len(words):
            continue
        command = Path(words[index]).name
        if command in {"rm", "rmdir", "unlink"}:
            return True
        if command == "find" and "-delete" in words[index + 1:]:
            return True
    return False


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    violations = []
    for directory in (root / "RACKET", root / "Tests", root / "scripts" / "fixtures"):
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
            if has_destructive_shell_command(line):
                violations.append(f"{path.relative_to(root)}:{number}: destructive shell command")

    if violations:
        print("\n".join(violations), file=sys.stderr)
        return 1
    print("Source safety guardrails passed. Runtime safety requires the dedicated test suites.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
