"""CI-only Python stack snapshots for the opaque staged-updater hand-off.

No command arguments, environment, or frame locals are recorded. The real
updater runs unchanged; stacks identify where its child is blocked.
"""
import os

if os.environ.get("GITHUB_ACTIONS") == "true" and os.environ.get("HERMES_E2E_HANDOFF_TRACE"):
    import faulthandler
    from pathlib import Path

    _directory = Path(os.environ["HERMES_E2E_HANDOFF_TRACE"])
    _directory.mkdir(parents=True, exist_ok=True)
    _stream = (_directory / f"python-stacks-{os.getpid()}.log").open("a", encoding="utf-8")
    faulthandler.dump_traceback_later(90, repeat=True, file=_stream)
