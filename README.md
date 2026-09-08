# Task Manager

Native Apple Silicon macOS app modeled on Windows Task Manager.

## Tabs
- **Processes** — Apps, background processes, and macOS processes with CPU, memory, disk, status, and End task
- **Performance** — Live CPU, memory, disk, network, and GPU graphs
- **App history** — CPU time and peak memory since the app was opened
- **Startup apps** — Login items, LaunchAgents, and LaunchDaemons
- **Users** — Signed-in accounts and their resource use
- **Details** — Flat process table with PID, threads, priority, and architecture
- **Services** — launchd jobs with start / stop / restart

## Requirements
- Apple Silicon Mac
- macOS 14 or later

The app is not sandboxed so it can list every process. Ending another user's or a system process can require administrator privileges. `kernel_task`, `launchd`, and a few other system processes are protected.

Per-process network and GPU counters are not published by macOS the way Windows ETW publishes them. Those columns stay at zero; system-wide network and GPU appear on the Performance tab.

## Build
```bash
cd project2/TaskManager
./build.sh
```
