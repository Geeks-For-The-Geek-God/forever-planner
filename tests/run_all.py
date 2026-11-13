"""Runs every Forever Planner test against the stubbed WoW API. Exit code 1 if any fail."""
import os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
failed = []
for name in ("test.py", "test_catchup.py", "test_gear.py", "test_update.py", "test_talents.py", "test_traits.py"):
    print(f"=== {name}")
    r = subprocess.run([sys.executable, os.path.join(HERE, name)], capture_output=True, text=True)
    out = r.stdout + r.stderr
    print("\n".join(l for l in out.splitlines() if l.startswith(("PASS", "FAIL", "FAILURES", "Traceback", "  File", "lupa"))))
    if r.returncode != 0:
        failed.append(name)
print("\nAll tests passed." if not failed else f"\nFailed: {', '.join(failed)}")
sys.exit(1 if failed else 0)
