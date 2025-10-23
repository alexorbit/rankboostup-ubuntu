#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

usage() {
    cat <<USAGE
Usage: $(basename "$0") <command>

Commands:
  install   Install Google Chrome/Chromium and headless browsing dependencies (requires sudo).
  start     Launch RankBoostup in headless mode using the installed browser.
  stop      Stop every RankBoostup headless browser instance started by this script.

Environment variables:
  RBU_CHROME_BIN       Override the browser binary to use (default: autodetect google-chrome/chromium).
  RBU_EXTENSION_DIR    Directory containing the unpacked RankBoostup extension (default: ${REPO_ROOT}).
  RBU_PROFILE_DIR      Browser profile directory (default: ~/.config/rankboostup-headless).
  RBU_START_URL        URL opened when starting the session (default: https://app.rankboostup.com/dashboard/traffic-exchange/?autostart=1).
  RBU_DEBUG_PORT       Remote debugging port (default: 9222).
  RBU_VIRTUAL_SCREEN   Virtual screen size when using Xvfb (default: 1920x1080x24).
  RBU_HEADLESS_MODE    one of [xvfb|chrome|none] (default: xvfb). "chrome" uses Chrome's native headless mode, "none" runs normally.
  RBU_NO_SANDBOX       Set to 1 to add --no-sandbox when launching Chrome (default: enabled when running as root).
  RBU_ENABLE_UNSAFE_SWIFTSHADER
                       When 1 (default), forces SwiftShader for WebGL to avoid GPU initialization failures on headless servers.
USAGE
}

autodetect_chrome() {
    local candidate
    if [[ -n "${RBU_CHROME_BIN:-}" ]]; then
        if command -v "${RBU_CHROME_BIN}" >/dev/null 2>&1; then
            echo "${RBU_CHROME_BIN}"
            return 0
        fi
        log "Specified browser ${RBU_CHROME_BIN} not found"
    fi

    for candidate in google-chrome google-chrome-stable chromium-browser chromium; do
        if command -v "$candidate" >/dev/null 2>&1; then
            echo "$candidate"
            return 0
        fi
    done

    return 1
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        log "This command must be run as root or with sudo."
        exit 1
    fi
}

state_dir_for_profile() {
    local profile_dir="$1"
    printf '%s\n' "${profile_dir%/}/.rankboostup-headless-state"
}

set_dbus_environment() {
    local address="$1"
    export DBUS_SYSTEM_BUS_ADDRESS="$address"
    export DBUS_SESSION_BUS_ADDRESS="$address"
}

ensure_dbus_ready() {
    local profile_dir="$1"
    local state_dir
    state_dir=$(state_dir_for_profile "$profile_dir")
    mkdir -p "$state_dir"

    local pid_file="${state_dir}/dbus.pid"
    local socket_file="${state_dir}/system_bus_socket"
    local mode_file="${state_dir}/dbus.mode"

    if [[ -f "$pid_file" ]]; then
        local existing_pid
        existing_pid=$(cat "$pid_file" 2>/dev/null || true)
        if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
            local mode
            mode=$(cat "$mode_file" 2>/dev/null || true)
            if [[ "$mode" == "private" ]]; then
                set_dbus_environment "unix:path=${socket_file}"
            else
                set_dbus_environment "unix:path=/run/dbus/system_bus_socket"
            fi
            return 0
        fi
        rm -f "$pid_file" "$mode_file"
    fi

    rm -f "$socket_file"

    local system_socket="/run/dbus/system_bus_socket"
    if [[ -S "$system_socket" ]]; then
        printf '%s\n' "system" >"$mode_file"
        set_dbus_environment "unix:path=${system_socket}"
        return 0
    fi

    if ! command -v dbus-daemon >/dev/null 2>&1; then
        log "dbus-daemon not available; skipping D-Bus bootstrap"
        return 0
    fi

    if [[ $EUID -eq 0 ]]; then
        mkdir -p /run/dbus
        local sys_pid_file="/run/dbus/pid"
        if [[ -f "$sys_pid_file" ]]; then
            local sys_pid
            sys_pid=$(cat "$sys_pid_file" 2>/dev/null || true)
            if [[ -n "$sys_pid" ]] && ! kill -0 "$sys_pid" 2>/dev/null; then
                rm -f "$sys_pid_file" "$system_socket"
            fi
        fi

        log "Starting dedicated system D-Bus daemon for headless Chrome"
        local sys_pid
        if sys_pid=$(dbus-daemon --system --fork --print-pid 1 2>/dev/null); then
            printf '%s\n' "$sys_pid" >"$pid_file"
            printf '%s\n' "system-managed" >"$mode_file"
            set_dbus_environment "unix:path=${system_socket}"
            return 0
        else
            log "Warning: Failed to start system D-Bus daemon. Falling back to private session bus."
        fi
    fi

    local address="unix:path=${socket_file}"
    log "Launching private D-Bus system bus for headless Chrome (session)"
    local pid
    if pid=$(dbus-daemon --session --fork --print-pid 1 --address="${address}" 2>/dev/null); then
        printf '%s\n' "$pid" >"$pid_file"
        printf '%s\n' "private" >"$mode_file"
        set_dbus_environment "${address}"
    else
        log "Warning: Failed to start private D-Bus daemon. Chrome may continue with verbose D-Bus errors."
        rm -f "$pid_file" "$mode_file"
    fi
}

cleanup_managed_dbus() {
    local profile_dir="$1"
    local state_dir
    state_dir=$(state_dir_for_profile "$profile_dir")

    local pid_file="${state_dir}/dbus.pid"
    local mode_file="${state_dir}/dbus.mode"
    local socket_file="${state_dir}/system_bus_socket"

    if [[ -f "$mode_file" ]] && [[ -f "$pid_file" ]]; then
        local mode
        mode=$(cat "$mode_file" 2>/dev/null || true)
        local dbus_pid
        dbus_pid=$(cat "$pid_file" 2>/dev/null || true)
        case "$mode" in
            private)
                if [[ -n "$dbus_pid" ]] && kill -0 "$dbus_pid" 2>/dev/null; then
                    log "Stopping private D-Bus daemon (PID $dbus_pid)"
                    kill "$dbus_pid" || true
                fi
                rm -f "$socket_file"
                ;;
            system-managed)
                if [[ -n "$dbus_pid" ]] && kill -0 "$dbus_pid" 2>/dev/null; then
                    log "Stopping dedicated system D-Bus daemon (PID $dbus_pid)"
                    kill "$dbus_pid" || true
                fi
                if [[ -f /run/dbus/pid ]] && [[ $(cat /run/dbus/pid 2>/dev/null || true) == "$dbus_pid" ]]; then
                    rm -f /run/dbus/pid
                fi
                rm -f /run/dbus/system_bus_socket
                ;;
        esac
    fi

    rm -f "$pid_file" "$mode_file"
}

