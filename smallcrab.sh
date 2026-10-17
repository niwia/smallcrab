#!/usr/bin/env bash
# smallcrab -- lightweight Steam launch-script patcher and inventory helper.
# Replaces steam.sh and client.sh with LD_AUDIT-enabled launchers from upstream
# and optionally creates steam.cfg to inhibit self-updates.

set -Eeuo pipefail

readonly SCRIPT_NAME="$(basename "$0")"

# Upstream patch & reference URLs
readonly UPSTREAM_CLIENT_URL="https://runn.i.ng//Deadboy666/SteamTracking/refs/heads/master/ClientExtracted/steam.sh"
readonly UPSTREAM_NATIVE_URL="https://runn.i.ng//Deadboy666/h3adcr-b-modul3s/refs/heads/main/headcrab_native.sh"
readonly UPSTREAM_FLATPAK_URL="https://runn.i.ng//Deadboy666/h3adcr-b-modul3s/refs/heads/main/headcrab_flatpak.sh"
readonly UPSTREAM_HEADCRAB_RAW_URL="https://raw.githubusercontent.com/Deadboy666/h3adcr-b/main/headcrab.sh"

readonly FLATPAK_STEAM_CANDIDATES=(
    "$HOME/.var/app/com.valvesoftware.Steam/.steam/steam"
    "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
)
readonly FLATPAK_SLSSTEAM_DIR="$HOME/.var/app/com.valvesoftware.Steam/.local/share/SLSsteam"

readonly NATIVE_STEAM_CANDIDATES=(
    "$HOME/.steam/steam"
    "$HOME/.local/share/Steam"
    "$HOME/.steam/root"
)
readonly NATIVE_SLSSTEAM_DIR="$HOME/.local/share/SLSsteam"

steam_dir=""
install_type=""
sls_dir=""
detected_client_version=""
target_client_version=""

# CLI options
opt_check_only=false
opt_patch_only=false
opt_cfg_only=false
opt_yes=false

usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

A lightweight Steam launcher patcher that installs the SLSsteam LD_AUDIT launch-script
patch (steam.sh and client.sh) and optionally creates steam.cfg to inhibit updates.

Options:
  -c, --check       Check and report Steam / SLSsteam status without making changes
  -p, --patch       Patch launch scripts (steam.sh & client.sh) non-interactively
  --cfg             Create steam.cfg non-interactively if missing
  -y, --yes         Auto-confirm all prompts (patch scripts and create steam.cfg)
  -h, --help        Show this help message and exit

EOF
}

find_steam_install() {
    for candidate in "${FLATPAK_STEAM_CANDIDATES[@]}"; do
        if [[ -d "$candidate" ]]; then
            steam_dir="$(readlink -f -- "$candidate")"
            install_type="Flatpak"
            if [[ -d "$FLATPAK_SLSSTEAM_DIR" ]]; then
                sls_dir="$FLATPAK_SLSSTEAM_DIR"
            elif [[ -d "$steam_dir/SLSsteam" ]]; then
                sls_dir="$steam_dir/SLSsteam"
            else
                sls_dir="$FLATPAK_SLSSTEAM_DIR"
            fi
            return 0
        fi
    done

    for candidate in "${NATIVE_STEAM_CANDIDATES[@]}"; do
        if [[ -d "$candidate" ]]; then
            steam_dir="$(readlink -f -- "$candidate")"
            install_type="Native"
            if [[ -d "$NATIVE_SLSSTEAM_DIR" ]]; then
                sls_dir="$NATIVE_SLSSTEAM_DIR"
            elif [[ -d "$steam_dir/SLSsteam" ]]; then
                sls_dir="$steam_dir/SLSsteam"
            else
                sls_dir="$NATIVE_SLSSTEAM_DIR"
            fi
            return 0
        fi
    done

    return 1
}

is_steam_running() {
    command -v pgrep >/dev/null 2>&1 && pgrep -x steam >/dev/null 2>&1
}

read_os_release() {
    local release_file
    for release_file in /etc/os-release /usr/lib/os-release; do
        if [[ -r "$release_file" ]]; then
            # os-release is shell-compatible; source only the trusted system file.
            # shellcheck disable=SC1090
            . "$release_file"
            printf '%s\n' "${PRETTY_NAME:-${ID:-Unknown Linux}}"
            return
        fi
    done
    printf '%s\n' "Unknown Linux"
}

manifest_version() {
    local manifest="$1"
    [[ -r "$manifest" ]] || return 1
    awk -F '"' '/"version"/ { print $4; exit }' "$manifest"
}

