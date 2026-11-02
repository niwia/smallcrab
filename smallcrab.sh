#!/usr/bin/env bash
# smallcrab -- lightweight Steam launch-script patcher and inventory helper for SLSsteam (x64 & x86).
# Replaces steam.sh and client.sh with an x64-aware LD_AUDIT launch wrapper
# and optionally creates steam.cfg to inhibit self-updates.

set -Eeuo pipefail

readonly SCRIPT_NAME="$(basename "$0")"

# Upstream genuine Steam launch-script sources
readonly UPSTREAM_CLIENT_PRIMARY_URL="https://raw.githubusercontent.com/SteamDatabase/SteamTracking/master/ClientExtracted/steam.sh"
readonly UPSTREAM_CLIENT_FALLBACK_URL="https://runn.i.ng//Deadboy666/SteamTracking/refs/heads/master/ClientExtracted/steam.sh"
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
sls_arch="unknown"
has_steamrt64=false

# CLI options
opt_check_only=false
opt_patch_only=false
opt_unpatch=false
opt_cfg_only=false
opt_yes=false

usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

A lightweight Steam launcher patcher that installs an x64-aware SLSsteam LD_AUDIT
launch-script patch (steam.sh and client.sh) and optionally creates steam.cfg to
inhibit automatic bootstrapper updates.

Options:
  -c, --check       Check and report Steam / SLSsteam status without making changes
  -p, --patch       Patch launch scripts (steam.sh & client.sh) non-interactively
  -u, --unpatch     Restore stock Steam launch scripts (reverts steam.sh)
  --cfg             Create steam.cfg non-interactively if missing
  -y, --yes         Auto-confirm all prompts (patch scripts and create steam.cfg)
  -h, --help        Show this help message and exit

Examples:
  $SCRIPT_NAME               # Interactive patch & setup
  $SCRIPT_NAME --check       # Inspect environment without modifying files
  $SCRIPT_NAME --patch       # Patch launch scripts without prompting
  $SCRIPT_NAME --yes         # Full non-interactive patch and steam.cfg creation
  $SCRIPT_NAME --unpatch     # Revert steam.sh to stock

Piped usage:
  curl -sSL https://raw.githubusercontent.com/niwia/smallcrab/main/smallcrab.sh | bash

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
                printf 'Compatibility: Could not check upstream recommended version (offline or unreachable).\n'
            fi
            return 0
        fi
    done

    printf 'Steam client version: unavailable (no readable client manifest found)\n'
}

check_slssteam_status() {
    local sls_lib="$sls_dir/SLSsteam.so"
    local inject_lib="$sls_dir/library-inject.so"

    if [[ ! -f "$sls_lib" ]]; then
        printf 'SLSsteam libraries: NOT found in %s\n' "$sls_dir"
        printf '  Warning: SLSsteam.so is required for LD_AUDIT injection to take effect.\n'
        return 1
    fi

    # Detect SLSsteam.so ELF architecture
    if command -v file >/dev/null 2>&1; then
        local file_out
        file_out="$(file -bL "$sls_lib" 2>/dev/null || true)"
        case "$file_out" in
            *x86-64*|*x86_64*|*ELF*64-bit*)
                sls_arch="x86_64"
                ;;
            *80386*|*i386*|*i686*|*ELF*32-bit*)
                sls_arch="x86_32"
                ;;
            *)
                sls_arch="unknown"
                ;;
        esac
    fi

    if [[ -s "$inject_lib" ]]; then
        printf 'SLSsteam libraries: present in %s (%s, with active library-inject.so)\n' "$sls_dir" "$sls_arch"
    elif [[ -f "$inject_lib" ]]; then
        printf 'SLSsteam libraries: present in %s (%s, standalone with empty stub)\n' "$sls_dir" "$sls_arch"
    else
        printf 'SLSsteam libraries: present in %s (%s, standalone SLSsteam.so)\n' "$sls_dir" "$sls_arch"
    fi

    # Check SteamRT64 support in Steam directory
    if [[ -x "$steam_dir/steamrt64/steam" ]]; then
        has_steamrt64=true
        printf 'Steam runtime: SteamRT64 (64-bit client) is available\n'
    else
        has_steamrt64=false
        printf 'Steam runtime: legacy 32-bit client (steamrt64 not found)\n'
    fi

    if [[ -f "$steam_dir/.steam-disable-steamrt64-client" ]]; then
        printf 'Notice: .steam-disable-steamrt64-client detected (will be removed to ensure 64-bit operation)\n'
    fi

    return 0
}

