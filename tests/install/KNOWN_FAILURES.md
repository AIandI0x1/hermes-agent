# Confirmed historical upgrade limitations

These failures cannot be repaired by changing the update target: the failing code is already loaded from the starting release. This is an evidence register, not a skip list. The workflow still runs these legs and preserves their failing exit codes. A later failure must match the recorded cause before it receives this classification; the tag alone is not enough.

## Windows launcher self-lock

Classification: **unfixable in the update target for the exact released `hermes.exe update` path**.

| Starting release | Released commit | Install → update | Verified failing job |
|---|---|---|---|
| `v2026.3.12` | `a370ab8391ca5f8de7ebbc449f05cb0df36ade7c` | `installer-script` → `hermes-update` | [101514756800](https://github.com/ethernet8023/hermes-agent/actions/runs/34043635705/job/101514756800) |
| `v2026.4.8` | `86960cdbb0148145890e2ee90b4e157fa899f6e1` | `installer-script` → `hermes-update` | [101514755527](https://github.com/ethernet8023/hermes-agent/actions/runs/34043635705/job/101514755527) |

The running console launcher holds `venv/Scripts/hermes.exe` open. The old updater pulls the new checkout, then asks uv to replace that same executable during an editable install. Windows rejects the replacement with `Access is denied. (os error 5)`. The old updater's ZIP fallback repeats the dependency install and encounters the same lock.

Evidence required: the CLI update phase failed, the traceback identifies the running `hermes.exe/__main__.py`, and uv reports failure to remove that install's `Scripts/hermes.exe` with OS error 5. A generic access-denied error on another file does not match.

The March call is in the released `hermes_cli/main.py:1678-1683`, with the ZIP fallback at `1571-1576`. April calls `_install_python_dependencies_with_optional_fallback`, whose released body at `3295-3321` runs the installs without launcher quarantine. Those function objects were loaded before the checkout changed. May's sampled CLI update passed; do not classify it from this record.

Re-running the installer is a separate tested upgrade route. Invoking the old CLI through its venv Python is a possible recovery route, but is not silently substituted for the console-launcher leg.

## July Windows app offers only a manual update for script installs

Classification: **unfixable in the update target for the exact released app-button path**.

Starting release: `v2026.7.1`, commit `7c1a029553d87c43ecff8a3821336bc95872213b`.

| Install → update | Verified failing job |
|---|---|
| `installer-script` → `hermes-desktop-app-update` | [101514755236](https://github.com/ethernet8023/hermes-agent/actions/runs/34043635705/job/101514755236) |
| `installer-script+desktop` → `hermes-desktop-app-update` | [101514760893](https://github.com/ethernet8023/hermes-agent/actions/runs/34043635705/job/101514760893) |
| `installer-script+desktop` → `open-app-update` | [101514756508](https://github.com/ethernet8023/hermes-agent/actions/runs/34043635705/job/101514756508) |

These script installs have no staged updater. The released Electron code (`apps/desktop/electron/main.cjs:2212-2214`) logs `no staged updater; surfacing manual` and returns `{ ok: true, manual: true, command }`. It does not start an update. Each job's `logs/desktop.log` records that branch followed by `[updates] manual: hermes update`; no target checkout/result signal appears.

Evidence required: an app-update leg from this released commit and those explicit manual-update log entries. A hand-off timeout without the manual message is not this limitation. Desktop-installer installs have a different staged-updater path and are not covered by this classification.

## Not classified as unfixable

Onboarding click failures, zoom drift, native permission dialogs, AutoHotkey window waits, stale update markers, autostash conflicts, network failures, and generic timeouts remain actionable or unclassified until diagnosed. They must not inherit a historical label because they occurred on an old release.
