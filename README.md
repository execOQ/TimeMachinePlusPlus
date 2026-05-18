# TimeMachine++

TimeMachine++ is a local macOS utility for managing Time Machine exclusions with manual paths, full-path regex rules, immediate previews, and a menu-bar workflow.

## Notes

- Time Machine does not expose a public pre-backup hook, so the app supports background readiness scans and a precise `Scan + Start Backup` action.
- Exclusions are applied through `/usr/bin/tmutil addexclusion`.
- Full Disk Access may be required for scanning protected folders or applying exclusions.

## Project

Open `TimeMachinePlusPlus.xcodeproj` in Xcode. The app source is organized like:

- `TimeMachinePlusPlus/App`
- `TimeMachinePlusPlus/Core`
- `TimeMachinePlusPlus/Features`
- `TimeMachinePlusPlusTests`

## Run

```sh
./script/build_and_run.sh
```
