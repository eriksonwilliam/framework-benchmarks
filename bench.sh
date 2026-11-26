#!/usr/bin/env bash
#
# Mede startup, memoria e throughput/latencia dos 4 servicos da serie (modo
# JVM/CLR), com rodadas repetidas e resultado bruto em CSV.
#
# Requer os 4 repositorios como pastas irmas e ja buildados, alem do
# bombardier (https://github.com/codesenberg/bombardier) no PATH.
#
# Uso:
#   BASE=/caminho/para/os/repos bash bench.sh
#   ROUNDS=5 WARMUP_SECONDS=20 DURATION_SECONDS=15 CONCURRENCY="10 50" bash bench.sh
#
# Saida: results/<data>/raw.csv (uma linha por servico x rodada x concorrencia)
# e results/<data>/environment.txt. Resuma com: python3 summarize.py results/<data>
# (onde python3 nao existir, use PYTHON=python bash bench.sh e python summarize.py)
set -u

BASE="${BASE:-..}"
PYTHON="${PYTHON:-python3}"
ROUNDS="${ROUNDS:-5}"
WARMUP_SECONDS="${WARMUP_SECONDS:-20}"
DURATION_SECONDS="${DURATION_SECONDS:-15}"
CONCURRENCY="${CONCURRENCY:-10 50}"
# A loja comeca vazia nos 4 servicos. Sem popular, GET /products mede so a
# serializacao de "[]" — a pilha HTTP, nao um endpoint de leitura.
SEED_PRODUCTS="${SEED_PRODUCTS:-100}"
OUT_DIR="${OUT_DIR:-results/$(date +%Y-%m-%d)}"

# Porta propria, longe da 8080: a versao anterior encerrava "qualquer processo
# escutando na 8080", o que derruba o que mais estiver nessa porta na maquina.
BENCH_PORT="${BENCH_PORT:-18080}"
URL="http://localhost:$BENCH_PORT/products"
export PORT="$BENCH_PORT"
export ASPNETCORE_URLS="http://localhost:$BENCH_PORT"

mkdir -p "$OUT_DIR"
RAW="$OUT_DIR/raw.csv"
[ -f "$RAW" ] || echo "framework,round,concurrency,startup_ms,rss_idle_mb,rss_after_load_mb,products,response_bytes,requests,rps_mean,latency_p50_ms,latency_p95_ms,latency_p99_ms,latency_max_ms,non_2xx,errors" >"$RAW"

# RSS (MB) do processo que escuta na porta do benchmark — Windows (PowerShell) ou Unix.
mem_mb() {
  if command -v powershell >/dev/null 2>&1; then
    powershell -NoProfile -Command \
      "\$p=(Get-NetTCPConnection -LocalPort $BENCH_PORT -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty OwningProcess); if(\$p){[math]::Round((Get-Process -Id \$p).WorkingSet64/1MB)} else {0}" 2>/dev/null | tr -d '\r'
  else
    local pid
    pid=$(lsof -ti:"$BENCH_PORT" 2>/dev/null | head -1)
    if [ -n "$pid" ]; then echo $(( $(ps -o rss= -p "$pid") / 1024 )); else echo 0; fi
  fi
}

port_busy() {
  curl -s -o /dev/null --max-time 1 "http://localhost:$BENCH_PORT/" 2>/dev/null
}

# Encerra apenas o processo lancado pelo script e espera a porta liberar.
stop_service() {
  local pid="$1"
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  for _ in $(seq 1 100); do
    port_busy || return 0
    sleep 0.1
  done
  echo "a porta $BENCH_PORT continua ocupada depois de encerrar o servico" >&2
  exit 1
}

# Extrai um campo do JSON do bombardier sem depender de jq.
json_field() {
  "$PYTHON" -c "import json,sys; d=json.load(sys.stdin)['result']; print(eval(sys.argv[1]))" "$1"
}

# exec: o PID em background passa a ser o do servico, nao o de um subshell;
# e ele que stop_service encerra.
launch() {
  case "$1" in
    spring) exec java -jar "$BASE/spring-boot-graalvm-native/target/catalog-service-0.1.0.jar" ;;
    quarkus) exec java -jar "$BASE/quarkus-catalog/target/quarkus-app/quarkus-run.jar" ;;
    ktor) exec java -jar "$BASE/ktor-catalog/target/ktor-catalog-0.1.0.jar" ;;
    dotnet) exec dotnet "$BASE/dotnet-aspire-catalog/publish/Catalog.Api.dll" ;;
  esac
}

