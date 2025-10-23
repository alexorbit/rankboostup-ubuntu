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
  install   Instala o Google Chrome em /Applications utilizando o pacote oficial da Google (requer sudo).
  start     Inicia o RankBoostup em modo headless utilizando o Chrome instalado (execute sem sudo).
  stop      Interrompe instâncias do Chrome abertas por este script com o perfil configurado.

Variáveis de ambiente:
  RBU_CHROME_BIN       Caminho do binário do Chrome (padrão: autodetectar /Applications/Google Chrome.app).
  RBU_EXTENSION_DIR    Diretório da extensão (padrão: ${REPO_ROOT}).
  RBU_PROFILE_DIR      Diretório do perfil do navegador (padrão: ~/Library/Application Support/rankboostup-headless).
  RBU_START_URL        URL aberta ao iniciar (padrão: https://app.rankboostup.com/dashboard/traffic-exchange/?autostart=1).
  RBU_DEBUG_PORT       Porta de depuração remota (padrão: 9222).
  RBU_HEADLESS_MODE    "chrome" (padrão) para headless nativo ou "none" para abrir janela visível.
  RBU_NO_SANDBOX       Defina como 1 para adicionar --no-sandbox ao iniciar o Chrome.
  RBU_ENABLE_UNSAFE_SWIFTSHADER
                       Quando 1 (padrão), força o uso do SwiftShader para garantir WebGL em servidores sem GPU.
  RBU_EXTRA_CHROME_FLAGS
                       Flags adicionais repassadas ao Chrome (ex.: "--disable-gpu --disable-webgpu").
  RBU_LOGIN_EMAIL      Usuário/e-mail utilizado para realizar login automático antes de iniciar o exchange.
  RBU_LOGIN_PASSWORD   Senha correspondente a RBU_LOGIN_EMAIL para o login automático.
  RBU_LOGIN_TIMEOUT    Tempo máximo (segundos) aguardando o login automático concluir (padrão: 45).
  RBU_LOGIN_URL        Substitui a URL de login utilizada pelo processo automático (padrão: https://app.rankboostup.com/login/).
USAGE
}

detect_python() {
    if command -v python3 >/dev/null 2>&1; then
        printf '%s\n' python3
        return 0
    fi

    if command -v python >/dev/null 2>&1; then
        if python - <<'PY' >/dev/null 2>&1
import sys
sys.exit(0 if sys.version_info.major == 3 else 1)
PY
        then
            printf '%s\n' python
            return 0
        fi
    fi

    return 1
}

pick_free_port() {
    local python_bin
    if ! python_bin=$(detect_python); then
        return 1
    fi

    "${python_bin}" - <<'PY'
import socket

sock = socket.socket()
sock.bind(("127.0.0.1", 0))
port = sock.getsockname()[1]
sock.close()
print(port)
PY
}

auto_login_if_configured() {
    local chrome_bin="$1"
    local profile_dir="$2"

    local email="${RBU_LOGIN_EMAIL:-}"
    local password="${RBU_LOGIN_PASSWORD:-}"

    if [[ -z "$email" || -z "$password" ]]; then
        return 0
    fi

    local python_bin
    if ! python_bin=$(detect_python); then
        log "python3 é obrigatório para realizar o login automático, mas não foi encontrado no PATH."
        return 1
    fi

    local helper_script="${SCRIPT_DIR}/rbu_auto_login.py"
    if [[ ! -x "$helper_script" ]]; then
        log "Script auxiliar ${helper_script} ausente ou sem permissão de execução."
        return 1
    fi

    local login_url="${RBU_LOGIN_URL:-https://app.rankboostup.com/login/}"
    local login_timeout="${RBU_LOGIN_TIMEOUT:-45}"

    local port
    if ! port=$(pick_free_port); then
        log "Não foi possível reservar uma porta local para o DevTools."
        return 1
    fi

    log "Realizando login automático do RankBoostup."

    local -a login_flags=(
        "--headless=new"
        "--disable-gpu"
        "--hide-scrollbars"
        "--user-data-dir=${profile_dir}"
        "--remote-debugging-port=${port}"
        "--no-first-run"
        "--no-default-browser-check"
        "--disable-background-networking"
        "--disable-sync"
        "--metrics-recording-only"
        "--disable-default-apps"
        "--disable-component-extensions-with-background-pages"
        "--disable-extensions"
        "--disable-features=TranslateUI,PushMessaging,CloudMessaging"
        "--disable-gcm-driver"
        "--disable-machine-learning"
        "--disable-webgpu"
        "--ignore-certificate-errors"
        "--allow-insecure-localhost"
        "--window-size=1280,720"
    )

    "${chrome_bin}" "${login_flags[@]}" "${login_url}" >/dev/null 2>&1 &
    local chrome_pid=$!

    auto_login_cleanup() {
        if kill -0 "$chrome_pid" >/dev/null 2>&1; then
            kill "$chrome_pid" >/dev/null 2>&1 || true
            wait "$chrome_pid" 2>/dev/null || true
        fi
    }

    trap 'auto_login_cleanup' RETURN

    if ! "${python_bin}" "$helper_script" --port "$port" --email "$email" --password "$password" --timeout "$login_timeout"; then
        log "Falha ao realizar o login automático. Abortando start."
        return 1
    fi

    if kill -0 "$chrome_pid" >/dev/null 2>&1; then
        wait "$chrome_pid" 2>/dev/null || true
    fi

    trap - RETURN
    auto_login_cleanup || true

    log "Login automático concluído com sucesso."
}

require_macos() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        log "Este script só pode ser executado no macOS."
        exit 1
    fi
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        log "Este comando deve ser executado como root (use sudo)."
        exit 1
    fi
}

