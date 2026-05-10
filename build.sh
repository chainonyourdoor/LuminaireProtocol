#!/usr/bin/env bash
# ======================================================
# ✨ LUMINAIRE PROTOCOL
# ======================================================

set -eo pipefail

# ======================================================
# ⚙️ CONFIGURATION
# ======================================================

# --- 🏷️ Kernel Identity ---
KERNEL_NAME="LuminaireProtocol"
KERNEL_TAG="Alpha"
BUILD_USER="chainonyourdoor"
BUILD_HOST="LuminaireCI"

# --- 🗂️ Kernel Source ---
KERNEL_REPO="https://android.googlesource.com/kernel/common"
KERNEL_BRANCH="android14-6.1-lts"
DEFCONFIG="gki_defconfig"
ARCH="arm64"

# --- 📁 Directories ---
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="${ROOT_DIR}/workspace"
CLANG_DIR="${ROOT_DIR}/greenforce-clang"
CLANG_BIN="${CLANG_DIR}/bin"
KERNEL_SRC="${WORK_DIR}/kernel"
AK3_DIR="${WORK_DIR}/AnyKernel3"
OUT_DIR="${WORK_DIR}/out"
ZIP_DIR="${WORK_DIR}/zip"

# --- ⚡ Ccache ---
CCACHE_BIN="${ROOT_DIR}/ccache-bin/ccache"
CCACHE_WRAPPER_DIR="${ROOT_DIR}/ccache-wrappers"
export CCACHE_DIR="${CCACHE_DIR:-${ROOT_DIR}/.ccache}"
export CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-5G}"
export CCACHE_COMPRESS=1
export CCACHE_COMPRESSLEVEL=1

# --- 📦 Cache Dirs ---
CLANG_CACHE_DIR="${HOME}/clang-cache"
KERNEL_CACHE_DIR="${HOME}/kernel-cache"
AK3_CACHE_DIR="${HOME}/ak3-cache"

# --- 🗃️ Release ZIP Name ---
DATE=$(date +"%b%d")
ZIP_NAME="LuminaireProtocol-Vanilla-${DATE}R${GITHUB_RUN_NUMBER:-0}.zip"

# --- 📋 Log file ---
LOG_FILE="/tmp/luminaire-$(date +%s).log"
touch "$LOG_FILE"

# ======================================================
# 📦 IMPORT FUNCTIONS
# ======================================================
source "${ROOT_DIR}/functions.sh"

# ======================================================
# ⚡ CCACHE SETUP
# ======================================================
setup_ccache() {
    local CCACHE_HOME="${HOME}/ccache-bin"

    if [ ! -f "${CCACHE_HOME}/ccache" ]; then
        log "Building ccache-ECS from source..."
        sudo apt-get install -y --no-install-recommends \
            cmake ninja-build g++ libzstd-dev > /dev/null 2>&1

        git clone --depth=1 -b ccache-ECS-v1.0 https://github.com/cctv18/ccache-ECS /tmp/ccache-ECS
        cmake -S /tmp/ccache-ECS -B /tmp/ccache-build \
            -GNinja \
            -DCMAKE_BUILD_TYPE=Release \
            -DZSTD_FROM_INTERNET=OFF \
            -DENABLE_TESTING=OFF \
            -DENABLE_DOCUMENTATION=OFF \
            -DENABLE_IPO=ON \
            -DREDIS_STORAGE_BACKEND=OFF \
            -DHTTP_STORAGE_BACKEND=OFF > /dev/null 2>&1
        cmake --build /tmp/ccache-build -j$(nproc) > /dev/null 2>&1
        mkdir -p "${CCACHE_HOME}"
        cp /tmp/ccache-build/ccache "${CCACHE_HOME}/ccache"
        log "ccache-ECS built successfully ✅"
    fi

    mkdir -p "${ROOT_DIR}/ccache-bin"
    cp "${CCACHE_HOME}/ccache" "${ROOT_DIR}/ccache-bin/ccache"
    chmod +x "${ROOT_DIR}/ccache-bin/ccache"

    [ ! -f "$CCACHE_BIN" ] && log "ccache binary not found, skipping" && return 0

    mkdir -p "$CCACHE_WRAPPER_DIR"
    for tool in clang clang++ clang-14 clang-15 clang-16 clang-17 clang-18 clang-19 clang-20; do
        REAL_BIN="${CLANG_BIN}/${tool}"
        WRAPPER="${CCACHE_WRAPPER_DIR}/${tool}"
        if [ -f "$REAL_BIN" ]; then
            cat > "$WRAPPER" << WRAPPER_EOF
#!/usr/bin/env bash
exec "${CCACHE_BIN}" "${REAL_BIN}" "\$@"
WRAPPER_EOF
            chmod +x "$WRAPPER"
        fi
    done

    export PATH="${CCACHE_WRAPPER_DIR}:${PATH}"
    export CCACHE_COMPILER="${CLANG_BIN}/clang"
    export CCACHE_BASEDIR="$KERNEL_SRC"
    export CCACHE_IS_KERNEL_COMPILING="true"

    $CCACHE_BIN --zero-stats > /dev/null 2>&1 || true
    log "ccache ready | dir: ${CCACHE_DIR} | max: ${CCACHE_MAXSIZE}"
}