fetch_target_client_version() {
    local fetched=""
    if command -v curl >/dev/null 2>&1; then
        fetched="$(curl -fsSL --connect-timeout 3 --max-time 5 "$UPSTREAM_HEADCRAB_RAW_URL" 2>/dev/null | grep 'HeadcrabCompatibleClientVer=' | head -n 1 | awk -F'=' '{ print $2 }' | tr -d ' "\r\n' || true)"
    elif command -v wget >/dev/null 2>&1; then
        fetched="$(wget -qO- --timeout=5 "$UPSTREAM_HEADCRAB_RAW_URL" 2>/dev/null | grep 'HeadcrabCompatibleClientVer=' | head -n 1 | awk -F'=' '{ print $2 }' | tr -d ' "\r\n' || true)"
    fi

    if [[ -n "$fetched" && "$fetched" =~ ^[0-9]+$ ]]; then
        target_client_version="$fetched"
    else
        target_client_version=""
    fi
}

report_client_version() {
    local package_dir="$steam_dir/package"
    local manifest version channel
    local candidates=(
        steam_client_steamdeck_stable_ubuntu12.manifest
        steam_client_steamdeck_publicbeta_ubuntu12.manifest
        steam_client_ubuntu12.manifest
        steam_client_publicbeta_ubuntu12.manifest
        steam_client_steamdeck_stable_ubuntu12
        steam_client_ubuntu12
    )

    fetch_target_client_version

    for manifest in "${candidates[@]}"; do
        if version="$(manifest_version "$package_dir/$manifest")" && [[ -n "$version" ]]; then
            detected_client_version="$version"
            case "$manifest" in
                *publicbeta*) channel="Beta" ;;
                *) channel="Stable" ;;
            esac
            printf 'Steam client: %s (%s; %s)\n' "$version" "$channel" "$manifest"
            if [[ -n "$target_client_version" ]]; then
                if [[ "$detected_client_version" == "$target_client_version" ]]; then
                    printf 'Compatibility: Matches upstream Headcrab targeted version (%s)\n' "$target_client_version"
                else
                    printf 'Compatibility warning: Client version (%s) differs from upstream Headcrab targeted version (%s).\n' "$detected_client_version" "$target_client_version"
                fi
            else
                printf 'Compatibility: Could not check latest recommended compatible version from upstream (offline or unreachable).\n'
            fi
            return 0
        fi
    done

    printf 'Steam client version: unavailable (no readable client manifest found)\n'
}

check_slssteam_status() {
    local inject_lib="$sls_dir/library-inject.so"
    local sls_lib="$sls_dir/SLSsteam.so"
    if [[ -f "$inject_lib" && -f "$sls_lib" ]]; then
        printf 'SLSsteam libraries: present in %s\n' "$sls_dir"
    else
        printf 'SLSsteam libraries: NOT found in %s\n' "$sls_dir"
        printf '  Note: SLSsteam files (library-inject.so, SLSsteam.so) must be installed for LD_AUDIT to take effect.\n'
    fi
}

download_file() {
    local url="$1"
    local dest="$2"
    local tmp
    tmp="$(mktemp "${dest}.XXXXXX")"

    if command -v curl >/dev/null 2>&1; then
        if ! curl -fsSL "$url" -o "$tmp"; then
            rm -f -- "$tmp"
            return 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget -qO "$tmp" "$url"; then
            rm -f -- "$tmp"
            return 1
        fi
    else
        printf 'Error: Neither curl nor wget is available.\n' >&2
        rm -f -- "$tmp"
        return 1
    fi

    if [[ ! -s "$tmp" ]]; then
        printf 'Error: Download from %s was empty.\n' "$url" >&2
        rm -f -- "$tmp"
        return 1
    fi

    [[ -e "$dest" ]] && chmod u+w -- "$dest" 2>/dev/null || true
    mv -f -- "$tmp" "$dest"
}

patch_steam_scripts() {
    local client_url="$UPSTREAM_CLIENT_URL"
    local steam_url
    local patch_name

    if [[ "$install_type" == "Flatpak" ]]; then
        steam_url="$UPSTREAM_FLATPAK_URL"
        patch_name="Flatpak-SLSsteam"
    else
        steam_url="$UPSTREAM_NATIVE_URL"
        patch_name="Native-SLSsteam"
    fi

    printf '\nPatching Steam launch scripts in %s...\n' "$steam_dir"
    printf 'Using patch variant: %s\n' "$patch_name"

    printf '  -> Fetching client.sh...\n'
    if ! download_file "$client_url" "$steam_dir/client.sh"; then
        printf 'Error: Failed to fetch client.sh from %s\n' "$client_url" >&2
        return 1
    fi
    chmod 755 -- "$steam_dir/client.sh"
    printf '  -> client.sh installed successfully.\n'

    printf '  -> Fetching steam.sh (%s)...\n' "$patch_name"
    if ! download_file "$steam_url" "$steam_dir/steam.sh"; then
        printf 'Error: Failed to fetch steam.sh from %s\n' "$steam_url" >&2
        return 1
    fi
    chmod 555 -- "$steam_dir/steam.sh"
    printf '  -> steam.sh installed successfully (permissions set to 555).\n'

    printf 'Successfully patched steam.sh and client.sh for LD_AUDIT injection.\n'
}

