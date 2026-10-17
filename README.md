# smallcrab

A patch-only fork of [h3adcr-b](https://github.com/Deadboy666/h3adcr-b).

Smallcrab does one thing: replace `steam.sh` and `client.sh` in your Steam install with the SLSsteam-patched versions from the h3adcr-b-modul3s repo. Nothing else.

It does **not**:

- Download or extract SLSsteam / Netsock.
- Downgrade the Steam client.
- Modify `config.yaml`.
- Install Cloud Redirect libraries or flatpaks.
- Install system packages.
- Kill or launch Steam.

If you need any of those, use the [full headcrab](https://github.com/Deadboy666/h3adcr-b).

## Prerequisites

Before running smallcrab you must already have:

- Steam installed (Native or Flatpak).
- SLSsteam's `library-inject.so` and `SLSsteam.so` in `~/.local/share/SLSsteam/` (Native) or `~/.var/app/com.valvesoftware.Steam/.local/share/SLSsteam/` (Flatpak).
- `~/.config/SLSsteam/config.yaml` (or its Flatpak equivalent) configured the way you want it. smallcrab reads it (read-only) to decide whether to apply the CloudRedirect variant of the patch.
- Steam **closed**. If Steam is running when you patch, the live process will overwrite your changes.

## Requirements

`wget`, `grep`. That's it.

## Usage

```
./headcrab.sh
```

The script is idempotent -- run it again and it just re-fetches the same files.

## How it picks the patch variant

- Native vs Flatpak is decided by whether `~/.var/app/com.valvesoftware.Steam/.steam/steam/` exists.
- CloudRedirect vs standard is decided by whether your existing `config.yaml` contains `DisableCloud: no`.

If neither config exists, smallcrab will create an empty config dir but won't write a `config.yaml` for you -- make one yourself.

## Caveats

- **No compatible-version check.** The full headcrab reads Steam's client manifest and downgrades if it's too new. smallcrab does not. If your Steam client is newer than what the patched `steam.sh` supports, Steam will refuse to launch. Verify compatibility yourself, or run the full headcrab once to handle the downgrade.
- **The patch URLs come from upstream modules.** They can go stale if the upstream `h3adcr-b-modul3s` repo restructures. If a fetch fails, that's the most likely cause.
- **CloudRedirect branch is read-only.** smallcrab never edits `config.yaml`. It only inspects `DisableCloud` to pick a URL.

## License / credit

Forked from [h3adcr-b](https://github.com/Deadboy666/h3adcr-b) by Deadboy666. The patch URLs and CloudRedirect branch logic come from the [h3adcr-b-modul3s](https://github.com/Deadboy666/h3adcr-b-modul3s) repo.

the headcrab approaches..
