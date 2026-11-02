# smallcrab x64

A lightweight, 64-bit aware Steam launch-script patcher and SLSsteam helper for Linux (Native & Flatpak).

Smallcrab patches `steam.sh` and `client.sh` in your Steam installation to enable `LD_AUDIT` injection for SLSsteam on modern 64-bit systems (SteamRT64) while preventing update conflicts.

## Quick Install (Piped Run)

```sh
curl -sSL https://raw.githubusercontent.com/niwia/smallcrab/main/smallcrab.sh | bash
```

Or run non-interactively with auto-confirm:

```sh
curl -sSL https://raw.githubusercontent.com/niwia/smallcrab/main/smallcrab.sh | bash -s -- --yes
```

---

## Features

- **x64 SLSsteam Native Support**: Handles modern 64-bit SLSsteam where `library-inject.so` is an empty stub (0 bytes) and `SLSsteam.so` exports the audit entry points directly. Avoids glibc `file too short` errors.
- **SteamRT64 Safe**: Automatically detects and enables Steam Runtime 3 (SteamRT64). Removes legacy `.steam-disable-steamrt64-client` overrides so the 64-bit client (`steamrt64/steam`) runs instead of crashing in legacy 32-bit mode.
- **Direct Process Execution**: Uses `exec "$STEAM_CLIENT" "$@"` rather than broken subshell `source` and `cd package/` logic, preserving process hierarchy, arguments, exit codes, and signals.
- **Full Logging & Diagnostics**: Does not redirect stdout/stderr to `/dev/null`, ensuring you can see debug output and errors when troubleshooting.
- **In-Place File Preservation**: Backs up your stock Valve `steam.sh` to `steam.sh.valve.bak` and verifies `client.sh`.
- **Inhibit Self-Updates**: Optionally writes `steam.cfg` (`BootStrapperInhibitAll=enable`, `BootStrapperForceSelfUpdate=disable`) to prevent Steam from overwriting your patched launchers.
- **Reversible**: Includes a `--unpatch` option to cleanly restore stock Valve launch scripts at any time.

---

## Options

```
Usage: smallcrab.sh [OPTIONS]

Options:
  -c, --check       Check and report Steam / SLSsteam status without making changes
  -p, --patch       Patch launch scripts (steam.sh & client.sh) non-interactively
  -u, --unpatch     Restore stock Steam launch scripts (reverts steam.sh)
  --cfg             Create steam.cfg non-interactively if missing
  -y, --yes         Auto-confirm all prompts (patch scripts and create steam.cfg)
  -h, --help        Show this help message and exit
```

### Examples

```sh
# Check your system and SLSsteam status without modifying files
./smallcrab.sh --check

# Patch launch scripts non-interactively
./smallcrab.sh --patch

# Full run with auto-confirm (patch and create steam.cfg)
./smallcrab.sh --yes

# Restore stock Steam launch scripts
./smallcrab.sh --unpatch
```