prompt_read() {
    local -n _ref="$1"
    if [[ ! -t 0 ]] && [[ -e /dev/tty && -r /dev/tty ]]; then
        IFS= read -r _ref </dev/tty || _ref=""
    else
        IFS= read -r _ref || _ref=""
    fi
}

maybe_patch_steam() {
    if [[ -z "$target_client_version" ]]; then
        printf '\nNotice: Unable to check the latest recommended compatible version from upstream (offline or unreachable).\n'
        printf 'There is no guarantee that the LD_AUDIT launch scripts will work on this Steam build.\n'

        if ! "$opt_patch_only" && ! "$opt_yes"; then
            local proceed_answer
            printf 'Do you want to continue anyway? [y/N] '
            prompt_read proceed_answer
            case "$proceed_answer" in
                y|Y|yes|YES|Yes) ;;
                *)
                    printf 'Aborted launch-script patching.\n'
                    return 0
                    ;;
            esac
        fi
    elif [[ -n "$detected_client_version" && "$detected_client_version" != "$target_client_version" ]]; then
        printf '\nWARNING: Installed Steam client version (%s) does not match the version\n' "$detected_client_version"
        printf 'targeted by upstream Headcrab (%s).\n' "$target_client_version"
        printf 'There is no guarantee that the LD_AUDIT launch scripts will work on this Steam build.\n'

        if ! "$opt_patch_only" && ! "$opt_yes"; then
            local proceed_answer
            printf 'Do you want to continue anyway? [y/N] '
            prompt_read proceed_answer
            case "$proceed_answer" in
                y|Y|yes|YES|Yes) ;;
                *)
                    printf 'Aborted launch-script patching due to version mismatch.\n'
                    return 0
                    ;;
            esac
        fi
    fi

    if "$opt_patch_only" || "$opt_yes"; then
        patch_steam_scripts
        return $?
    fi

    local answer
    printf '\nPatch Steam launch scripts (steam.sh and client.sh with LD_AUDIT)? [Y/n] '
    prompt_read answer
    case "$answer" in
        n|N|no|NO|No)
            printf 'Skipped launch-script patching.\n'
            return 0
            ;;
        *)
            patch_steam_scripts
            ;;
    esac
}

maybe_create_steam_cfg() {
    local cfg="$steam_dir/steam.cfg"
    local answer tmp

    if [[ -e "$cfg" ]]; then
        printf '\nsteam.cfg already exists in %s (keeping unchanged).\n' "$steam_dir"
        return 0
    fi

    if ! "$opt_cfg_only" && ! "$opt_yes"; then
        printf '\nOptional step: create steam.cfg to inhibit Steam self-updates? [y/N] '
        prompt_read answer
        case "$answer" in
            y|Y|yes|YES|Yes) ;;
            *) printf 'Skipped steam.cfg.\n'; return 0 ;;
        esac
    fi

    tmp="$(mktemp "$steam_dir/.steam.cfg.XXXXXX")"
    if ! {
        printf '%s\n' 'BootStrapperInhibitAll=enable' 'BootStrapperForceSelfUpdate=disable' > "$tmp"
    }; then
        rm -f -- "$tmp"
        printf 'Could not write steam.cfg.\n' >&2
        return 1
    fi
    chmod 644 -- "$tmp"
    mv -n -- "$tmp" "$cfg"
    if [[ -e "$tmp" ]]; then
        rm -f -- "$tmp"
        printf 'steam.cfg appeared during creation; left it unchanged.\n'
        return 0
    fi
    printf 'Created %s.\n' "$cfg"
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--check|--dry-run)
                opt_check_only=true
                shift
                ;;
            -p|--patch)
                opt_patch_only=true
                shift
                ;;
            --cfg)
                opt_cfg_only=true
                shift
                ;;
            -y|--yes)
                opt_yes=true
                shift
                ;;
            -h|--help)
                usage
                return 0
                ;;
            *)
                printf 'Unknown option: %s\n' "$1" >&2
                usage >&2
                return 1
                ;;
        esac
    done

    printf 'smallcrab: Steam launch-script patcher & inventory\n'
    printf 'Operating system: %s\n' "$(read_os_release)"

    if ! find_steam_install; then
        printf 'No supported Steam install found. Checked:\n' >&2
        printf '  %s\n' "${FLATPAK_STEAM_CANDIDATES[@]}" "${NATIVE_STEAM_CANDIDATES[@]}" >&2
        return 1
    fi

    printf 'Steam install type: %s\n' "$install_type"
    printf 'Steam install directory: %s\n' "$steam_dir"
    report_client_version
    check_slssteam_status

    if "$opt_check_only"; then
        printf '\nCheck completed. No changes made.\n'
        return 0
    fi

    if is_steam_running; then
        printf '\nError: Steam is currently running. Please close Steam before patching.\n' >&2
        printf 'Overwriting launch scripts while Steam is active will cause conflicts or be reverted.\n' >&2
        return 1
    fi

    if "$opt_cfg_only"; then
        maybe_create_steam_cfg
        return $?
    fi

    maybe_patch_steam
    maybe_create_steam_cfg
}

main "$@"
