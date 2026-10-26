# Pulse for Mac · 2.0 preview

A native, local-only performance monitor for **Apple silicon Macs (M1 and newer), targeting macOS 14 Sonoma or later**. Built with SwiftUI and native macOS counters. No account, server, third-party dependencies, administrator password, or privileged helper.

Dashboards, charts, settings, and menu-bar panels follow macOS Light/Dark appearance. The menu-bar panel keeps Dashboard, pause/resume, Settings, and Quit in one compact action row. For Wi-Fi health and protection checks, see the separate [Pulse WiFi app](https://github.com/AevarOfjord/Pulse-Mac-Wifi).

## Install

Download the [Pulse 2.0 preview ZIP](https://github.com/AevarOfjord/Pulse-Mac-Monitoring/releases/download/v2.0.0-preview.2/Pulse-2.0-AppleSilicon-Preview.zip), or visit [Releases](https://github.com/AevarOfjord/Pulse-Mac-Monitoring/releases/tag/v2.0.0-preview.2) for the checksum and notes. GitHub's “Source code” archives contain the project, not an app. Extract the ZIP, drag **Pulse.app** into Applications, and open it.

Preview builds are locally signed and **not notarized**. If macOS blocks a download you trust, use **System Settings → Privacy & Security → Open Anyway**, following [Apple's instructions](https://support.apple.com/102445). Never disable Gatekeeper globally. Building from source is also available.

Verified locally on an **M5 Pro running macOS 27.0.1**. The CI workflow targets Apple silicon runners on macOS 15 and 26. A configured matrix is not evidence of a successful run; see [Actions](https://github.com/AevarOfjord/Pulse-Mac-Monitoring/actions) for results. macOS 14 remains the deployment target, but its [GitHub runner retires November 2, 2026](https://github.blog/changelog/2026-10-01-github-actions-macos-14-runner-image-retirement/). Other physical M-series Macs still need testing. Intel Macs are outside scope.

## What’s new in 2.0

1. **Better process accounting.** Physical footprint, RSS, peak footprint, parent PID, start time, and CPU deltas between scans. Identity includes PID and process start time to handle PID reuse. Per-process compressed bytes appear for Pulse itself; other tasks show unavailable when macOS restricts access.
2. **Apps and development workloads.** Group app helpers and descendants of recognized build/test/run commands. See project basenames when passed explicitly, running duration, group totals, and concurrent similar jobs. Expand any group to inspect its processes or switch to the flat list.
3. **Resource explanations.** Overview explains elevated macOS memory pressure, active swap I/O, busy CPU/GPU, serious thermal state, and low disk space. Ranked footprints and CPU consumers provide context, not proof of causation. High RAM usage or old swap usage alone does not trigger a warning.
4. **History and sustained alerts.** Up to 24 hours of session history with the five largest group footprints at each process scan. Optional local retention across restarts. Opt-in alerts require 30, 60, or 120 seconds of consecutive elevated observations, with a 15-minute cooldown per resource. Events remain visible in History even if notification permission is denied.
5. **Less monitoring overhead.** Native process APIs replace periodic `ps` subprocesses. Metadata is cached by process identity. When the dashboard is hidden, closed, or minimized, adaptive sampling uses at least 5 seconds for system metrics and 15 seconds for processes, and removes the chart views. Chart work is bounded to 240 observations.
6. **Saved preferences and release tooling.** Configurable menu bar metric, optional launch at login, saved sampling and process-view choices, Apple silicon CI, privacy checks in packaging, and Developer ID/notarization scripts for a future signed release.

CPU, GPU, logical cores, memory breakdown, disk capacity and activity, Ethernet/Wi-Fi traffic, thermal state, pause/resume, and JSON export remain available. **Temperatures** adds live PMU die, battery, and storage group maxima, sensor labels, and selectable °C history. Overview includes the three temperature readings. Use **Settings…** from the sidebar, menu bar, or **⌘,**. Closing the dashboard keeps the menu bar monitor running. Quit with **⌘Q**. **⌘⇧P** pauses/resumes; **⌘⇧E** exports retained system metrics.

Click or drag across a chart to inspect a reading. The selection remains after release, with its timestamp and values in the panel header, leaving the graph unobstructed. CPU selections show Total, User, and System; network selections show Download and Upload; disk selections show Read and Write. The overview's large CPU number identifies live or paused data separately. History's time slider selects the same sample in the chart header and contributor details. Inspection uses retained samples even when the plotted line is subsampled.

After enabling alerts, use **Send test notification** to check the notification request. macOS controls banner delivery and Focus settings. **Refresh status** rechecks permission after a change in System Settings; denied permission still permits events in History.

## History and privacy

Pulse makes no network requests. All measurements stay on your Mac unless you choose to export or share them.

- Disk retention and alerts are **off by default**. Session history is bounded to 24 hours. Recent 15-minute history retains the configured sampling resolution; older data keeps the last observation in each 30-second bucket. Charts subsample to 240 points, so brief peaks can be omitted.
- Pauses, sleep, restarts, and unavailable readings break chart lines. Alert observation duration resets across pauses and sleep. Process contributors are sampled less frequently than system metrics; History shows their scan timestamp.
- Enabling local retention writes `~/Library/Application Support/Pulse/history-v2.json`, at most once a minute, with user-only file permissions and an 8 MiB limit. Quitting can lose the last minute. The file contains system metrics and **app/workload names, including project basenames**. Disable retention to delete this file, or use **Clear all history** to clear saved and session history.
- Process executable paths are displayed in the live process details. Argument inspection retains only an allowed command category and an explicit project basename. Full arguments and environment values are discarded and never included in history.
- **JSON export contains system snapshots only**, without app names, project names, executable paths, or arguments. Notification bodies also omit app/project names. Pressure events are session-only.
- `.gitignore` excludes local builds, diagnostics, and exported JSON in `build/`. Do not commit exports elsewhere or upload the entire working folder.

## Measurements and limits

| Reading | Source and behavior |
| --- | --- |
| CPU | Mach `host_processor_info` tick deltas. Whole-machine and per-core utilization are 0–100%. First sample establishes a baseline. |
| Process CPU | `PROC_PIDTASKINFO` cumulative Mach CPU ticks, converted with `mach_timebase_info` before interval deltas, independently of footprint availability. A process can exceed 100% across cores. The smoke check compares interval deltas against `getrusage` without assuming the APIs share a lifetime baseline. |
| Process memory | `proc_pid_rusage` physical footprint, resident size, and peak footprint; resident-only fallback via `PROC_PIDTASKINFO`. Footprint is memory charged to a process, including compressed backing, not resident RAM. Group sums are approximate, can overlap shared allocations, and do not equal system RAM used. Missing members mark group footprint as partial. |
| Grouping | App bundle ancestry and parent PID chains, checked against start times with cycle guards. Recognizes `dotnet`, `node`, `npm`, `swift`, `xcodebuild`, and `cargo` with a direct `test/build/run/watch/publish/restore` subcommand. Project names are extracted from explicit `.csproj/.sln/.slnx/.xcodeproj/.xcworkspace` arguments. Reparented processes, implicit projects, and other command forms may remain separate. |
| System memory | Mach VM counters. Used = resident anonymous app pages (minus purgeable) + wired + compressed. Available = physical − used, including reclaimable cache. Swap usage and OS pressure use `sysctl` where permitted; swap I/O uses VM counter deltas. |
| GPU | IOKit `IOAccelerator` driver statistics; busiest exposed accelerator. Availability varies by hardware and OS. Per-app GPU attribution is unavailable. |
| Disk | APFS Data volume capacity and aggregate `IOBlockStorageDriver` read/write deltas. Free space excludes purgeable files and can differ from Finder. |
| Network | 64-bit `NET_RT_IFLIST2` counters on active `en*` Ethernet/Wi-Fi interfaces. VPN, loopback, and peer-to-peer traffic excluded to avoid duplicate counting. Measures traffic, not connection capacity. |
| Thermal | `ProcessInfo.thermalState`, an OS severity level, not temperature. |
| Temperature | Read-only Apple-vendor HID thermal events, resolved at runtime. Reads are cached for at least five seconds (six at a two-second system interval); service discovery is cached for a minute and reset after wake/restart. PMU die = highest valid `PMU tdie*` zone; battery/NAND labels determine the other two maxima. These zones are **not verified CPU/GPU core temperatures**. The sensor page retains original labels and distinguishes repeated names. Missing/nonfinite values and values outside −20…150 °C are omitted as implausible, not treated as thermal alerts. Unsupported hardware or macOS versions show unavailable. No administrator permission is needed. |

Explanation thresholds: CPU ≥85%, GPU ≥90%, memory pressure warning/critical or ≥20 MiB/s combined swap I/O, thermal serious/critical, and disk free <10%. These indicate resource signals, not a definitive diagnosis of application latency. No artificial health score is calculated.

Rates use actual monotonic elapsed time. New/reset counters need two samples. Restricted counters show a dash or “Unavailable”; they are not replaced with fabricated values. System and process scans are sequential observations rather than an atomic snapshot. Temperature history/exports contain the three optional group maxima and their sensor-read timestamp, not the full list or registry identifiers. Old history remains readable with temperatures absent. Temperature access uses private macOS interfaces and may change across releases. Fan speeds, frequency, power draw, and battery health are not implemented.

Primary references: [Apple XNU process accounting](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/bsd_kern.c), [Mach timebase](https://developer.apple.com/documentation/kernel/1462446-mach_timebase_info), [login items](https://developer.apple.com/documentation/servicemanagement/smappservice), [notification permissions](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications).

## Build and test

Requires Apple Command Line Tools or Xcode with **Swift 6+**; running a packaged app needs neither.

```sh
git clone https://github.com/AevarOfjord/Pulse-Mac-Monitoring.git
cd Pulse-Mac-Monitoring
./scripts/test.sh
swift run --disable-sandbox PulseDiagnostics --smoke
./scripts/build-app.sh --open
./scripts/package-release.sh
```

The preview archive is `build/Pulse-2.0-AppleSilicon-Preview.zip`, with a SHA-256 checksum alongside it. Packaging includes only the app and installation notes, excludes Finder metadata, strips debug source paths, checks for absolute developer paths, and verifies the local signature and architecture. Quit a running local build before rebuilding it.

`PulseDiagnostics` without `--smoke` prints real system metrics and the largest processes. Treat that output as private diagnostic data. Restricted terminals may block process enumeration or some sysctl readings; run the diagnostic in a normal local terminal. The app has no App Sandbox entitlement and needs no root access. SwiftPM's `--disable-sandbox` affects build subprocesses, not app privileges.

See [TESTING.md](TESTING.md) for coverage and manual checks, and [RELEASING.md](RELEASING.md) for optional Developer ID signing and notarization. The current maintainer has no Apple Developer Program membership, so 2.0 remains a locally signed preview.
