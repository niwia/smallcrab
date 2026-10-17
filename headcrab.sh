#!/usr/bin/env bash
#
# smallcrab -- patch-only fork of h3adcr-b
#
# What it does:
#   - Detects Steam install type (Flatpak vs Native).
#   - Reads the existing SLSsteam config.yaml (read-only) to decide whether
#     to apply the CloudRedirect variant of the patch.
#   - Replaces $SteamInstallDir/steam.sh and .../client.sh with the patched
#     versions from the h3adcr-b-modul3s repo, and fixes permissions.
#
# What it intentionally DOES NOT do (caller's responsibility):
#   - Does NOT modify SLSsteam config.yaml.
#   - Does NOT download or extract SLSsteam / Netsock.
#   - Does NOT downgrade the Steam client.
#   - Does NOT install system packages or touch the SLSsteam package on disk.
#   - Does NOT install Cloud Redirect libraries or flatpaks.
#   - Does NOT kill the running Steam process. Stop Steam yourself before
#     running this, otherwise the file replacement can race with the live
#     process and silently no-op.
#
# Prerequisites the caller must already have:
#   - SLSsteam's library-inject.so and SLSsteam.so must already exist in
#     $SLSsteamInstallDir (or $FlatpakSLSsteamInstallDir for Flatpak).
#   - SLSsteam config.yaml already created/configured as desired.
#   - Steam must be closed before running.
#
# Compatible client version is dictated by the upstream Headcrab_Native /
# Headcrab_Flatpak scripts. This script does NOT verify Steam's own client
# version -- if you are on a too-new Steam build, the patched steam.sh may
# refuse to launch. Verify compatibility yourself (or use the full headcrab
# to handle the downgrade).

set -u

#Paths
SteamInstallDir=$HOME/.steam/steam
FlatpakSteamInstallDir=$HOME/.var/app/com.valvesoftware.Steam/.steam/steam
FlatpakSLSsteamConfigDir=$HOME/.var/app/com.valvesoftware.Steam/.config/SLSsteam
SLSsteamConfigDir=$HOME/.config/SLSsteam

#Patch URLs (from h3adcr-b-modul3s)
Headcrab_Native="https://runn.i.ng//Deadboy666/h3adcr-b-modul3s/refs/heads/main/headcrab_native.sh"
Headcrab_Native_CR="https://runn.i.ng//Deadboy666/h3adcr-b-modul3s/refs/heads/cr-test/headcrab_native.sh"
Headcrab_Flatpak="https://runn.i.ng//Deadboy666/h3adcr-b-modul3s/refs/heads/main/headcrab_flatpak.sh"
Headcrab_Flatpak_CR="https://runn.i.ng//Deadboy666/h3adcr-b-modul3s/refs/heads/cr-test/headcrab_flatpak.sh"
Headcrab_Client="https://runn.i.ng//Deadboy666/SteamTracking/refs/heads/master/ClientExtracted/steam.sh"

flatpakcheck(){
    [ -d "$FlatpakSteamInstallDir" ]
}

whereSLSsteamconfig(){
    if [ -d "$FlatpakSLSsteamConfigDir" ]; then
        mkdir -p "$FlatpakSLSsteamConfigDir"
        cd "$FlatpakSLSsteamConfigDir" || return 1
    else
        mkdir -p "$SLSsteamConfigDir"
        cd "$SLSsteamConfigDir" || return 1
    fi
}

#Read-only check: does the user's existing SLSsteam config have CloudRedirect enabled?
crconfigcheck(){
    whereSLSsteamconfig
    grep -F "DisableCloud: no" config.yaml &> /dev/null
}

checkcrsteam(){
    if crconfigcheck; then
        echo "CloudRedirect: enabled in SLSsteam config -> using Headcrab-CR variant"
        cd "$SteamInstallDir/" || return 1
        rm -f steam.sh
        wget -O steam.sh "$Headcrab_Native_CR" || {
            echo "Failed to fetch $Headcrab_Native_CR"
            return 1
        }
        echo "Patched client.sh + steam.sh with Headcrab-CR"
    else
        echo "CloudRedirect: not enabled in SLSsteam config -> using standard Headcrab variant"
        cd "$SteamInstallDir/" || return 1
        rm -f steam.sh
        wget -O steam.sh "$Headcrab_Native" || {
            echo "Failed to fetch $Headcrab_Native"
            return 1
        }
        echo "Patched client.sh + steam.sh with Headcrab"
    fi
}

checkcrflatpaksteam(){
    if crconfigcheck; then
        echo "CloudRedirect: enabled in SLSsteam config -> using Headcrab-Flatpak-CR variant"
        cd "$FlatpakSteamInstallDir/" || return 1
        rm -f steam.sh
        wget -O steam.sh "$Headcrab_Flatpak_CR" || {
            echo "Failed to fetch $Headcrab_Flatpak_CR"
            return 1
        }
        echo "Patched client.sh + steam.sh with Headcrab-Flatpak-CR"
    else
        echo "CloudRedirect: not enabled in SLSsteam config -> using standard Headcrab-Flatpak variant"
        cd "$FlatpakSteamInstallDir/" || return 1
        rm -f steam.sh
        wget -O steam.sh "$Headcrab_Flatpak" || {
            echo "Failed to fetch $Headcrab_Flatpak"
            return 1
        }
        echo "Patched client.sh + steam.sh with Headcrab-Flatpak"
    fi
}

patchflatpaksteam(){
    cd "$FlatpakSteamInstallDir/" || return 1
    wget -O client.sh "$Headcrab_Client" || {
        echo "Failed to fetch $Headcrab_Client"
        return 1
    }
    chmod 777 steam.sh
    checkcrflatpaksteam
    chmod 555 steam.sh
    chmod +x client.sh
    echo "SLSsteamInstallType: Flatpak"
}

patchlocalsteam(){
    cd "$SteamInstallDir/" || return 1
    wget -O client.sh "$Headcrab_Client" || {
        echo "Failed to fetch $Headcrab_Client"
        return 1
    }
    chmod 777 steam.sh
    checkcrsteam
    chmod 555 steam.sh
    chmod +x client.sh
    echo "SLSsteamInstallType: Native"
}

patchsteam(){
    if flatpakcheck; then
        patchflatpaksteam
    else
        patchlocalsteam
    fi
}

main(){
    echo "smallcrab (patch-only) -- not downloading Steam, not modifying SLSsteam config"
    if [ ! -d "$SteamInstallDir" ] && [ ! -d "$FlatpakSteamInstallDir" ]; then
        echo "No Steam install found at:"
        echo "  $SteamInstallDir"
        echo "  $FlatpakSteamInstallDir"
        echo "Is Steam installed?"
        exit 1
    fi
    if command -v steam >/dev/null 2>&1 && pgrep -x steam >/dev/null 2>&1; then
        echo "Steam is currently running. Close it before patching (otherwise the"
        echo "replacement can be overwritten by the live process)."
        exit 1
    fi
    patchsteam
}

main
