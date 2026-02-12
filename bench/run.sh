#!/bin/bash

# ─── Config ──────────────────────────────────────────
REQUESTS=5000
CONCURRENCY=50
WARMUP_REQUESTS=100
RUNS=2
RESULTS_FILE="result.csv"
ZON_FILE="../site/pages/bench.zon"

# ─── Colors ──────────────────────────────────────────
BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[32m'
RED='\033[31m'
NC='\033[0m'

ALL_FRAMEWORKS="ziex leptos solidjs nextjs"

# ─── Helpers ─────────────────────────────────────────
get_port() {
    case "$1" in
        ziex)    echo 3003 ;;
        leptos)  echo 3002 ;;
        solidjs) echo 3001 ;;
        nextjs)  echo 3000 ;;
    esac
}

get_label() {
    case "$1" in
        ziex)    echo "Ziex" ;;
        leptos)  echo "Leptos" ;;
        solidjs) echo "SolidStart" ;;
        nextjs)  echo "Next.js" ;;
        *)       echo "$1" ;;
    esac
}

get_memory_mb() {
    docker stats --no-stream --format "{{.MemUsage}}" "$1" 2>/dev/null | \
        awk '{gsub(/[A-Za-z]/, "", $1); print $1}'
}

die() { echo -e "${RED}error:${NC} $1" >&2; exit 1; }

