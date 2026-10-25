#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
client_output="$(mktemp)"
trap 'rm -f "$client_output"' EXIT
set_scenario() {
    curl --fail --silent --show-error --max-time 3 http://127.0.0.1:4917/api/__scenario \
        -H 'Content-Type: application/json' --data "{\"scenario\":\"$1\"}" > /dev/null
}
set_scenario success
.build/release/OllamaDiagnostics 4917 2 > "$client_output"
test "$(rg -c 'Synthetic translated sentence' "$client_output")" -eq 2
printf '%s\n' 'PASS: valid requests and both language directions'
for scenario in error html truncated empty missing timeout redirect; do
    set_scenario "$scenario"
    if .build/release/OllamaDiagnostics 4917 0.2 > "$client_output" 2>&1; then
        printf 'FAIL: %s unexpectedly succeeded\n' "$scenario" >&2
        exit 1
    fi
    case "$scenario" in
        error|html) expected='HTTP 500' ;;
        truncated) expected='не завершила перевод' ;;
        empty) expected='пустой перевод' ;;
        missing) expected='нет translategemma:4b' ;;
        timeout) expected='недоступна или не успела' ;;
        redirect) expected='HTTP 302' ;;
    esac
    rg -q "$expected" "$client_output"
    printf 'PASS: %s\n' "$scenario"
done
set_scenario success