download_file() {
    local url="$1"
    local dest="$2"
    local tmp
    tmp="$(mktemp "${dest}.XXXXXX")"

    if command -v curl >/dev/null 2>&1; then
        if ! curl -fsSL --connect-timeout 5 --max-time 30 "$url" -o "$tmp"; then
            rm -f -- "$tmp"
            return 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget -qO "$tmp" --timeout=30 "$url"; then
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

prompt_confirm() {
    local prompt_msg="$1"
    local default_yes="${2:-true}"
    local answer=""

    if "$opt_yes"; then
        return 0
    fi

    if [[ -t 0 ]]; then
        printf '%s ' "$prompt_msg"
        IFS= read -r answer || answer=""
    elif [[ -t 1 && -e /dev/tty && -r /dev/tty ]]; then
        printf '%s ' "$prompt_msg" > /dev/tty 2>/dev/null || printf '%s ' "$prompt_msg"
        IFS= read -r answer < /dev/tty 2>/dev/null || answer=""
    else
        # Non-interactive / piped without tty: follow default_yes
        if "$default_yes"; then
            printf '%s [auto-yes (non-interactive)]\n' "$prompt_msg"
            return 0
        else
            printf '%s [auto-no (non-interactive)]\n' "$prompt_msg"
            return 1
        fi
    fi

    if [[ -z "$answer" ]]; then
        "$default_yes" && return 0 || return 1
    fi

    case "$answer" in
        y|Y|yes|YES|Yes) return 0 ;;
        *) return 1 ;;
    esac
}

generate_steam_sh() {
    local target="$steam_dir/steam.sh"
    local tmp
    tmp="$(mktemp "${target}.XXXXXX")"

    cat << 'EOF' > "$tmp"
#!/usr/bin/env bash
# smallcrab x64 -- Steam launch-script wrapper for SLSsteam
set -eo pipefail

STEAMROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
STEAM_CLIENT="${STEAMROOT}/client.sh"

if [[ ! -x "${STEAM_CLIENT}" ]]; then
    printf 'smallcrab error: client launcher %s is missing or not executable.\n' "${STEAM_CLIENT}" >&2
    exit 1
fi

# Resolve SLSsteam directory
SLS_DIR="${SLSSTEAM_DIR:-}"
if [[ -z "${SLS_DIR}" ]]; then
    if [[ -d "${STEAMROOT}/SLSsteam" ]]; then
        SLS_DIR="${STEAMROOT}/SLSsteam"
    elif [[ "${STEAMROOT}" == *"/com.valvesoftware.Steam/"* ]]; then
        SLS_DIR="${HOME}/.var/app/com.valvesoftware.Steam/.local/share/SLSsteam"
    else
        SLS_DIR="${HOME}/.local/share/SLSsteam"
    fi
fi

# Setup LD_AUDIT libraries (x64 aware)
AUDIT_LIB="${SLS_DIR}/library-inject.so"
SLS_LIB="${SLS_DIR}/SLSsteam.so"
AUDIT=""

if [[ -f "${SLS_LIB}" ]]; then
    AUDIT="${SLS_LIB}"
    # In x64 builds, library-inject.so is typically an empty stub (0 bytes).
    # Only prepend library-inject.so if it is a real non-empty library.
    if [[ -s "${AUDIT_LIB}" ]]; then
        AUDIT="${AUDIT_LIB}:${AUDIT}"
    fi
fi

if [[ -n "${LD_AUDIT:-}" ]]; then
    AUDIT="${AUDIT:+${AUDIT}:}${LD_AUDIT}"
fi

# Ensure SteamRT64 client is active (remove legacy 32-bit force sentinel)
rm -f "${STEAMROOT}/.steam-disable-steamrt64-client" 2>/dev/null || true
rm -f "${STEAMROOT}/.crash" 2>/dev/null || true

cd "${STEAMROOT}"

if [[ -n "${AUDIT}" ]]; then
    export LD_AUDIT="${AUDIT}"
fi

exec "${STEAM_CLIENT}" "$@"
EOF

    chmod 555 "$tmp"
    [[ -e "$target" ]] && chmod u+w "$target" 2>/dev/null || true
    mv -f "$tmp" "$target"
}