# ─── Parse args ──────────────────────────────────────
FRAMEWORKS=""
if [ $# -gt 0 ]; then
    for arg in "$@"; do
        port=$(get_port "$arg" 2>/dev/null)
        [ -n "$port" ] || die "unknown framework '$arg' (available: $ALL_FRAMEWORKS)"
        FRAMEWORKS="$FRAMEWORKS $arg"
    done
    FRAMEWORKS=$(echo "$FRAMEWORKS" | xargs)
else
    FRAMEWORKS="$ALL_FRAMEWORKS"
fi

command -v oha &>/dev/null || die "oha not installed (cargo install oha)"

echo -e "\n${BOLD}ZX Benchmark Suite${NC}"
echo -e "${DIM}───────────────────────────────────────${NC}\n"

# ─── Build ───────────────────────────────────────────
echo -ne "Building images..."
docker-compose build --parallel $FRAMEWORKS &>/dev/null
echo -e " ${GREEN}✓${NC}\n"

# ─── Prepare CSV ─────────────────────────────────────
running_all=false
[ "$FRAMEWORKS" = "$ALL_FRAMEWORKS" ] && running_all=true

if [ "$running_all" = true ] || [ ! -f "$RESULTS_FILE" ]; then
    echo "framework,idle_mb,peak_mb,rps,p50_ms,p99_ms" > "$RESULTS_FILE"
else
    # Preserve results for frameworks not being re-benchmarked
    tmpfile=$(mktemp)
    head -1 "$RESULTS_FILE" > "$tmpfile"
    tail -n +2 "$RESULTS_FILE" | while IFS=',' read -r fw rest; do
        skip=false
        for target in $FRAMEWORKS; do
            [ "$fw" = "$target" ] && { skip=true; break; }
        done
        $skip || echo "$fw,$rest" >> "$tmpfile"
    done
    mv "$tmpfile" "$RESULTS_FILE"
fi

# ─── Benchmark ───────────────────────────────────────
benchmark() {
    local name=$1
    local port=$(get_port "$name")
    local label=$(get_label "$name")
    local url="http://localhost:$port/ssr"

    echo -e "${BOLD}▸ $label${NC} ${DIM}($name:$port)${NC}"

    # Start container
    echo -ne "  Starting..."
    if ! docker-compose up -d --wait "$name" &>/dev/null; then
        echo -e " ${RED}✗${NC}"
        docker-compose logs "$name" 2>/dev/null | tail -3 | sed 's/^/    /'
        docker-compose stop "$name" &>/dev/null
        return 1
    fi

    local container
    container=$(docker-compose ps -q "$name")
    [ -n "$container" ] || { echo -e " ${RED}✗${NC} no container"; return 1; }

    sleep 2
    local idle_mem
    idle_mem=$(get_memory_mb "$container")
    echo -e " ${GREEN}✓${NC}  idle: ${idle_mem} MB"

    # Warmup (silent)
    oha -n $WARMUP_REQUESTS "$url" --no-tui &>/dev/null
    sleep 1

    # Benchmark runs
    echo -ne "  Benchmarking ×${RUNS}..."

    local total_rps=0 total_p50=0 total_p99=0 total_peak=0

    for run in $(seq 1 $RUNS); do
        local max_mem=$idle_mem
        (
            while docker ps -q --filter id="$container" &>/dev/null; do
                mem=$(get_memory_mb "$container" 2>/dev/null || echo "0")
                if [ -n "$mem" ] && (( $(echo "$mem > $max_mem" | bc -l 2>/dev/null || echo 0) )); then
                    max_mem=$mem
                    echo "$max_mem" > "/tmp/${name}_peak_${run}.txt"
                fi
                sleep 0.3
            done
        ) &
        local monitor_pid=$!

        oha -n $REQUESTS -c $CONCURRENCY "$url" --no-tui > "/tmp/${name}_oha_${run}.txt" 2>&1

        kill $monitor_pid 2>/dev/null
        wait $monitor_pid 2>/dev/null

        local peak_mem=$idle_mem
        if [ -f "/tmp/${name}_peak_${run}.txt" ]; then
            peak_mem=$(cat "/tmp/${name}_peak_${run}.txt")
            rm "/tmp/${name}_peak_${run}.txt"
        fi

        local rps p50 p99
        rps=$(grep "Requests/sec" "/tmp/${name}_oha_${run}.txt" | awk '{print $2}')
        p50=$(grep "50.00%" "/tmp/${name}_oha_${run}.txt" | awk '{print $3}')
        p99=$(grep "99.00%" "/tmp/${name}_oha_${run}.txt" | awk '{print $3}')

        rps=${rps:-0}; p50=${p50:-0}; p99=${p99:-0}

        total_rps=$(echo "$total_rps + $rps" | bc)
        total_p50=$(echo "$total_p50 + $p50" | bc)
        total_p99=$(echo "$total_p99 + $p99" | bc)
        total_peak=$(echo "$total_peak + $peak_mem" | bc)

        sleep 0.5
    done

    local avg_rps avg_p50 avg_p99 avg_peak
    avg_rps=$(printf "%.2f" "$(echo "scale=4; $total_rps / $RUNS" | bc)")
    avg_p50=$(printf "%.2f" "$(echo "scale=4; $total_p50 / $RUNS" | bc)")
    avg_p99=$(printf "%.2f" "$(echo "scale=4; $total_p99 / $RUNS" | bc)")
    avg_peak=$(printf "%.2f" "$(echo "scale=4; $total_peak / $RUNS" | bc)")

    echo -e " ${GREEN}✓${NC}"
    printf "  ${GREEN}→${NC} ${BOLD}%.0f req/s${NC} · p50: %sms · p99: %sms · peak: %s MB\n" \
        "$avg_rps" "$avg_p50" "$avg_p99" "$avg_peak"
    echo ""

    echo "$name,$idle_mem,$avg_peak,$avg_rps,$avg_p50,$avg_p99" >> "$RESULTS_FILE"
    docker-compose stop "$name" &>/dev/null
}

for fw in $FRAMEWORKS; do
    benchmark "$fw"
done

# ─── Generate bench.zon ─────────────────────────────
generate_zon() {
    cat > "$ZON_FILE" << 'HEADER'
// Auto-generated by bench/run.sh — do not edit
.{
HEADER

    tail -n +2 "$RESULTS_FILE" | while IFS=',' read -r fw idle peak rps p50 p99; do
        local label
        label=$(get_label "$fw")
        cat >> "$ZON_FILE" << EOF
    .{
        .id = "$fw",
        .label = "$label",
        .idle_memory_mb = $(printf "%.1f" "$idle"),
        .peak_memory_mb = $(printf "%.1f" "$peak"),
        .requests_per_sec = $(printf "%.0f" "$rps"),
        .p50_latency_ms = $(printf "%.2f" "$p50"),
        .p99_latency_ms = $(printf "%.2f" "$p99"),
    },
EOF
    done

    echo "}" >> "$ZON_FILE"
}

generate_zon
docker-compose down &>/dev/null

# ─── Summary ─────────────────────────────────────────
echo -e "${DIM}───────────────────────────────────────${NC}"
printf "  ${BOLD}%-12s %9s %10s %10s %9s %9s${NC}\n" "Framework" "Req/s" "P50" "P99" "Idle" "Peak"

tail -n +2 "$RESULTS_FILE" | while IFS=',' read -r fw idle peak rps p50 p99; do
    label=$(get_label "$fw")
    printf "  %-12s %9.0f %8.2f ms %8.2f ms %6s MB %6s MB\n" \
        "$label" "$rps" "$p50" "$p99" "$idle" "$peak"
done

echo -e "${DIM}───────────────────────────────────────${NC}"
echo -e "  ${DIM}Saved: ${RESULTS_FILE} · ${ZON_FILE}${NC}"
echo -e "  ${DIM}${REQUESTS} req × ${CONCURRENCY} conn × ${RUNS} runs${NC}"
echo ""
