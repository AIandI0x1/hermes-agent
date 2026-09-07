"""CI-only Python stack snapshots for the opaque staged-updater hand-off.

No command arguments, environment, or frame locals are recorded. The real
updater runs unchanged; stacks identify where its child is blocked.
"""
import os

if os.environ.get("GITHUB_ACTIONS") == "true" and os.environ.get("HERMES_E2E_HANDOFF_TRACE"):
    import faulthandler
    import sys
    from pathlib import Path

    _directory = Path(os.environ["HERMES_E2E_HANDOFF_TRACE"])
    _directory.mkdir(parents=True, exist_ok=True)
    _stream = (_directory / f"python-stacks-{os.getpid()}.log").open("a", encoding="utf-8")
    _stream.write(f"started pid={os.getpid()} parent={os.getppid()} executable={sys.executable}\n")
    _stream.flush()
    faulthandler.dump_traceback_later(90, repeat=True, file=_stream)

    # Call boundaries locate an early exit before the first timed stack dump.
    # Never record arguments, frame locals, or return values.
    _watched = {
        "cmd_update", "_cmd_update_impl", "_run_pre_update_backup",
        "_pause_windows_gateways_for_update", "find_gateway_pids",
        "_scan_gateway_pids", "_get_service_pids", "_install_hangup_protection",
        "_finalize_update_output", "load_config", "is_installed",
    }

    def _trace_calls(frame, event, arg):
        if event in ("call", "return") and frame.f_code.co_name in _watched:
            _stream.write(f"{event} {frame.f_code.co_filename}:{frame.f_lineno} {frame.f_code.co_name}\n")
            _stream.flush()
        elif event == "c_call" and getattr(arg, "__name__", "") in {"kill", "_exit", "abort"}:
            _stream.write(f"c_call {frame.f_code.co_filename}:{frame.f_lineno} {arg.__name__}\n")
            _stream.flush()

    sys.setprofile(_trace_calls)
