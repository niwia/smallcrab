# smallcrab

A lightweight, patch-only fork of [h3adcr-b](https://github.com/Deadboy666/h3adcr-b).

Smallcrab replaces `steam.sh` and `client.sh` in your Steam install with the SLSsteam `LD_AUDIT` launch scripts from the upstream repository, and optionally creates `steam.cfg` to inhibit automatic Steam self-updates.

## What Smallcrab does

- Detects Native Steam and Flatpak Steam installations.
- Reports Linux distribution, Steam install paths, and Steam client version/channel (if manifest is found).
- Checks installed Steam client version against the compatible client version targeted by upstream Headcrab (`HeadcrabCompatibleClientVer`), warning before patching if there is a version mismatch.
- Checks whether SLSsteam libraries (`library-inject.so` and `SLSsteam.so`) exist in the expected directory.
- Replaces `$SteamInstallDir/client.sh` and `$SteamInstallDir/steam.sh` with the LD_AUDIT-enabled launchers from upstream, setting appropriate file permissions (`chmod 555 steam.sh` and `chmod 755 client.sh`).
- Identical file footprint: Writes files to the exact same paths and formats as Headcrab (`client.sh`, `steam.sh`, `steam.cfg`), allowing seamless interoperability without conflicting with existing or future Headcrab setups.
- Optionally creates `steam.cfg` to disable bootstrapper self-updates (`BootStrapperInhibitAll=enable` and `BootStrapperForceSelfUpdate=disable`).
- Safeguard: Refuses to patch if Steam is actively running to prevent live-process overwrite conflicts.

## What Smallcrab does NOT do

- Does not download or build SLSsteam binaries (`library-inject.so` / `SLSsteam.so`).
- Does not modify or read `config.yaml`.
- Does not install system distro packages (`apt`, `pacman`, `xbps`).
- Does not run the Steam client downgrade/manifest pipeline (`dgsc` / `dlm`).
- Does not launch or terminate Steam.

If you require the full automated installation pipeline (downgrading, binary downloads, system packages, config editing), see upstream [h3adcr-b](https://github.com/Deadboy666/h3adcr-b).

## Requirements

- Bash
- `awk`, `readlink`, `pgrep`
- `curl` or `wget`

## Usage

Interactive run:
```sh
./smallcrab.sh
```

### Options

```
Usage: smallcrab.sh [OPTIONS]

Options:
  -c, --check       Check and report Steam / SLSsteam status without making changes
  -p, --patch       Patch launch scripts (steam.sh & client.sh) non-interactively
  --cfg             Create steam.cfg non-interactively if missing
  -y, --yes         Auto-confirm all prompts (patch scripts and create steam.cfg)
  -h, --help        Show this help message and exit
```

Examples:

```sh
# Inventory check only:
./smallcrab.sh --check

# Patch launch scripts non-interactively:
./smallcrab.sh --patch

# Non-interactive full run (patch launch scripts and create steam.cfg):
./smallcrab.sh --yes
```

## Patch Variants

- **Native vs Flatpak**: Selected automatically based on detected Steam installation (`Native-SLSsteam` vs `Flatpak-SLSsteam`).

## Credit

Forked and adapted from [h3adcr-b](https://github.com/Deadboy666/h3adcr-b) by Deadboy666. Upstream launch scripts and modules provided by [h3adcr-b-modul3s](https://github.com/Deadboy666/h3adcr-b-modul3s).
