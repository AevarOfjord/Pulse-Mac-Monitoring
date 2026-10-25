PULSE FOR MAC 2.0 — PREVIEW

Compatibility
Apple silicon Macs (M1 or newer), including MacBook Air and MacBook Pro.
Targets macOS 14 Sonoma or later. Intel Macs are outside scope.
Verified locally on M5 Pro / macOS 27.0.1. Other physical Macs need testing.
GPU readings depend on driver and OS.

Install
Extract the ZIP, drag Pulse.app into Applications, then open it.
Developer tools, an account, and a privileged helper are not required.

Distribution status
The archive name ending in -Preview contains a locally signed app without
Apple Developer ID signing or notarization. macOS may block the download.
If you trust it, follow Apple's per-app Open Anyway instructions:
https://support.apple.com/102445
Archives without -Preview are created only after Developer ID, notarization,
and Gatekeeper checks pass. Do not disable Gatekeeper globally.

Use
Use the sidebar for CPU, GPU, memory, storage, network, processes, and history.
Overview explains elevated resource signals. Processes can be grouped by
app or recognized development job; expand to see footprint, RSS and details.
Settings controls the menu metric, adaptive sampling, optional launch at
login, notifications and history retention. Opt-in features start off.
Closing the dashboard leaves the menu bar monitor running.
Command-Q quits. Command-Shift-P pauses. Command-Shift-E exports system metrics.

Privacy and measurement notes
Pulse makes no network requests. History stays on your Mac.
Session history lasts up to 24 hours. Recent 15 minutes retain full resolution;
older data uses 30-second buckets. Charts subsample and can omit brief peaks.
Optional disk history includes app/workload names and project basenames;
turn retention off to delete it, or Clear all history to clear everything.
JSON exports contain system metrics only, without process names or paths.
Full command arguments and environment values are not retained.
Physical footprint differs from resident RAM and includes compressed backing.
Other processes' compressed-byte counters may be restricted by macOS.
Group totals are approximate and do not equal system RAM used.
Temperatures shows available PMU die, battery, and storage sensors in Celsius.
PMU die zones are not verified CPU/GPU core temperatures. Readings refresh
about every five seconds. Sensor availability varies by hardware and macOS;
private thermal interfaces may become unavailable after OS updates. Invalid
readings are omitted. History/exports store group maxima and their read time.
Thermal state is macOS's separate severity assessment. Fans, power draw,
and battery health are not collected.