autodetect_chrome() {
    local candidate

    if [[ -n "${RBU_CHROME_BIN:-}" ]]; then
        if [[ -x "${RBU_CHROME_BIN}" ]]; then
            printf '%s\n' "${RBU_CHROME_BIN}"
            return 0
        fi
        log "O caminho informado em RBU_CHROME_BIN não é executável: ${RBU_CHROME_BIN}"
    fi

    local -a candidates=(
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        "/Applications/Google Chrome Beta.app/Contents/MacOS/Google Chrome"
        "/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome"
        "/Applications/Chromium.app/Contents/MacOS/Chromium"
    )

    for candidate in "${candidates[@]}"; do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

install_dependencies() {
    require_macos
    require_root

    if autodetect_chrome >/dev/null 2>&1; then
        log "Google Chrome já está instalado, pulando instalação."
        return
    fi

    local tmp_dir
    tmp_dir="$(mktemp -d /tmp/rbu-chrome.XXXXXX)"
    local dmg_path="${tmp_dir}/googlechrome.dmg"
    local mount_point="${tmp_dir}/mount"

    mkdir -p "$mount_point"

    cleanup() {
        if mount | grep -Fq "on ${mount_point} "; then
            hdiutil detach "$mount_point" -quiet || true
        fi
        rm -rf "$tmp_dir"
    }
    trap cleanup EXIT

    log "Baixando imagem do Google Chrome"
    curl -L --fail -o "$dmg_path" "https://dl.google.com/chrome/mac/stable/GGRO/googlechrome.dmg"

    log "Montando imagem DMG"
    hdiutil attach "$dmg_path" -nobrowse -quiet -mountpoint "$mount_point"

    local chrome_app="${mount_point}/Google Chrome.app"
    if [[ ! -d "$chrome_app" ]]; then
        log "Não foi possível localizar Google Chrome.app dentro da imagem montada"
        exit 1
    fi

    log "Copiando Google Chrome para /Applications"
    ditto "$chrome_app" "/Applications/Google Chrome.app"

    log "Desmontando imagem"
    hdiutil detach "$mount_point" -quiet || true

    trap - EXIT
    cleanup

    log "Instalação concluída"
}

start_browser() {
    require_macos

    local chrome_bin
    if ! chrome_bin="$(autodetect_chrome)"; then
        log "Não foi possível localizar o binário do Chrome. Execute o comando install ou defina RBU_CHROME_BIN."
        exit 1
    fi

    local extension_dir="${RBU_EXTENSION_DIR:-${REPO_ROOT}}"
    if [[ ! -d "$extension_dir" ]]; then
        log "Diretório da extensão não encontrado: ${extension_dir}"
        exit 1
    fi

    local profile_dir="${RBU_PROFILE_DIR:-${HOME}/Library/Application Support/rankboostup-headless}"
    if [[ "${profile_dir}" == ~* ]]; then
        profile_dir="${profile_dir/#~/${HOME}}"
    fi

    if ! mkdir -p "$profile_dir"; then
        log "Não foi possível criar o diretório de perfil ${profile_dir}. Verifique as permissões."
        exit 1
    fi

    if [[ ! -w "$profile_dir" ]]; then
        log "O diretório de perfil ${profile_dir} não é gravável pelo usuário atual."
        log "Se ele foi criado anteriormente com sudo, execute: sudo chown -R '$(id -un):$(id -gn)' '${profile_dir}'"
        exit 1
    fi

    if ! auto_login_if_configured "$chrome_bin" "$profile_dir"; then
        exit 1
    fi

    local start_url="${RBU_START_URL:-https://app.rankboostup.com/dashboard/traffic-exchange/?autostart=1}"
    local debug_port="${RBU_DEBUG_PORT:-9222}"
    local headless_mode="${RBU_HEADLESS_MODE:-chrome}"

    local -a chrome_flags=(
        "--user-data-dir=${profile_dir}"
        "--load-extension=${extension_dir}"
        "--disable-extensions-except=${extension_dir}"
        "--no-first-run"
        "--no-default-browser-check"
        "--disable-notifications"
        "--disable-popup-blocking"
        "--disable-background-networking"
        "--disable-dev-shm-usage"
        "--remote-debugging-port=${debug_port}"
        "--autoplay-policy=no-user-gesture-required"
        "--disable-features=TranslateUI,PushMessaging,CloudMessaging"
        "--disable-gcm-driver"
        "--ignore-certificate-errors"
        "--allow-insecure-localhost"
        "--test-type"
        "--window-size=1920,1080"
        "--disable-machine-learning"
        "--disable-webgpu"
    )

    if [[ "${RBU_ENABLE_UNSAFE_SWIFTSHADER:-1}" != "0" ]]; then
        log "Forçando SwiftShader para compatibilidade WebGL"
        chrome_flags+=("--use-angle=swiftshader" "--use-gl=angle" "--enable-unsafe-swiftshader")
    fi

    local extra_flags_raw="${RBU_EXTRA_CHROME_FLAGS:-}"
    if [[ -n "${extra_flags_raw}" ]]; then
        log "Anexando flags extras do Chrome a partir de RBU_EXTRA_CHROME_FLAGS"
        local -a extra_flags=()
        read -r -a extra_flags <<<"${extra_flags_raw}"
        if (( ${#extra_flags[@]} > 0 )); then
            chrome_flags+=("${extra_flags[@]}")
        fi
    fi

    if [[ ${RBU_NO_SANDBOX:-0} -eq 1 ]]; then
        chrome_flags+=("--no-sandbox")
    fi

    local -a launcher
    case "$headless_mode" in
        chrome|new|headless)
            log "Iniciando Chrome em modo headless nativo"
            launcher=("$chrome_bin" "${chrome_flags[@]}" "--headless=new" "--hide-scrollbars" "${start_url}")
            ;;
        none|gui|window)
            log "Iniciando Chrome com janela visível"
            launcher=("$chrome_bin" "${chrome_flags[@]}" "${start_url}")
            ;;
        *)
            log "Modo headless desconhecido: ${headless_mode}"
            exit 1
            ;;
    esac

    log "Utilizando diretório de perfil: ${profile_dir}"
    log "Carregando extensão a partir de: ${extension_dir}"
    log "Abrindo URL: ${start_url}"

    exec "${launcher[@]}"
}

stop_browser() {
    require_macos
    local profile_dir="${RBU_PROFILE_DIR:-${HOME}/Library/Application Support/rankboostup-headless}"
    if [[ "${profile_dir}" == ~* ]]; then
        profile_dir="${profile_dir/#~/${HOME}}"
    fi
    log "Encerrando processos do Chrome associados ao perfil ${profile_dir}"
    pkill -f "${profile_dir}" || true
}

main() {
    local command="${1:-}";
    case "$command" in
        install)
            install_dependencies
            ;;
        start)
            shift || true
            if [[ $EUID -eq 0 ]]; then
                if [[ -n "${SUDO_USER:-}" ]]; then
                    log "Detectado sudo. Reexecutando como usuário ${SUDO_USER} para iniciar o Chrome sem privilégios elevados."

                    local target_home=""
                    if target_home="$(eval echo "~${SUDO_USER}" 2>/dev/null)"; then
                        if [[ -n "${target_home}" ]]; then
                            local profile_dir
                            profile_dir="${RBU_PROFILE_DIR:-${target_home}/Library/Application Support/rankboostup-headless}"

                            if [[ "${profile_dir}" == ~* ]]; then
                                profile_dir="${profile_dir/#~/${target_home}}"
                            fi

                            if [[ -d "${profile_dir}" ]]; then
                                local owner=""
                                if [[ "$(uname -s)" == "Darwin" ]]; then
                                    owner="$(stat -f '%Su' "${profile_dir}" 2>/dev/null || true)"
                                else
                                    owner="$(stat -c '%U' "${profile_dir}" 2>/dev/null || true)"
                                fi

                                if [[ -n "${owner}" && "${owner}" != "${SUDO_USER}" ]]; then
                                    log "Ajustando proprietário do diretório de perfil ${profile_dir} para ${SUDO_USER}."
                                    chown -R "${SUDO_USER}" "${profile_dir}"
                                fi
                            fi
                        fi
                    fi

                    exec sudo -u "${SUDO_USER}" -- "$0" start "$@"
                fi
                log "O comando start não deve ser executado como root. Execute-o sem sudo."
                exit 1
            fi
            start_browser "$@"
            ;;
        stop)
            stop_browser
            ;;
        --help|-h|help|"")
            usage
            ;;
        *)
            log "Comando desconhecido: $command"
            usage
            exit 1
            ;;
    esac
}

main "$@"