bench() {
  local framework="$1" round="$2"
  local t0 t1 code startup_ms rss_idle body products bytes
  t0=$(date +%s%3N)
  launch "$framework" >"$OUT_DIR/$framework-$round.log" 2>&1 &
  local pid=$!
  startup_ms=""
  for _ in $(seq 1 1200); do
    code=$(curl -s -o /dev/null -w "%{http_code}" "$URL" 2>/dev/null)
    if [ "$code" = "200" ]; then
      t1=$(date +%s%3N)
      startup_ms=$((t1 - t0))
      break
    fi
    sleep 0.05
  done
  if [ -z "$startup_ms" ]; then
    echo "$framework rodada $round: nao respondeu em 60s, pulando" >&2
    stop_service "$pid"
    return
  fi
  sleep 1
  rss_idle=$(mem_mb)

  for i in $(seq 1 "$SEED_PRODUCTS"); do
    curl -s -o /dev/null -X POST "$URL" -H "Content-Type: application/json" \
      -d "{\"name\":\"Produto $i\",\"priceCents\":$((i * 100))}"
  done
  body=$(curl -s "$URL")
  bytes=${#body}
  products=$(printf '%s' "$body" | "$PYTHON" -c "import json,sys; print(len(json.load(sys.stdin)))")

  # Aquecimento separado da medicao: o JIT da JVM so otimiza o codigo quente
  # depois de executa-lo; medir junto com o aquecimento penaliza a JVM.
  bombardier -c 50 -d "${WARMUP_SECONDS}s" "$URL" >/dev/null 2>&1

  for c in $CONCURRENCY; do
    local json
    json=$(bombardier -c "$c" -d "${DURATION_SECONDS}s" -l -p r -o json "$URL" 2>/dev/null)
    local requests rps p50 p95 p99 max non2xx errors rss_after
    requests=$(echo "$json" | json_field "d['req1xx']+d['req2xx']+d['req3xx']+d['req4xx']+d['req5xx']+d['others']")
    rps=$(echo "$json" | json_field "round(d['rps']['mean'],1)")
    p50=$(echo "$json" | json_field "round(d['latency']['percentiles']['50']/1000,2)")
    p95=$(echo "$json" | json_field "round(d['latency']['percentiles']['95']/1000,2)")
    p99=$(echo "$json" | json_field "round(d['latency']['percentiles']['99']/1000,2)")
    max=$(echo "$json" | json_field "round(d['latency']['max']/1000,2)")
    non2xx=$(echo "$json" | json_field "d['req1xx']+d['req3xx']+d['req4xx']+d['req5xx']")
    errors=$(echo "$json" | json_field "d['others']")
    rss_after=$(mem_mb)
    echo "$framework,$round,$c,$startup_ms,$rss_idle,$rss_after,$products,$bytes,$requests,$rps,$p50,$p95,$p99,$max,$non2xx,$errors" | tee -a "$RAW"
  done

  stop_service "$pid"
  sleep 3
}

{
  echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "os: $(uname -a)"
  if command -v powershell >/dev/null 2>&1; then
    echo "cpu: $(powershell -NoProfile -Command '(Get-CimInstance Win32_Processor).Name' | tr -d '\r')"
    echo "logical_cpus: $(powershell -NoProfile -Command '(Get-CimInstance Win32_Processor).NumberOfLogicalProcessors' | tr -d '\r')"
    echo "memory_gb: $(powershell -NoProfile -Command '[math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB,1)' | tr -d '\r')"
  fi
  echo "java: $(java -version 2>&1 | head -1)"
  echo "dotnet: $(dotnet --version 2>/dev/null)"
  echo "bombardier: $(bombardier --version 2>&1 | head -1)"
  echo "rounds=$ROUNDS warmup_s=$WARMUP_SECONDS duration_s=$DURATION_SECONDS concurrency=\"$CONCURRENCY\" seed_products=$SEED_PRODUCTS"
  for repo in spring-boot-graalvm-native quarkus-catalog ktor-catalog dotnet-aspire-catalog; do
    echo "commit $repo: $(git -C "$BASE/$repo" rev-parse --short HEAD 2>/dev/null)"
  done
} >"$OUT_DIR/environment.txt"

if port_busy; then
  echo "a porta $BENCH_PORT ja esta em uso; escolha outra com BENCH_PORT=..." >&2
  exit 1
fi

FRAMEWORKS=(spring quarkus ktor dotnet)
for round in $(seq 1 "$ROUNDS"); do
  # Ordem rotacionada a cada rodada: quem roda primeiro pega a maquina mais
  # "fria" (cache, termica); rotacionar impede que um servico leve sempre isso.
  offset=$(( (round - 1) % ${#FRAMEWORKS[@]} ))
  for i in $(seq 0 $(( ${#FRAMEWORKS[@]} - 1 ))); do
    bench "${FRAMEWORKS[$(( (i + offset) % ${#FRAMEWORKS[@]} ))]}" "$round"
  done
done
echo "resultado bruto: $RAW"
