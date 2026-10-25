# Pulse verification

## Automated checks

Run `./scripts/test.sh`. Swift Testing checks the business-critical measurement and state logic; trivial view layout is checked in the app rather than mirrored with unit tests.

| Area | Type | Expected behavior / examples |
| --- | --- | --- |
| CPU and byte rates | Unit | Interval deltas, nice time, 32-bit CPU tick rollover, 64-bit network counters, reset/zero interval handling, multicore CPU >100%, PID reuse invalidates baseline. |
| Memory | Unit | System compressed pages counted once, cache excluded from used RAM; process footprint and RSS remain distinct; unavailable compressed counters remain nil. |
| Process grouping | Unit | Helpers attach to app ancestry; concurrent jobs keep separate identities; descendants counted once; reused parent PIDs and cycles cannot attach unrelated processes; partial counters identified. |
| Argument privacy | Unit | Decode exactly argc values and stop before environment; retain only command/project basename; malformed input and unsupported commands rejected. |
| Explanations | Unit | High usage or old swap alone gives no pressure alert; OS warning/critical and active swap do; CPU/GPU/thermal/disk signals independent. |
| Alert timing | Unit | Consecutive observations required, cooldown retained after recovery, gaps and pause resets cannot count as sustained load. |
| History | Unit/integration | 24-hour retention and bounds, chart endpoints, gap segments, JSON round trip, user-only file permissions, deletion, rejection of oversized files. |
| Temperatures | Unit | Reject missing/NaN/infinite/sentinel events; preserve distinct sensors with repeated names, deduplicate IDs, sanitize labels, classify known groups only, calculate maxima; five-second cache, clock reset/wake, missing events clear stale values; legacy snapshot decoding and compact private history round trip. |
| Native temperatures | Integration | `swift run --disable-sandbox PulseDiagnostics --temperatures --require-temperatures` on a physical supported Mac: valid native readings and two thermal reads across seven one-second system samples. Omit `--require-temperatures` on VMs or hardware without exposed sensors. |
| Native sampler | Integration | `swift run --disable-sandbox PulseDiagnostics --smoke`: CPU in range, physical memory present, own footprint/CPU available, CPU clock units agree with getrusage after a short busy period. No app names are emitted in smoke mode. |
| Distribution | Build/package | arm64 only, version/plist validity, signature verification, archive integrity and checksum, no absolute developer paths in executable. |

The GitHub workflow runs tests, native smoke, build, and packaging on macOS 15/26 Apple silicon runners. macOS 14 remains the deployment target but its retiring GitHub runner is excluded. Review actual run results; configuration alone does not establish compatibility. No secrets or Developer ID certificate are required for CI previews.

## Manual acceptance checks

- Open the release app. Overview shows real measurements and explains any elevated signal with evidence. Missing counters say unavailable. CPU and GPU details still work.
- Temperatures: check PMU die/battery/storage maxima against the available sensor list, all three °C trend choices and ranges, timestamps, pause/resume, and the same three metrics in History. Selected values stay in the chart header. Old history has gaps rather than zero-degree invented readings. Export includes summaries, without raw sensor labels/identifiers.
- Processes: search by name/PID/project, change sort, switch grouped/workloads/flat views, expand a group and process. Compare a compressed workload's footprint with RSS. Check parent, duration, and peak details. Concurrent similar jobs remain separate.
- History: change time range/metric; use the inspection slider to view contributors and their scan time. Pause/resume and minimize/reopen; charts must not bridge the interruption. Export JSON and inspect it for system-only data.
- Settings: choose a menu metric and sampling interval, relaunch and verify preferences. Hide/minimize/close the dashboard: native process scans should slow to 15 seconds with adaptive sampling enabled. Reopen through the menu bar.
- Test retained history using disposable session data: opt in, wait for a save, quit/reopen, disable retention, and confirm the file is deleted. Clear removes current session data too. Default preferences keep retention off.
- Notifications and launch at login require explicit opt-in. On a disposable test installation, verify allow/deny behavior, Send test notification, a sustained event, cooldown, login item registration, and unregister. Verify Refresh status after changing permission in System Settings. Do not change the user's login/notification settings without permission.
- Test sleep/wake and sustained overnight retention on a physical Mac. Check Gatekeeper installation from a real download; ad-hoc preview builds can be blocked as documented.

## Local clickthrough results · 2026-10-25

