#!/bin/bash
# ============================================================================
# VieLotusIM — benchmark ratchet gate
#
# Runs the regression suite N times in SEPARATE processes and gates on the
# WORST result per metric, because a single lucky run is not evidence. (Same
# reasoning as running a CI perf gate in three processes: shared runners have
# long noise windows that min-of-N inside one process cannot filter out.)
#
#   ./scripts/benchmark_ratchet.sh              gate against scripts/ratchet_floors.env
#   ./scripts/benchmark_ratchet.sh --ratchet    gate, then tighten the floors
#   ./scripts/benchmark_ratchet.sh --runs 5     more runs, still worst-of-N
#   ./scripts/benchmark_ratchet.sh --no-build   reuse the existing release binary
#
# The ratchet only ever moves up. --ratchet rewrites a floor when the measured
# value is better, truncating toward zero so a floor never sits above the
# measurement it was derived from. It never lowers a floor for a worse build.
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

FLOORS_FILE="scripts/ratchet_floors.env"
RUNS=3
DO_RATCHET=0
DO_BUILD=1
DO_LATENCY=0

usage() {
    sed -n '2,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --runs)           RUNS="${2:?--runs needs a number}"; shift 2 ;;
        --ratchet)        DO_RATCHET=1; shift ;;
        --no-build)       DO_BUILD=0; shift ;;
        --with-latency)   DO_LATENCY=1; shift ;;
        --floors)         FLOORS_FILE="${2:?--floors needs a path}"; shift 2 ;;
        -h|--help)        usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
    esac
done

if ! [[ "$RUNS" =~ ^[1-9][0-9]*$ ]]; then
    echo "❌ --runs must be a positive integer, got '$RUNS'" >&2
    exit 2
fi

METRICS=(
    overall
    transform
    restore_raw
    keep_as_typed
    ambiguous_needs_context
    cancel_keep_composed
    vn_survives_collision
    ambiguous_both_sides
    case_signal_restores
)

floor_var_for() {
    local upper
    upper="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
    printf '%s_FLOOR' "$upper"
}

# Truncate toward zero at 2 decimals, so a derived floor is never above its measurement.
truncate2() {
    awk -v x="$1" 'BEGIN { printf "%.2f", int(x * 100) / 100 }'
}

# min of two decimals
min_of() {
    awk -v a="$1" -v b="$2" 'BEGIN { printf "%.4f", (b < a ? b : a) }'
}

# max of two decimals
max_of() {
    awk -v a="$1" -v b="$2" 'BEGIN { printf "%.4f", (b > a ? b : a) }'
}

extract_metric() { # $1 = metric key, $2 = BENCHMARK_JSON payload
    printf '%s' "$2" | sed -n "s/.*\"$1\":\([0-9][0-9.]*\).*/\1/p"
}

if [[ ! -f "$FLOORS_FILE" ]]; then
    echo "❌ Floors file not found: $FLOORS_FILE" >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$FLOORS_FILE"

BIN=".build/release/VieLotusCLI"
if [[ $DO_BUILD -eq 1 ]]; then
    echo "-> Building VieLotusCLI (release)..."
    swift build -c release --product VieLotusCLI 2>&1 | grep -Ev '^\[[0-9 ]+/[0-9 ]+\]$' || true
fi
if [[ ! -x "$BIN" ]]; then
    echo "❌ $BIN not found. Build it first or drop --no-build." >&2
    exit 1
fi

# NOTE: bash 3.2 compatible on purpose — that is what /bin/bash is on every macOS,
# so no associative arrays and no ${var^^}.
WORST=()
echo "-> Running the suite $RUNS time(s) in separate processes; gating on the worst result per metric."
for ((run = 1; run <= RUNS; run++)); do
    # The CLI's own internal floors are disabled here (0) so this script does the gating
    # on worst-of-N; `|| true` keeps a gate-driven exit code from killing the run loop.
    payload="$("$BIN" --benchmark --json --vn-floor 0 --both-floor 0 2>/dev/null \
        | sed -n 's/^BENCHMARK_JSON //p' | tail -1 || true)"
    if [[ -z "$payload" ]]; then
        echo "❌ Run $run produced no BENCHMARK_JSON line." >&2
        exit 1
    fi
    echo "   run $run: $payload"
    for i in "${!METRICS[@]}"; do
        metric="${METRICS[$i]}"
        value="$(extract_metric "$metric" "$payload")"
        if [[ -z "$value" ]]; then
            echo "❌ Run $run: metric '$metric' missing from BENCHMARK_JSON." >&2
            exit 1
        fi
        if [[ -z "${WORST[$i]:-}" ]]; then
            WORST[$i]="$value"
        else
            WORST[$i]="$(min_of "${WORST[$i]}" "$value")"
        fi
    done
done

echo ""
echo "--------------------------------------------------------------------------------"
printf '%-28s %10s %10s   %s\n' "METRIC" "WORST" "FLOOR" "VERDICT"
echo "--------------------------------------------------------------------------------"

FAILED=0
for i in "${!METRICS[@]}"; do
    metric="${METRICS[$i]}"
    var="$(floor_var_for "$metric")"
    floor="${!var-}"
    measured="${WORST[$i]}"
    if [[ -z "$floor" ]]; then
        printf '%-28s %10s %10s   %s\n' "$metric" "$measured" "-" "no floor set"
        continue
    fi
    if awk -v m="$measured" -v f="$floor" 'BEGIN { exit !(m < f) }'; then
        printf '%-28s %10s %10s   %s\n' "$metric" "$measured" "$floor" "❌ REGRESSED"
        FAILED=1
    else
        printf '%-28s %10s %10s   %s\n' "$metric" "$measured" "$floor" "✅"
    fi
