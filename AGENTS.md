# Agent Instructions

## About This Project

**Wiktionary Dictionary App** - A cross-platform dictionary app using Wiktionary data.

- **Rust core**: SQLite database with FTS5 search, exposed via C FFI
- **Android UI**: Jetpack Compose with JNI bindings to Rust
- **Data**: Preprocessed from kaikki.org Wiktionary dumps
- **Features**: Fast offline search, text selection integration (ACTION_PROCESS_TEXT), first-launch database download

Architecture details in `ARCHITECTURE.md`.

---

## Testing on Physical Devices

When debugging device-specific issues (especially arm64 vs x86_64), you can run tests directly on a user's connected phone:

### Setup
1. Ask user to connect phone via USB
2. Ask user to enable USB debugging (Settings → Developer Options → USB Debugging)
3. Ask user to approve the authorization popup on their phone
4. Verify connection: `adb devices` should show device as "device" not "unauthorized"

### Running Tests on Device
```bash
# Run all tests on connected physical device
./run-android-tests.sh --device

# Run specific diagnostic tests
adb shell am instrument -w -e class org.example.dictapp.DeviceDiagnosticTest \
  org.example.dictapp.test/androidx.test.runner.AndroidJUnitRunner

# Collect logs
adb logcat -d -s DeviceDiagnostic:D DictCore:D DictViewModel:D
```

### Useful ADB Commands
```bash
adb devices -l                    # List devices with details
adb install -r app.apk            # Install/reinstall APK
adb logcat -c                     # Clear logs
adb logcat -d                     # Dump logs
adb shell pm uninstall <package>  # Uninstall app
adb shell getprop ro.product.cpu.abi  # Check device architecture
```

### 16KB Page Size (Android 15+)
Devices running Android 15+ (SDK 35+) with arm64 may require 16KB page-aligned native libraries. Check with:
```bash
# Verify APK alignment
$ANDROID_SDK/build-tools/34.0.0/zipalign -c -v 4 app.apk | grep "\.so"
```

If alignment issues occur:
1. Ensure AGP 8.5+ in `android/build.gradle.kts`
2. Add to `core/.cargo/config.toml`: `rustflags = ["-C", "link-arg=-Wl,-z,max-page-size=16384"]`
3. Set `jniLibs.useLegacyPackaging = false` in app's `build.gradle.kts`

---

## E2E Testing and Automation

The `run-e2e.sh` script provides a unified interface for building, testing, and capturing screenshots/videos on both physical devices and emulators.

### Quick Start
```bash
# Capture screenshots (builds + installs automatically)
./run-e2e.sh capture --target device

# Or manually build and install first
./run-e2e.sh build
./run-e2e.sh install --target device

# Collect logs
./run-e2e.sh logs --target device --filter "DictCore:D DictViewModel:D *:S"

# Run tests
./run-e2e.sh test --target device --class DeviceDiagnosticTest
```

### Available Commands
- **build** - Build native libraries and APKs
- **install** - Install app and test APKs on target
- **logs** - Collect logcat output with optional filters
- **capture** - Automated screenshot and video capture (builds + installs by default)
- **test** - Run instrumentation tests
- **clean** - Clean all build artifacts

### Common Workflows

**Quick screenshot capture (one command):**
```bash
# Builds, installs, and captures automatically
./run-e2e.sh capture --target device

# Skip build if already installed
./run-e2e.sh capture --target device --skip-build
```

**Full rebuild and test on device:**
```bash
./run-e2e.sh clean
./run-e2e.sh build
./run-e2e.sh install --target device
./run-e2e.sh test --target device
```

**Fast iteration (screenshots only, no dark mode or video):**
```bash
./run-e2e.sh capture --target emulator --no-video --skip-dark --skip-build
```

**Debug specific issue:**
```bash
# Clear logs, reproduce issue, then collect
./run-e2e.sh logs --target device --clear
# ... reproduce issue ...
./run-e2e.sh logs --target device --filter "DictCore:D *:S"
```

Run `./run-e2e.sh --help` for full documentation.

**Note:** Old capture scripts (`capture-app-media.sh`, `capture-device-auto.sh`) are deprecated and redirect to `run-e2e.sh`.

---

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd sync               # Sync with git
```

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds

