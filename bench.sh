#!/usr/bin/env bash
#
# Mede startup, memoria ociosa e throughput dos 4 servicos da serie (modo
# JVM/CLR). Requer os 4 repositorios como pastas irmas e ja buildados, alem do
# bombardier (https://github.com/codesenberg/bombardier) no PATH.
#
# Uso:  BASE=/caminho/para/os/repos  bash bench.sh
#
set -u

BASE="${BASE:-..}"
URL="http://localhost:8080/products"
export PORT=8080
export ASPNETCORE_URLS="http://localhost:8080"

# RSS (MB) do processo que escuta na porta 8080 — Windows (PowerShell) ou Unix.
mem_mb() {
  if command -v powershell >/dev/null 2>&1; then
    powershell -NoProfile -Command \
      "\$p=(Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty OwningProcess); if(\$p){[math]::Round((Get-Process -Id \$p).WorkingSet64/1MB)} else {0}" 2>/dev/null | tr -d '\r'
  else
    local pid
    pid=$(lsof -ti:8080 2>/dev/null | head -1)
    if [ -n "$pid" ]; then echo $(( $(ps -o rss= -p "$pid") / 1024 )); else echo 0; fi
  fi
}

# Encerra qualquer processo escutando na porta 8080.
kill_port() {
  if command -v powershell >/dev/null 2>&1; then
    powershell -NoProfile -Command \
      "Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id \$_.OwningProcess -Force -ErrorAction SilentlyContinue }" 2>/dev/null
  else
    local pid
    pid=$(lsof -ti:8080 2>/dev/null | head -1)
    [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null
  fi
}

bench() {
  local label="$1"
  shift
  local t0 t1 code ready_ms mem out rps p99
  t0=$(date +%s%3N)
  "$@" >/tmp/bench-svc.log 2>&1 &
  local pid=$!
  ready_ms=0
  for _ in $(seq 1 600); do
    code=$(curl -s -o /dev/null -w "%{http_code}" "$URL" 2>/dev/null)
    if [ "$code" = "200" ]; then
      t1=$(date +%s%3N)
      ready_ms=$((t1 - t0))
      break
    fi
    sleep 0.05
  done
  sleep 1
  mem=$(mem_mb)
  bombardier -c 20 -d 3s "$URL" >/dev/null 2>&1
  out=$(bombardier -c 50 -d 8s -l "$URL" 2>&1)
  rps=$(echo "$out" | grep -iE "Reqs/sec" | awk '{print $2}')
  p99=$(echo "$out" | grep -E "^[[:space:]]*99" | head -1 | awk '{print $2}')
  printf "%-10s | startup: %6s ms | mem: %5s MB | rps: %10s | p99: %8s\n" \
    "$label" "$ready_ms" "$mem" "$rps" "$p99"
  kill "$pid" 2>/dev/null
  kill_port
  sleep 3
}

echo "=== Benchmark (JVM/CLR) — $(date) ==="
bench "spring"  java -jar "$BASE/spring-boot-graalvm-native/target/catalog-service-0.1.0.jar"
bench "quarkus" java -jar "$BASE/quarkus-catalog/target/quarkus-app/quarkus-run.jar"
bench "ktor"    java -jar "$BASE/ktor-catalog/target/ktor-catalog-0.1.0.jar"
bench "dotnet"  dotnet "$BASE/dotnet-aspire-catalog/publish/Catalog.Api.dll"
echo "=== fim ==="
