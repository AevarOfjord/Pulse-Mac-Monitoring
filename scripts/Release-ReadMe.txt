PULSE FOR MAC — EARLY PREVIEW

Compatibility
Apple silicon Macs (M1 or newer), including MacBook Air and MacBook Pro.
Requires macOS 14 Sonoma or later. Intel Macs are not supported.
Verified on an M5 Pro Mac running macOS 27.0.1; other models and macOS
versions have not yet been tested. GPU readings depend on the driver and OS.

Install
Extract the ZIP, drag Pulse.app into Applications, then open it.
Xcode, Command Line Tools, and an administrator helper are not required.

Distribution status
This preview is locally signed. It does not have an Apple Developer ID
signature or Apple notarization. macOS may block downloaded copies.
A signed and notarized release is needed for standard public installation.
https://developer.apple.com/macos/distribution/

Use
The sidebar opens CPU, GPU, memory, storage, network, and process details.
Choose a 1-, 2-, or 5-second refresh interval, or pause sampling.
Closing the dashboard leaves Pulse running in the menu bar.
Choose Quit Pulse from the menu bar or press Command-Q to exit.
Command-Shift-P pauses or resumes. Command-Shift-E exports history as JSON.

Notes
Metrics and up to five minutes of history stay on your Mac.
History clears when Pulse quits. There is no account, tracking, or upload.
The process table shows resident memory (RSS); compressed/swapped memory
can make an app's broader memory footprint substantially larger.
Thermal state is an OS severity level, not a temperature measurement.
Temperature, fan speed, power draw, and battery health are not included.
