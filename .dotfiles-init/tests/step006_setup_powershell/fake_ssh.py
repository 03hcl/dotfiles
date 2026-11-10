"""Fake ssh used by test_profile.py.

Records the received arguments as a JSON line, then behaves like an ssh server:
runs the last argument (the remote command) with `sh -c` in the fake remote home.
"""

import json
import os
import subprocess
import sys


def main() -> int:
    args = sys.argv[1:]
    with open(os.environ["TEST_SSH_LOG"], "a", encoding="utf-8") as log:
        log.write(json.dumps(args) + "\n")

    busybox = os.environ.get("TEST_BUSYBOX")
    if not busybox:
        return 0

    home = os.environ["TEST_REMOTE_HOME"]
    env = {**os.environ, "HOME": home}

    # Guard against writing to the real ~/.ssh
    pwd = subprocess.run(
        [busybox, "sh", "-c", "cd && pwd"], env=env, capture_output=True, text=True, check=True
    ).stdout.strip()
    if not os.path.samefile(pwd, home):
        sys.exit(f"fake_ssh: 'cd' moves to '{pwd}', not to '{home}'")

    return subprocess.run([busybox, "sh", "-c", args[-1]], env=env, cwd=home).returncode


if __name__ == "__main__":
    sys.exit(main())