# ======================================================
# 🚀 MAIN
# ======================================================
main() {
    exec 1> >(tee -a "$LOG_FILE") 2>&1

    echo ""
    log "========================================"
    log "  ✨ Luminaire Protocol Build Start"
    log "  🖥️ CPU: $(nproc --all) cores"
    log "  💾 RAM: $(free -h | grep Mem | awk '{print $2}')"
    log "  📅 $(date)"
    log "========================================"
    echo ""

    mkdir -p "$WORK_DIR" "$OUT_DIR" "$ZIP_DIR"

    # ======================================================
    # 📥 CLONE KERNEL
    # ======================================================
    echo "::group::📥 Kernel Source"
    if [ "${USE_KERNEL_CACHE}" = "true" ] && [ -d "${KERNEL_CACHE_DIR}/arch" ]; then
        log "Restoring kernel source from cache..."
        cp -a "${KERNEL_CACHE_DIR}/." "${KERNEL_SRC}/"
        log "Kernel source restored from cache ✅"
    else
        log "Cloning kernel source from AOSP (${KERNEL_BRANCH})..."
        git clone -q --depth=1 \
            --filter=blob:limit=10M \
            -b "$KERNEL_BRANCH" \
            "$KERNEL_REPO" \
            "$KERNEL_SRC" || error "Failed to clone kernel!"
        log "Saving kernel source to cache..."
        mkdir -p "${KERNEL_CACHE_DIR}"
        rsync -a --exclude='.git' "${KERNEL_SRC}/" "${KERNEL_CACHE_DIR}/"
        log "Kernel source saved to cache ✅"
    fi
    log "Kernel source ready"
    echo "::endgroup::"

    # ======================================================
    # 🧰 DOWNLOAD CLANG
    # ======================================================
    echo "::group::🧰 Clang Toolchain"
    if [ "${USE_CLANG_CACHE}" = "true" ] && [ -d "${CLANG_CACHE_DIR}/bin" ]; then
        log "Restoring Clang from cache..."
        cp -a "${CLANG_CACHE_DIR}/." "${CLANG_DIR}/"
        log "Clang restored from cache ✅"
    else
        log "Downloading Greenforce Clang..."
        wget -qO- https://raw.githubusercontent.com/greenforce-project/greenforce_clang/refs/heads/main/get_clang.sh \
            | bash &> /dev/null
        [ ! -d "$CLANG_BIN" ] && error "Clang not found at ${CLANG_BIN}!"
        log "Saving Clang to cache..."
        mkdir -p "${CLANG_CACHE_DIR}"
        cp -a "${CLANG_DIR}/." "${CLANG_CACHE_DIR}/"
        log "Clang saved to cache ✅"
    fi
    set +o pipefail
    CLANG_VER=$(${CLANG_BIN}/clang --version 2>&1 | head -1 || true)
    LINUX_VERSION=$(make -C "$KERNEL_SRC" kernelversion 2>/dev/null | grep -v "make" | head -n 1 | tr -d '[:space:]' || true)
    COMPILER_STRING=$(${CLANG_BIN}/clang -v 2>&1 | head -1 | sed 's/(https.*//' | sed 's/ version//' || true)
    set -o pipefail
    log "Clang ready: ${CLANG_VER}"
    echo "LINUX_VERSION=${LINUX_VERSION}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    echo "COMPILER_STRING=${COMPILER_STRING}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    export PATH="${CLANG_BIN}:${PATH}"
    echo "::endgroup::"

    # ======================================================
    # ⚡ SETUP CCACHE
    # ======================================================
    echo "::group::⚡ Ccache Setup"
    setup_ccache
    echo "::endgroup::"

    # ======================================================
    # 📦 PREP MODE
    # ======================================================
    if [ "${PREP_MODE:-false}" = "true" ]; then
        echo "::group::📦 AnyKernel3 (Prep)"
        log "Prep mode: setting up AnyKernel3..."
        if [ "${USE_AK3_CACHE:-false}" = "true" ] && [ -d "${AK3_CACHE_DIR}" ]; then
            log "Restoring AnyKernel3 from cache..."
            mkdir -p "${AK3_DIR}"
            cp -a "${AK3_CACHE_DIR}/." "${AK3_DIR}/"
            log "AnyKernel3 restored from cache ✅"
        else
            git clone -q --depth=1\
                "https://x-access-token:${PERSONAL_TOKEN}@github.com/chainonyourdoor/VeilAK3" \
                "$AK3_DIR" || error "Failed to clone AK3!"
            log "Saving AnyKernel3 to cache..."
            mkdir -p "${AK3_CACHE_DIR}"
            cp -a "${AK3_DIR}/." "${AK3_CACHE_DIR}/"
            log "AnyKernel3 saved to cache ✅"
        fi
        echo "::endgroup::"
        log "✅ Prep mode complete."
        exit 0
    fi

    # ======================================================
    # 🏗️ BUILD KERNEL
    # ======================================================
    export KBUILD_BUILD_USER="$BUILD_USER"
    export KBUILD_BUILD_HOST="$BUILD_HOST"
    export KBUILD_BUILD_TIMESTAMP="$(git -C "$KERNEL_SRC" log -1 --format=%cd --date=format:'%a %b %d %T %Z %Y')"
    export KCFLAGS="-w"

    SHORT_COMMIT="$(git -C "$ROOT_DIR" rev-parse --short HEAD)"
    LOCALVERSION="-${KERNEL_NAME}-${KERNEL_TAG}/code.${SHORT_COMMIT}"
    touch "${KERNEL_SRC}/.scmversion"

    MAKE_ARGS=(
        -C "$KERNEL_SRC"
        O="$OUT_DIR"
        ARCH="$ARCH"
        CROSS_COMPILE=aarch64-linux-gnu-
        CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
        LLVM=1
        LLVM_IAS=1
        LOCALVERSION="$LOCALVERSION"
        -j"$(($(nproc --all) * 2 - 1))"
    )

    log "Generating defconfig..."
    make "${MAKE_ARGS[@]}" "$DEFCONFIG" || error "Defconfig failed!"

    log "Patching defconfig..."
    source "${ROOT_DIR}/gki_defconfig.sh"

    log "Syncing config..."
    make "${MAKE_ARGS[@]}" olddefconfig || error "olddefconfig failed!"

    log "Building kernel..."
    START_TIME=$(date +%s)

    (
        set +eo pipefail
        while true; do
            sleep 30
            ELAPSED=$(( $(date +%s) - START_TIME ))
            ELAPSED_FMT=$(printf "%02d:%02d:%02d" $((ELAPSED/3600)) $((ELAPSED%3600/60)) $((ELAPSED%60)))
            echo "[LOG] Still building... ⏱️ ${ELAPSED_FMT} elapsed" >> "$LOG_FILE"
        done
    ) &
    HEARTBEAT_PID=$!

    make "${MAKE_ARGS[@]}" || { kill "$HEARTBEAT_PID" 2>/dev/null; error "Build failed!"; }
    kill "$HEARTBEAT_PID" 2>/dev/null || true
    wait "$HEARTBEAT_PID" 2>/dev/null || true

    END_TIME=$(date +%s)
    BUILD_SECONDS=$(( END_TIME - START_TIME ))
    log "Build completed in ${BUILD_SECONDS}s"
    echo "BUILD_SECONDS=${BUILD_SECONDS}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true

    # ======================================================
    # 🔥 WARMING MODE
    # ======================================================
    if [ "${WARMING_MODE}" = "true" ]; then
        log "WARMING_MODE: skipping packaging ✅"
        exit 0
    fi

    # ======================================================
    # 📊 CCACHE STATS
    # ======================================================
    echo "::group::📊 Ccache Stats"
    [ -f "$CCACHE_BIN" ] && $CCACHE_BIN --show-stats 2>/dev/null || true
    echo "::endgroup::"

    # ======================================================
    # 📦 PACKAGE ZIP
    # ======================================================
    echo "::group::📦 Package ZIP"
    if [ "${USE_AK3_CACHE}" = "true" ] && [ -d "${AK3_CACHE_DIR}" ]; then
        log "Restoring AnyKernel3 from cache..."
        cp -a "${AK3_CACHE_DIR}/." "${AK3_DIR}/"
        log "AnyKernel3 restored from cache ✅"
    else
        git clone -q --depth=1 \
            "https://x-access-token:${PERSONAL_TOKEN}@github.com/chainonyourdoor/VeilAK3" \
            "$AK3_DIR" || error "Failed to clone AK3!"
        mkdir -p "${AK3_CACHE_DIR}"
        cp -a "${AK3_DIR}/." "${AK3_CACHE_DIR}/"
    fi

    KERNEL_IMG=""
    for img in Image Image.gz Image.gz-dtb Image-dtb; do
        BOOT_PATH="${OUT_DIR}/arch/${ARCH}/boot/${img}"
        if [ -f "$BOOT_PATH" ]; then
            KERNEL_IMG="$BOOT_PATH"
            log "Kernel image: $img"
            break
        fi
    done
    [ -z "$KERNEL_IMG" ] && error "Kernel image not found!"

    cp "$KERNEL_IMG" "${AK3_DIR}/"
    cd "$AK3_DIR"
    zip -r9 "${ZIP_DIR}/${ZIP_NAME}" . \
        -x "*.git*" -x "*.github*" -x "*.md" -x "LICENSE"
    cd "$ROOT_DIR"

    export ZIP_PATH="${ZIP_DIR}/${ZIP_NAME}"
    log "ZIP ready: ${ZIP_NAME}"
    echo "ZIP_NAME=${ZIP_NAME}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    echo "ZIP_PATH=${ZIP_PATH}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
    echo "::endgroup::"

    # ======================================================
    # 📲 SEND TO TELEGRAM
    # ======================================================
    echo "::group::📲 Telegram"
    if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ] && [ -f "${ZIP_PATH}" ]; then
        log "Sending ZIP to Telegram..."
        printf '<b>✨ LUMINAIRE PROTOCOL</b>\n\nLinux : %s\nDate : %s\nCompiler : <code>%s</code>' \
            "${LINUX_VERSION:-N/A}" "$(date +"%d %b %Y")" \
            "${COMPILER_STRING:-N/A}" > /tmp/luminaire_caption.txt
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
            -F "chat_id=${TELEGRAM_CHAT_ID}" \
            ${TELEGRAM_THREAD_ID_BUILD:+-F "message_thread_id=${TELEGRAM_THREAD_ID_BUILD}"} \
            -F "document=@${ZIP_PATH};filename=${ZIP_NAME}" || true
        log "ZIP sent ✅"
    fi
    echo "::endgroup::"

    echo ""
    log "========================================"
    log "  ✅ Build Complete!"
    log "  📦 ${ZIP_NAME}"
    log "========================================"
    echo ""
}

cleanup() {
    if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ] && [ -f "${LOG_FILE:-}" ]; then
        local CAPTION="📄 Full Build Log"
        [ -n "${BUILD_SECONDS:-}" ] && CAPTION="✅ Build Complete! ⏱️ ${BUILD_SECONDS}s | 📦 ${ZIP_NAME:-unknown}"
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
            -F "chat_id=${TELEGRAM_CHAT_ID}" \
            ${TELEGRAM_THREAD_ID_LOG:+-F "message_thread_id=${TELEGRAM_THREAD_ID_LOG}"} \
            -F "document=@${LOG_FILE};filename=build-$(date +%Y%m%d-%H%M).log" \
            -F "caption=${CAPTION}" || true
    fi
}
trap cleanup EXIT

main "$@"
