"""String-only regressions; no shell command under test is executed."""

import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("source_policy", Path(__file__).with_name("check-source-policy.py"))
policy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(policy)


class ShellCommandPolicyTests(unittest.TestCase):
    def test_literal_deletion_commands_are_rejected(self):
        for source in [
            'rm "$fixture"',
            '/bin/rm "$fixture"',
            '/bin/rmdir "$fixture"',
            '/usr/bin/unlink "$fixture"',
            '"/bin/rm" "$fixture"',
            "'/bin/rmdir' \"$fixture\"",
            '/usr/bin/sudo -n /bin/rm "$fixture"',
            '/usr/bin/sudo -n -u fixture -- "/bin/rm" "$fixture"',
            'command -- /bin/rm "$fixture"',
            'PATH=/bin /usr/bin/env -i /bin/rm "$fixture"',
            'printf done; /bin/rm "$fixture"',
            'true && /bin/rm "$fixture"',
            'if /bin/rmdir "$fixture"; then printf done; fi',
            'find "$fixture" -type f -delete',
            '/usr/bin/find "$fixture" -delete',
            '"/usr/bin/find" "$fixture" "-delete"',
            'sudo -n /usr/bin/find "$fixture" -delete # selected fixture',
        ]:
            with self.subTest(source=source):
                self.assertTrue(policy.has_destructive_shell_command(source))

    def test_comments_and_printed_data_are_not_commands(self):
        for source in [
            '# /bin/rm "$fixture"',
            '  # find "$fixture" -delete',
            'printf "%s\\n" "rm /tmp/example"',
            'printf "%s\\n" "/bin/rm"',
            'printf "%s\\n" "/usr/bin/find /tmp/example -delete"',
            'printf "%s\\n" ";" "/bin/rm"',
            'printf done # /bin/rm "$fixture"',
            '/usr/bin/find "$fixture" -type f -print0',
            'printf "%s\\n" "find" "-delete"',
            'mkdir -m 700 "$fixture"',
        ]:
            with self.subTest(source=source):
                self.assertFalse(policy.has_destructive_shell_command(source))


if __name__ == "__main__":
    unittest.main()