done
echo "--------------------------------------------------------------------------------"

if [[ $DO_LATENCY -eq 1 ]]; then
    echo ""
    echo "-> Running high-throughput stress benchmark (250,000 keystrokes) for latency & throughput gating..."
    lat_payload="$("$BIN" --stress --json 2>/dev/null | sed -n 's/^LATENCY_JSON //p' | tail -1 || true)"
    if [[ -z "$lat_payload" ]]; then
        echo "❌ Stress benchmark produced no LATENCY_JSON line." >&2
        exit 1
    fi
    echo "   measured: $lat_payload"

    telex_p99="$(extract_metric "telex_p99" "$lat_payload")"
    vni_p99="$(extract_metric "vni_p99" "$lat_payload")"
    mixed_p99="$(extract_metric "mixed_p99" "$lat_payload")"
    avg_kps="$(extract_metric "avg_kps" "$lat_payload")"

    echo ""
    echo "--------------------------------------------------------------------------------"
    printf '%-30s %10s %10s   %s   %s\n' "LATENCY / PERF METRIC" "MEASURED" "TARGET" "TYPE" "VERDICT"
    echo "--------------------------------------------------------------------------------"

    check_ceiling() {
        local name="$1" val="$2" ceil="$3"
        if [[ -z "$ceil" ]]; then
            printf '%-30s %10s %10s   ceiling   %s\n' "$name" "$val" "-" "no limit"
            return
        fi
        if awk -v m="$val" -v c="$ceil" 'BEGIN { exit !(m > c) }'; then
            printf '%-30s %10s %10s   ceiling   %s\n' "$name" "$val" "$ceil" "❌ REGRESSED"
            FAILED=1
        else
            printf '%-30s %10s %10s   ceiling   %s\n' "$name" "$val" "$ceil" "✅"
        fi
    }

    check_floor() {
        local name="$1" val="$2" fl="$3"
        if [[ -z "$fl" ]]; then
            printf '%-30s %10s %10s   floor     %s\n' "$name" "$val" "-" "no limit"
            return
        fi
        if awk -v m="$val" -v f="$fl" 'BEGIN { exit !(m < f) }'; then
            printf '%-30s %10s %10s   floor     %s\n' "$name" "$val" "$fl" "❌ REGRESSED"
            FAILED=1
        else
            printf '%-30s %10s %10s   floor     %s\n' "$name" "$val" "$fl" "✅"
        fi
    }

    check_ceiling "telex_p99 (µs)" "$telex_p99" "${TELEX_P99_CEILING-}"
    check_ceiling "vni_p99 (µs)" "$vni_p99" "${VNI_P99_CEILING-}"
    check_ceiling "mixed_p99 (µs)" "$mixed_p99" "${MIXED_P99_CEILING-}"
    check_floor "throughput (keys/sec)" "$avg_kps" "${THROUGHPUT_FLOOR_KPS-}"
    echo "--------------------------------------------------------------------------------"
fi

if [[ $FAILED -ne 0 ]]; then
    echo ""
    echo "❌ Ratchet gate FAILED: at least one metric dropped below its floor."
    echo "   Floors never move down. Fix the regression — do not edit $FLOORS_FILE."
    exit 1
fi
echo ""
echo "✅ Ratchet gate passed (worst of $RUNS run(s))."

if [[ $DO_RATCHET -eq 0 ]]; then
    exit 0
fi

echo ""
echo "-> Tightening floors in $FLOORS_FILE (ratchet up only)..."
TIGHTENED=0
tmp="$(mktemp)"
cp "$FLOORS_FILE" "$tmp"
for i in "${!METRICS[@]}"; do
    metric="${METRICS[$i]}"
    var="$(floor_var_for "$metric")"
    current_floor="${!var-}"
    if [[ -z "$current_floor" ]]; then continue; fi
    new_floor="$(truncate2 "${WORST[$i]}")"
    if awk -v n="$new_floor" -v c="$current_floor" 'BEGIN { exit !(n > c) }'; then
        # Escape dots for sed, then rewrite the assignment in place.
        escaped_current="$(printf '%s' "$current_floor" | sed 's/\./\\./g')"
        sed -i '' -E "s/^${var}=${escaped_current}\$/${var}=${new_floor}/" "$tmp"
        echo "   ▲ ${var}: ${current_floor} -> ${new_floor}"
        TIGHTENED=$((TIGHTENED + 1))
    fi
done

if [[ $DO_LATENCY -eq 1 && -n "${THROUGHPUT_FLOOR_KPS-}" ]]; then
    new_kps="$(truncate2 "$avg_kps")"
    if awk -v n="$new_kps" -v c="$THROUGHPUT_FLOOR_KPS" 'BEGIN { exit !(n > c) }'; then
        escaped_current="$(printf '%s' "$THROUGHPUT_FLOOR_KPS" | sed 's/\./\\./g')"
        sed -i '' -E "s/^THROUGHPUT_FLOOR_KPS=${escaped_current}\$/THROUGHPUT_FLOOR_KPS=${new_kps}/" "$tmp"
        echo "   ▲ THROUGHPUT_FLOOR_KPS: ${THROUGHPUT_FLOOR_KPS} -> ${new_kps}"
        TIGHTENED=$((TIGHTENED + 1))
    fi
fi

if [[ $TIGHTENED -eq 0 ]]; then
    echo "   (no floor improved; $FLOORS_FILE unchanged)"
    rm -f "$tmp"
    exit 0
fi

mv "$tmp" "$FLOORS_FILE"
echo "✅ Tightened $TIGHTENED floor(s). Commit $FLOORS_FILE with the change that earned it."
