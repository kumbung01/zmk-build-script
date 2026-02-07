#!/bin/bash

# ============================
# Build target 정의
# ============================

TARGETS=(central left right)

declare -A TARGET_SHIELD
declare -A TARGET_BOARD
declare -A TARGET_OUTPUT

TARGET_SHIELD[central]="eyelash_sofle_central_dongle;prospector_adapter"
TARGET_BOARD[central]="xiao_ble"
TARGET_OUTPUT[central]="central.uf2"

TARGET_SHIELD[left]="eyelash_sofle_peripheral_left"
TARGET_BOARD[left]="nice_nano@2.0.0"
TARGET_OUTPUT[left]="left.uf2"

TARGET_SHIELD[right]="eyelash_sofle_peripheral_right"
TARGET_BOARD[right]="nice_nano@2.0.0"
TARGET_OUTPUT[right]="right.uf2"

# ============================
# 디렉토리
# ============================

OUTPUT_DIR="$WORKSPACE_DIR/app/build/output"
LOG_DIR="$WORKSPACE_DIR/app/build/logs"

# ============================
# 옵션 상태
# ============================

PRISTINE_FLAG="${ZMK_PRISTINE:-}"
USB_LOGGING_FLAG="${ZMK_USBLOG:-}"

MENUCONFIG=false
MENU_TARGET=""

SELECTED_TARGETS=()

# ============================
# 파라미터 처리
# ============================

for arg in "$@"; do
    case "$arg" in
        m)
            MENUCONFIG=true
            ;;
        1)
            SELECTED_TARGETS+=(central)
            MENU_TARGET="central"
            ;;
        2)
            SELECTED_TARGETS+=(left)
            MENU_TARGET="left"
            ;;
        3)
            SELECTED_TARGETS+=(right)
            MENU_TARGET="right"
            ;;
        all)
            SELECTED_TARGETS+=("${TARGETS[@]}")
            ;;
        -*)
            opts="${arg#-}"
            for ((i=0; i<${#opts}; i++)); do
                case "${opts:$i:1}" in
                    p) PRISTINE_FLAG="-p" ;;
                    l) USB_LOGGING_FLAG="zmk-usb-logging" ;;
                    *) echo "⚠ Unknown flag: -${opts:$i:1}" ;;
                esac
            done
            ;;
        *)
            echo "⚠ Unknown argument: $arg"
            ;;
    esac
done

# menuconfig 기본 대상
if [ "$MENUCONFIG" = true ] && [ -z "$MENU_TARGET" ]; then
    MENU_TARGET="central"
fi

# ============================
# menuconfig 모드
# ============================

if [ "$MENUCONFIG" = true ]; then
    t="$MENU_TARGET"

    SHIELD="${TARGET_SHIELD[$t]}"
    BOARD="${TARGET_BOARD[$t]}"
    build_dir="$WORKSPACE_DIR/app/build/${t}"

    echo "=============================="
    echo "Launching menuconfig"
    echo "Target : $t"
    echo "Board  : $BOARD"
    echo "Shield : $SHIELD"
    echo "=============================="

    west build "$PRISTINE_FLAG" \
        -d "$build_dir" \
        -b "$BOARD" \
        -- \
        -DSHIELD="$SHIELD" \
        -DZMK_CONFIG=/workspaces/zmk-config/zmk-sofle-dongle/config/ \
        -DBOARD_ROOT=/workspaces/zmk-config/zmk-sofle-dongle/

    west build -d "$build_dir" -t menuconfig
    exit 0
fi

# ============================
# 기본값: all
# ============================

if [ ${#SELECTED_TARGETS[@]} -eq 0 ]; then
    SELECTED_TARGETS=("${TARGETS[@]}")
fi

# ============================
# 중복 제거
# ============================

declare -A uniq
for t in "${SELECTED_TARGETS[@]}"; do uniq["$t"]=1; done
SELECTED_TARGETS=("${!uniq[@]}")

# ============================
# 디렉토리 준비
# ============================

rm -rf "$OUTPUT_DIR" "$LOG_DIR"
mkdir -p "$OUTPUT_DIR" "$LOG_DIR"

export ZMK_PRISTINE="$PRISTINE_FLAG"
export ZMK_USBLOG="$USB_LOGGING_FLAG"

PRISTINE_YN=${PRISTINE_FLAG:+yes}; PRISTINE_YN=${PRISTINE_YN:-no}
USBLOG_YN=${USB_LOGGING_FLAG:+yes}; USBLOG_YN=${USBLOG_YN:-no}

# ============================
# 빌드 계획 출력
# ============================

echo "=============================="
echo "Build plan summary:"
echo "Pristine build: $PRISTINE_YN"
echo "USB logging: $USBLOG_YN"
echo "Targets:"
for t in "${SELECTED_TARGETS[@]}"; do
    echo "  - $t"
    echo "      board : ${TARGET_BOARD[$t]}"
    echo "      shield: ${TARGET_SHIELD[$t]}"
done
echo "=============================="
echo "Logs in $LOG_DIR/"
echo "Files in $OUTPUT_DIR/"

# ============================
# 병렬 빌드
# ============================

for t in "${SELECTED_TARGETS[@]}"; do
(
    SHIELD="${TARGET_SHIELD[$t]}"
    BOARD="${TARGET_BOARD[$t]}"
    OUTPUT_NAME="${TARGET_OUTPUT[$t]}"

    build_dir="$WORKSPACE_DIR/app/build/${t}"
    log_file="${LOG_DIR}/${t}.log"

    echo "Building [$t] ($BOARD / $SHIELD)"
    start_time=$(date +%s)

    CMD=(west build "$PRISTINE_FLAG" -d "$build_dir" -b "$BOARD")
    [ -n "$USB_LOGGING_FLAG" ] && CMD+=(-S "$USB_LOGGING_FLAG")
    CMD+=(-- -DSHIELD="$SHIELD" \
              -DZMK_CONFIG=/work/zmk-config/zmk-sofle-dongle/config/ \
              -DBOARD_ROOT=/work/zmk-config/zmk-sofle-dongle/)

    if "${CMD[@]}" &> "$log_file"; then
        end_time=$(date +%s)
        cp "$build_dir/zephyr/zmk.uf2" "$OUTPUT_DIR/$OUTPUT_NAME"
        echo "✓ [$t] Done (${OUTPUT_NAME}) in $((end_time-start_time))s"
    else
        echo "✗ [$t] Failed (see $log_file)"
    fi
) &
done

wait
echo "All builds complete. Logs in $LOG_DIR/"
echo "Output UF2 files in $OUTPUT_DIR/"