install_dependencies() {
    require_root

    log "Updating apt metadata"
    apt-get update -y

    log "Installing base packages (wget, gnupg, unzip, Xvfb, fonts, D-Bus)"
    apt-get install -y wget curl gnupg ca-certificates unzip xvfb fonts-liberation libu2f-udev xdg-utils dbus >/dev/null

    if ! command -v google-chrome >/dev/null 2>&1 && ! command -v google-chrome-stable >/dev/null 2>&1; then
        log "Configuring Google Chrome APT repository"
        install -d -m 755 /etc/apt/keyrings
        curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /etc/apt/keyrings/google-linux-signing-keyring.gpg
        cat <<'EOF_REPO' >/etc/apt/sources.list.d/google-chrome.list
### Added by rankboostup-headless.sh
### Provides Google Chrome stable builds
# shellcheck disable=SC2143
#
deb [arch=amd64 signed-by=/etc/apt/keyrings/google-linux-signing-keyring.gpg] http://dl.google.com/linux/chrome/deb/ stable main
EOF_REPO
        apt-get update -y
        log "Installing google-chrome-stable"
        apt-get install -y google-chrome-stable >/dev/null
    else
        log "Google Chrome already installed, skipping"
    fi

    log "Installation complete"
}

start_browser() {
    local chrome_bin
    if ! chrome_bin=$(autodetect_chrome); then
        log "Unable to locate a Chrome/Chromium binary. Run the install command first or set RBU_CHROME_BIN."
        exit 1
    fi

    local extension_dir="${RBU_EXTENSION_DIR:-${REPO_ROOT}}"
    if [[ ! -d "$extension_dir" ]]; then
        log "Extension directory '$extension_dir' not found"
        exit 1
    fi

    local profile_dir="${RBU_PROFILE_DIR:-$HOME/.config/rankboostup-headless}"
    mkdir -p "$profile_dir"

    ensure_dbus_ready "$profile_dir"

    local start_url="${RBU_START_URL:-https://app.rankboostup.com/dashboard/traffic-exchange/?autostart=1}"
    local debug_port="${RBU_DEBUG_PORT:-9222}"
    local virtual_screen="${RBU_VIRTUAL_SCREEN:-1920x1080x24}"
    local headless_mode="${RBU_HEADLESS_MODE:-xvfb}"
    local enable_unsafe_swiftshader="${RBU_ENABLE_UNSAFE_SWIFTSHADER:-1}"

    local -a chrome_flags=(
        "--user-data-dir=${profile_dir}"
        "--load-extension=${extension_dir}"
        "--disable-extensions-except=${extension_dir}"
        "--no-first-run"
        "--no-default-browser-check"
        "--disable-notifications"
        "--disable-popup-blocking"
        "--disable-dev-shm-usage"
        "--remote-debugging-port=${debug_port}"
        "--autoplay-policy=no-user-gesture-required"
        "--disable-background-networking"
        # Disable translation UI and push messaging to avoid deprecated GCM registrations
        "--disable-features=TranslateUI,PushMessaging,CloudMessaging"
        "--disable-gcm-driver"
        "--ignore-certificate-errors"
        "--allow-insecure-localhost"
        "--test-type"
        "--window-size=1920,1080"
        "--disable-machine-learning"
        "--disable-webgpu"
    )

    if [[ "$enable_unsafe_swiftshader" != "0" ]]; then
        log "Forcing SwiftShader for WebGL compatibility"
        chrome_flags+=("--use-angle=swiftshader" "--use-gl=angle" "--enable-unsafe-swiftshader")
    fi

    if [[ ${RBU_NO_SANDBOX:-0} -eq 1 || $EUID -eq 0 ]]; then
        chrome_flags+=("--no-sandbox")
    fi

    local extra_flags_raw="${RBU_EXTRA_CHROME_FLAGS:-}"
    if [[ -n "${extra_flags_raw}" ]]; then
        log "Appending extra Chrome flags from RBU_EXTRA_CHROME_FLAGS"
        local -a extra_flags=()
        read -r -a extra_flags <<<"${extra_flags_raw}"
        if (( ${#extra_flags[@]} > 0 )); then
            chrome_flags+=("${extra_flags[@]}")
        fi
    fi

    local -a launcher
    case "$headless_mode" in
        chrome|new)
            log "Starting Chrome using native headless mode"
            launcher=("$chrome_bin" "${chrome_flags[@]}" "--headless=new" "--hide-scrollbars" "${start_url}")
            ;;
        none)
            log "Starting Chrome with a visible window"
            launcher=("$chrome_bin" "${chrome_flags[@]}" "${start_url}")
            ;;
        *)
            log "Starting Chrome inside Xvfb virtual display (${virtual_screen})"
            launcher=(xvfb-run --auto-servernum --server-args="-screen 0 ${virtual_screen}" "$chrome_bin" "${chrome_flags[@]}" "${start_url}")
            ;;
    esac

    log "Using profile directory: ${profile_dir}"
    log "Using extension directory: ${extension_dir}"
    log "Opening URL: ${start_url}"

    exec "${launcher[@]}"
}

stop_browser() {
    local profile_dir="${RBU_PROFILE_DIR:-$HOME/.config/rankboostup-headless}"
    log "Stopping Chrome processes that use profile ${profile_dir}"
    pkill -f -- "${profile_dir}" || true
    cleanup_managed_dbus "$profile_dir"
}

main() {
    local command="${1:-}";
    case "$command" in
        install)
            install_dependencies
            ;;
        start)
            shift || true
            start_browser "$@"
            ;;
        stop)
            stop_browser
            ;;
        --help|-h|help|"")
            usage
            ;;
        *)
            log "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

main "$@"