patch_steam_scripts() {
    local client_file="$steam_dir/client.sh"
    local steam_file="$steam_dir/steam.sh"
    local need_download=true

    printf '\nPatching Steam launch scripts in %s...\n' "$steam_dir"

    # Step 1: Ensure client.sh is valid and present
    if [[ -s "$client_file" ]]; then
        if grep -q "STEAMROOT=" "$client_file" 2>/dev/null || grep -q "Starting SteamRT3" "$client_file" 2>/dev/null; then
            printf '  -> Using existing client.sh (%d bytes).\n' "$(wc -c < "$client_file")"
            need_download=false
        fi
    fi

    # If client.sh is missing/invalid, check if current steam.sh is the genuine Valve script
    if "$need_download" && [[ -s "$steam_file" ]]; then
        if grep -q "STEAMSCRIPT=" "$steam_file" 2>/dev/null || (grep -q "log ()" "$steam_file" 2>/dev/null && ! grep -q "smallcrab" "$steam_file" 2>/dev/null && ! grep -q "INJECT_SLS" "$steam_file" 2>/dev/null); then
            printf '  -> Backing up original Valve steam.sh to client.sh and steam.sh.valve.bak\n'
            cp -f "$steam_file" "$steam_dir/steam.sh.valve.bak"
            cp -f "$steam_file" "$client_file"
            need_download=false
        fi
    fi

    # If still need download, fetch genuine client.sh from upstream SteamTracking
    if "$need_download"; then
        printf '  -> Fetching genuine client.sh from upstream SteamTracking...\n'
        if ! download_file "$UPSTREAM_CLIENT_PRIMARY_URL" "$client_file"; then
            printf '  -> Primary URL failed, trying fallback...\n'
            if ! download_file "$UPSTREAM_CLIENT_FALLBACK_URL" "$client_file"; then
                printf 'Error: Failed to fetch client.sh from upstream.\n' >&2
                return 1
            fi
        fi
    fi

    chmod 755 "$client_file"
    printf '  -> client.sh installed successfully (permissions 755).\n'

    # Step 2: Install x64-aware steam.sh wrapper
    printf '  -> Installing x64 SLSsteam launch wrapper steam.sh...\n'
    generate_steam_sh
    printf '  -> steam.sh installed successfully (permissions 555).\n'

    # Step 3: Re-enable SteamRT64 if disabled
    if [[ -f "$steam_dir/.steam-disable-steamrt64-client" ]]; then
        rm -f "$steam_dir/.steam-disable-steamrt64-client" 2>/dev/null || true
        printf '  -> Removed .steam-disable-steamrt64-client to ensure 64-bit SteamRT64 client.\n'
    fi
    rm -f "$steam_dir/.crash" 2>/dev/null || true

    printf 'Successfully patched steam.sh and client.sh for x64 SLSsteam injection.\n'
}

