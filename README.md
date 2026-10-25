# Pulse for Mac

A native, local-only macOS performance monitor for **Apple silicon Macs (M1 and newer) running macOS 14 Sonoma or later**, built with SwiftUI. No account, server, dependencies, administrator password, or background helper.

## Install the preview

1. Open the [GitHub preview release](https://github.com/AevarOfjord/Pulse-Mac-Monitoring/releases/tag/v1.0.0-preview.1).
2. Download **Pulse-1.0-AppleSilicon-Preview.zip** from Assets. GitHub's **Source code** archives contain the project rather than a ready-to-run app.
3. Extract the ZIP, drag **Pulse.app** into Applications, then open it.

The preview is locally signed and has not been notarized by Apple. If macOS blocks the first launch and you trust this download, open **System Settings → Privacy & Security → Open Anyway** for Pulse and confirm. See [Apple's instructions](https://support.apple.com/102445). Signing and notarization are still planned for a standard public installation experience.

Monitoring starts automatically. Closing the dashboard leaves the menu bar monitor running; choose **Quit Pulse** from the menu bar or press **Command-Q** to exit.

## Build from source

```sh
git clone https://github.com/AevarOfjord/Pulse-Mac-Monitoring.git
cd Pulse-Mac-Monitoring
./scripts/build-app.sh --open
```

Running the packaged app requires no developer tools. Building from source requires Apple Command Line Tools with Swift 6 or later. The build script explicitly produces an Apple silicon (`arm64`) app and signs it locally. Intel Macs are outside the supported scope.

Verified on an M5 Pro Mac running macOS 27.0.1. Other Apple silicon models and older supported macOS versions still need device testing. The deployment target of macOS 14 is an intended compatibility baseline, not confirmation that every supported version has been tested.

## Sharing a preview

Package the existing build:

```sh
./scripts/package-release.sh
```

This creates `build/Pulse-1.0-AppleSilicon-Preview.zip` and a SHA-256 checksum. The ZIP contains Pulse.app and installation notes. Source files and exported performance history are excluded.

Packaging removes debug symbol records with absolute developer build paths and excludes Finder metadata and extended attributes. The sanitized preview copy is signed again and verified. `.gitignore` excludes `build/`, `.build/`, and `.swiftpm/`; use Git to publish the source rather than uploading the entire working directory, which also contains local diagnostics and compiler caches.

The current preview is locally signed, without an Apple Developer ID signature or notarization. Downloaded copies may be blocked by Gatekeeper. For normal public installation, prepare a Developer ID-signed, notarized release using [Apple's distribution workflow](https://developer.apple.com/macos/distribution/).

Suggested compatibility wording for a demo: **“Pulse is a native performance monitor targeting Apple silicon Macs (M1 or newer) on macOS 14+. Early preview, currently verified on M5 Pro.”**

## Features

- CPU utilization, user/system activity, individual logical cores, and load averages.
- GPU device, renderer and tiler utilization, GPU cores, and allocated memory where the driver exposes them.
- Memory usage split into app, wired, and compressed memory; cached files, swap, and memory pressure.
- Startup disk capacity and aggregate disk read/write rates.
- Download/upload speeds and cumulative counters per Ethernet/Wi-Fi interface.
- Searchable process list with CPU, resident memory, PID, sorting, and executable paths.
- Thermal state, system uptime, and a compact menu bar summary.
- 1-, 2-, or 5-second sampling, pause/resume, up to five minutes of history, and JSON export.

Use the sidebar for details. Drag across a chart to inspect values. Process CPU can exceed 100% when using multiple cores. The process list refreshes every five seconds or the sampling interval, whichever is longer.

Shortcuts: **⌘⇧P** pauses/resumes; **⌘⇧E** exports history; **⌘Q** quits. Export saves measured system snapshots from the in-memory history, without process paths or names. Nothing is uploaded. History is cleared when the app quits.

## Measurements and limits

| Reading | Source and behavior |
| --- | --- |
| CPU | Deltas of Mach `host_processor_info` ticks. Whole-machine CPU is 0–100%; per-core values use the same scale. The first sample establishes a baseline. |
| Memory | Mach `host_statistics64` VM counters. Used = resident anonymous app pages (excluding purgeable pages) + wired + compressed. Available = physical − used; includes reclaimable cache. Swap and pressure use `sysctl` where permitted. |
| GPU | IOKit `IOAccelerator` driver performance statistics. On multi-GPU Macs the busiest available GPU is shown. These driver-defined keys vary by hardware and OS. Missing metrics say “Unavailable” or show a dash. |
| Disk | APFS Data volume capacity; `IOBlockStorageDriver` byte deltas across exposed block storage drivers. Free capacity excludes purgeable files and may differ from Finder. |
| Network | 64-bit `NET_RT_IFLIST2` interface counters for active `en*` Ethernet/Wi-Fi interfaces. VPN, loopback, and peer-to-peer traffic are excluded to avoid double counting. This measures current traffic, not maximum connection speed. |
| Processes | `/bin/ps` CPU accounting and RSS, not instantaneous CPU deltas. Shared resident pages can appear in multiple processes. |
| Thermal | `ProcessInfo.thermalState`, an OS severity level, not a temperature. |

Rates use actual elapsed monotonic time. New or reset counters need two samples; pausing/resuming resets the baselines. There are no synthetic readings or prefilled charts. GPU statistics depend on which counters the Apple silicon GPU driver exposes on the installed macOS version; missing readings show as unavailable. Temperature, fans, frequency, power draw, and battery health are not implemented.

Apple references: [Mach processor information](https://developer.apple.com/documentation/kernel/1502854-host_processor_info), [IOKit service matching](https://developer.apple.com/documentation/iokit/1514494-ioservicegetmatchingservices).

## Development and verification

```sh
swift build
./scripts/test.sh
swift run PulseDiagnostics
```

The diagnostic tool takes two real samples one second apart, prints JSON, and lists the busiest processes. Restricted terminals can block process enumeration and some `sysctl` readings; the app runs without an App Sandbox entitlement. CPU and rate calculations, tick wraparound, 64-bit counters, reset handling, memory accounting, and process-path parsing have nine Swift Testing tests. The test script explicitly loads the bundled Testing macro plugin for Command Line Tools versions that omit it from build commands.

For a restricted build environment, keep compiler caches within the project:

```sh
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
./scripts/test.sh
```

`--disable-sandbox` applies only to SwiftPM’s build subprocesses. The build script uses it for compatibility with restricted development environments. The app needs no privileged operations.

Source layout: `Sources/MonitorCore` contains the isolated sampler and calculations; `Sources/Pulse` contains the native dashboard; `Sources/PulseDiagnostics` is the live CLI check.