| Area | Observed result |
| --- | --- |
| Dashboard sections | Opened Overview, CPU, GPU, Memory, Temperatures, Storage, Network, Processes, and History with live data. Per-core activity, memory categories, disk capacity, and network interfaces rendered. |
| Temperatures | The M5 Pro exposed 52 valid readings from 77 HID services; missing events and invalid sentinels were omitted. Live PMU die, battery, and storage maxima rendered with original sensor labels. All three trend groups and 1/2/5-minute ranges worked. History inspection showed 72.0 °C PMU die, 34.5 °C battery, and 44.0 °C storage from the same selected sample. Pause held the sensor timestamp and values; Resume produced a fresh read. Export parsed with compact summaries and no raw sensor names/IDs. Native diagnostics verified five-second caching (about 76–81 ms per thermal read on this run). |
| Process controls | Apps & jobs, Workloads, and All processes; footprint/CPU/name sort; name/PID/project search; empty results; expanded group and process accounting all worked. |
| Workload grouping | Two lightweight test jobs produced two separate groups and a duplicate-job hint. Each group's helper appeared once. Both groups disappeared after their test jobs exited. |
| Charts and history | CPU chart ranges and all history ranges/metrics rendered. The history inspection slider changed the selected sample and contributor scan time. Pause/resume stopped and restarted sampling; restart gaps remained separate chart series. After the interaction fix, the user confirmed that click/drag readings appeared and remained visible after release. A supplied screenshot also showed both CPU and GPU chart readouts. |
| CPU inspection clarity | CPU inspection shows the selected timestamp and Total, User, and System from the same retained sample. A rendered readout was compared with its saved source snapshot and matched all three values. History's slider and chart now inspect the same full-resolution sample, independently of plot subsampling. The overview distinguishes the live total from historical readings. |
| Header inspection and paired metrics | Selected readings now appear between the panel title and subtitle, with no chart annotation covering the lines. A deterministic native UI fixture verified two different selected samples for CPU Total/User/System, GPU Device, network Download/Upload, and disk Read/Write. Compact and wide layouts were inspected, and clearing selection restored the hints. The production History header's timestamp and CPU total matched its details panel after slider inspection. |
| Sampling and preferences | 1/2/5-second choices worked. All four menu metrics and adaptive sampling settings were selectable. Relaunch preserved preferences. An exported interval log confirmed 2-second visible sampling and 5-second minimized sampling. |
| Saved history | Opt-in wrote a private mode-0600 file. Relaunch restored data. Disabling retention removed the file while keeping session data. Clear History emptied the UI and produced an empty export. Original session data was backed up and restored after this check. |
| Export | JSON parsed successfully and contained system metrics without app/project names. Exporting empty history produced `[]`. |
| Notifications | On an isolated QA bundle, authorization allowed the test request; macOS accepted it. Blocking permission disabled the test button. Refresh status reflected allowed/blocked changes. Enabling alerts while blocked kept event recording available without an unnecessary authorization error. Actual banner presentation was not independently observed. |
| Login item | On the isolated QA bundle, registration reported On and persisted after relaunch. Unregister returned Off. An actual login/reboot was not performed. |
| Menu bar panel | With the panel opened manually, live measurements, Pause, Resume, Settings, and Open Dashboard worked through native automation. The user confirmed that Quit Pulse closed the app. |
| Cleanup | Test processes stopped; QA alerts, login item, and notifications disabled. Main app's notifications remained Not requested; its original monitoring preferences and history were restored. |

The clickthrough found stale notification-permission text and adaptive-sampling help that did not reflect the toggle. Both were corrected. Settings now includes Refresh status and Send test notification. Internal chart-series legends are hidden. A manual drag check did not show a chart reading; chart inspection now has an explicit click/drag gesture, retains its selection after release, fits its annotation within the chart, and avoids clipping the annotation. This follows [Apple's chart interaction example](https://developer.apple.com/videos/play/wwdc2023/10037/).

Automated checks passed: 28 tests including temperature validation, caching, missing-event recovery, and legacy history compatibility. Native sampler/CPU-clock smoke, native thermal cadence, release build, and an extracted preview launch have been checked locally. Signature, archive, architecture, developer-path checks, and checksum validation passed. Private QA histories, exports, fixtures, and logs remain under ignored `build/` and are excluded from the release archive.

## Remaining manual checks

The native automation tool could not target the status icon or perform a chart drag (`noWindowsAvailable`), although dashboard AX controls and screenshots worked. Opening the menu panel required a manual click on the icon. The user completed the chart inspection and Quit checks and confirmed both passed; these checks are manual rather than automated regression coverage. History inspection through its slider was verified through native automation.

The main local validation machine is an M5 Pro on macOS 27.0.1. CI cannot validate every GPU driver, physical sleep/wake, menu bar layout, or M-series generation. Apple Developer signing/notarization cannot be exercised without a membership and identity. Local notification permission and login-item registration are not enabled automatically during development. Preview this release before recommending it as broadly verified across all M-series Macs.
