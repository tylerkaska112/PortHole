Simulator harness for the library/settings screens (they cannot run in the real app on the simulator because the runtime links device-only libraries).
Copy to a scratch dir, add `Sources/` symlinks to app/Sources/UI/{Theme,LibraryView,SettingsView}.swift next to Stubs.swift, `xcodegen generate`, build for the simulator, launch.