unpatch_steam_scripts() {
    local steam_file="$steam_dir/steam.sh"
    local client_file="$steam_dir/client.sh"
    local bak_file="$steam_dir/steam.sh.valve.bak"

    printf '\nRestoring original Steam launch scripts in %s...\n' "$steam_dir"

    chmod u+w "$steam_file" 2>/dev/null || true

    if [[ -s "$bak_file" ]]; then
        mv -f "$bak_file" "$steam_file"
        chmod 755 "$steam_file"
        printf '  -> Restored steam.sh from backup.\n'
    elif [[ -s "$client_file" ]]; then
        cp -f "$client_file" "$steam_file"
        chmod 755 "$steam_file"
        printf '  -> Restored steam.sh from client.sh.\n'
    else
        printf '  -> No backup found. Re-fetching stock steam.sh from SteamTracking...\n'
        download_file "$UPSTREAM_CLIENT_PRIMARY_URL" "$steam_file"
        chmod 755 "$steam_file"
        printf '  -> Stock steam.sh restored.\n'
    fi

    rm -f "$client_file" 2>/dev/null || true
    printf '  -> Cleaned up client.sh.\n'

    if [[ -f "$steam_dir/steam.cfg" ]]; then
        if prompt_confirm "Remove steam.cfg?" false; then
            rm -f "$steam_dir/steam.cfg"
            printf '  -> Removed steam.cfg.\n'
        fi
    fi

    printf 'Restore complete. Steam launch scripts have been reverted to stock.\n'
}

maybe_patch_steam() {
    if [[ -z "$target_client_version" ]]; then
        printf '\nNotice: Unable to check the latest recommended compatible version from upstream (offline or unreachable).\n'
        if ! "$opt_patch_only" && ! "$opt_yes"; then
            if ! prompt_confirm "Do you want to continue anyway? [Y/n]" true; then
                printf 'Aborted launch-script patching.\n'
                return 0
            fi
        fi
    elif [[ -n "$detected_client_version" && "$detected_client_version" != "$target_client_version" ]]; then
        printf '\nWARNING: Installed Steam client version (%s) differs from version\n' "$detected_client_version"
        printf 'targeted by upstream Headcrab (%s).\n' "$target_client_version"
        if ! "$opt_patch_only" && ! "$opt_yes"; then
            if ! prompt_confirm "Do you want to continue anyway? [Y/n]" true; then
                printf 'Aborted launch-script patching due to version mismatch.\n'
                return 0
            fi
        fi
    fi

    if "$opt_patch_only" || "$opt_yes"; then
        patch_steam_scripts
        return $?
    fi

    if prompt_confirm "Patch Steam launch scripts (steam.sh and client.sh with x64 SLSsteam)? [Y/n]" true; then
        patch_steam_scripts
    else
        printf 'Skipped launch-script patching.\n'
    fi
}

maybe_create_steam_cfg() {
    local cfg="$steam_dir/steam.cfg"
    local tmp

    if [[ -e "$cfg" ]]; then
        printf '\nsteam.cfg already exists in %s (keeping unchanged).\n' "$steam_dir"
        return 0
    fi

    if ! "$opt_cfg_only" && ! "$opt_yes"; then
        if ! prompt_confirm "Optional step: create steam.cfg to inhibit Steam self-updates? [y/N]" false; then
            printf 'Skipped steam.cfg.\n'
            return 0
        fi
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
            -u|--unpatch|--restore)
                opt_unpatch=true
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

    printf 'smallcrab x64: Steam launch-script patcher & SLSsteam helper\n'
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
        printf '\nError: Steam is currently running. Please close Steam before modifying launch scripts.\n' >&2
        printf 'Overwriting launch scripts while Steam is active will cause conflicts or be reverted.\n' >&2
        return 1
    fi

    if "$opt_unpatch"; then
        unpatch_steam_scripts
        return $?
    fi

    if "$opt_cfg_only"; then
        maybe_create_steam_cfg
        return $?
    fi

    maybe_patch_steam
    maybe_create_steam_cfg
}

main "$@"
