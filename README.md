# framework-benchmarks

Comparativo **com números reais** dos quatro serviços da minha série que
implementam a **mesma API** (um catálogo de produtos), medindo **startup**,
**memória** e **throughput**:

- [spring-boot-graalvm-native](https://github.com/eriksonwilliam/spring-boot-graalvm-native) — Java · Spring Boot 3
- [quarkus-catalog](https://github.com/eriksonwilliam/quarkus-catalog) — Java · Quarkus
- [ktor-catalog](https://github.com/eriksonwilliam/ktor-catalog) — Kotlin · Ktor
- [dotnet-aspire-catalog](https://github.com/eriksonwilliam/dotnet-aspire-catalog) — C# · .NET 9

> A API, o contrato e o payload são idênticos (100 produtos, 8.385 bytes,
> conferidos a cada rodada). **O armazenamento não é**: os três serviços JVM
> usam `ConcurrentHashMap`, o .NET usa o provider InMemory do EF Core. Parte
> da diferença do .NET pode vir disso, não do runtime.

## Resultados — 26/11/2026 (modo JVM / CLR)

Mediana de **5 rodadas**; entre parênteses, mínimo–máximo. Dado bruto em
[`results/2026-11-26/raw.csv`](results/2026-11-26/raw.csv), resumo em
[`summary.md`](results/2026-11-26/summary.md) e ambiente em
[`environment.txt`](results/2026-11-26/environment.txt). Zero erros e zero
respostas não-2xx em todas as 40 medições.

### Startup e memória

| Framework | Startup (ms) | RSS ocioso (MB) | RSS após carga (MB) |
| --- | ---: | ---: | ---: |
| .NET 9 | 888 (869–1072) | 72 (72–72) | 101 (96–115) |
| Ktor | 1357 (1316–1456) | 119 (119–136) | 276 (273–278) |
| Quarkus | 1776 (1561–1899) | 118 (117–132) | 194.5 (155–265) |
| Spring Boot 3 | 4444 (4245–5475) | 165 (163–187) | 205.5 (200–211) |

### GET /products com 100 produtos, 50 conexões por 15 s

| Framework | req/s | p50 (ms) | p95 (ms) | p99 (ms) |
| --- | ---: | ---: | ---: | ---: |
| Quarkus | 3998.6 (3475.1–4081.4) | 10.55 | 29.69 | 43.44 |
| Spring Boot 3 | 3621.9 (3176.8–3672) | 11.6 | 31.15 | 44.3 |
| Ktor | 3481.3 (3189.6–3755.2) | 11.69 | 31.89 | 46.26 |
| .NET 9 | 3316.6 (3274–3453.6) | 13.1 | 28.99 | **39.66** |

Com 10 conexões a ordem de vazão é a mesma (Quarkus 3800, Ktor 3279, Spring
3277, .NET 2652 req/s); ver `summary.md`.

### Leitura

- **.NET** sobe mais rápido e ocupa menos memória, antes e depois da carga.
  Tem a menor vazão, mas o **melhor p99** e a menor variação entre rodadas
  a 50 conexões.
- **Quarkus** lidera a vazão nas duas concorrências.
- **Ktor** é o segundo mais rápido para subir, mas termina a carga com o
  maior RSS (276 MB).
- **Spring Boot** continua o mais lento para subir (~4,4 s), com vazão no
  meio do grupo.
- As diferenças de vazão ficam entre 10% e 20%; a variação entre rodadas do
  mesmo serviço chega a ~15%. Não dá para declarar um vencedor universal.

## O que mudou em relação à medição de julho/2026

A medição anterior (tabelas abaixo, em "Histórico") tinha três problemas:

1. **Uma rodada por serviço** e 3 s de aquecimento junto da medição.
2. **Loja vazia**: nenhum serviço popula dados na subida, então
   `GET /products` serializava `[]`. Media a pilha HTTP, não um endpoint.
3. O script encerrava **qualquer processo** escutando na porta 8080.

Agora: 5 rodadas com a ordem dos serviços rotacionada, 20 s de aquecimento
separado, 100 produtos populados pela própria API, duas concorrências, CSV
bruto, porta própria (18080) e encerramento só do processo lançado.

Na loja populada, o Spring subiu mais rápido (6822 → 4444 ms) e o .NET deixou
de ficar tão atrás em vazão (2731 → 3317 req/s a 50 conexões).

## Histórico (julho/2026, uma rodada, loja vazia)

Mantido para comparação; **não use como resultado**.

| Framework     | Startup (ms) | Memória (MB) | Throughput (req/s) | p99 (ms) |
| ------------- | -----------: | -----------: | -----------------: | -------: |
| .NET 9        |         1193 |           72 |               2731 |    52.72 |
| Ktor          |         1906 |          136 |               3168 |    53.46 |
| Quarkus       |         2382 |          114 |               3748 |    47.33 |
| Spring Boot 3 |         6822 |          185 |               3203 |    57.99 |

## Nativo (GraalVM) — histórico, julho/2026

> Medição de julho/2026, com a metodologia antiga (uma rodada, loja vazia).
> Não foi reproduzida em 26/11/2026.

Spring e Quarkus também compilam para **imagem nativa** (AOT) com o GraalVM
`native-image` (Oracle GraalVM 21). Compilei os dois binários e medi com a mesma
metodologia. O resultado muda o jogo em **startup** e **memória**:

### Startup — JVM vs. Nativo (menor é melhor)

```
quarkus-native  ███ 469 ms
spring-native   ███ 490 ms
quarkus (JVM)   ████████████████ 2382 ms
spring  (JVM)   ████████████████████████████████████████████ 6822 ms
```

### Memória ociosa — JVM vs. Nativo (menor é melhor)

```
quarkus-native  ███████ 33 MB
spring-native   █████████████████ 78 MB
quarkus (JVM)   █████████████████████████ 114 MB
spring  (JVM)   ████████████████████████████████████████ 185 MB
```

### Tabela — o que a compilação nativa muda

| Serviço          |    Startup |  Memória |   Throughput |
| ---------------- | ---------: | -------: | -----------: |
| spring **(JVM)** |    6822 ms |   185 MB |   3203 req/s |
| spring-native    | **490 ms** | **78 MB**|   2778 req/s |
| quarkus **(JVM)**|    2382 ms |   114 MB |   3748 req/s |
| quarkus-native   | **469 ms** | **33 MB**|   3182 req/s |

**Leitura rápida:** o nativo **derruba o startup** (Spring: ~14× mais rápido;
Quarkus: ~5×) e corta a memória para uma **fração** (Spring 2,4× mais leve;
Quarkus 3,5×) — exatamente o que faz sentido para **serverless / escala a zero /
cold start**. Em troca, o **throughput sustentado cai um pouco** (~10–15%): a JVM
tem *JIT* que aquece sob carga e otimiza o código quente, coisa que o AOT não
faz. Ou seja: nativo ganha em **subir rápido e ocupar pouco**; a JVM quente ainda
lidera em **vazão de pico**. Escolha pelo que pesa no seu caso.

> **Como foi medido:** binários gerados com `mvn -Pnative` (Spring) e
> `mvn package -Dnative` (Quarkus). O startup nativo é o **melhor de 3 execuções
> aquecidas** — a *primeira* execução de um `.exe` novo no Windows é penalizada
> pelo antivírus varrendo o binário (chegava a ~3 s), o que não reflete o startup
> real do processo. O mesmo racional de AOT vale para o **.NET Native AOT**, não
> medido aqui.

## Metodologia

[`bench.sh`](bench.sh), para cada rodada e cada serviço (ordem rotacionada):

1. **Startup**: tempo entre lançar o processo e a primeira resposta `200` em
   `GET /products` (inclui o boot da JVM/CLR).
2. **RSS ocioso**: working set do processo logo após subir.
3. **Dados**: 100 produtos criados por `POST /products`; o tamanho da
   resposta é registrado para conferir que os quatro devolvem o mesmo payload.
4. **Aquecimento**: 20 s de carga com 50 conexões, fora da medição.
5. **Medição**: [`bombardier`](https://github.com/codesenberg/bombardier) por
   15 s em cada concorrência (10 e 50), com latência p50/p95/p99, contagem de
   não-2xx e de erros, e RSS depois da carga.

[`summarize.py`](summarize.py) (só biblioteca padrão) calcula mediana, mínimo
e máximo entre rodadas.

## Ressalvas

- Notebook (i7-1165G7, 8 threads, Windows 11), com cliente de carga e
  serviço na mesma máquina. Ordem de grandeza, não laboratório.
- Armazenamento diferente no .NET (EF Core InMemory), como dito acima.
- Uma única rota de leitura; escrita e regras de negócio não foram medidas.
- Nativo não foi reproduzido nesta rodada.

## Como reproduzir

```bash
# os 4 repositórios como pastas irmãs, cada um buildado:
#   spring-boot-graalvm-native, quarkus-catalog, ktor-catalog -> mvn package -DskipTests
#   dotnet-aspire-catalog -> dotnet publish src/Catalog.Api -c Release -o publish
go install github.com/codesenberg/bombardier@v1.2.6

BASE=.. ROUNDS=5 bash bench.sh            # PYTHON=python onde python3 não existir
python3 summarize.py results/$(date +%Y-%m-%d)
```

Variáveis: `ROUNDS`, `WARMUP_SECONDS`, `DURATION_SECONDS`, `CONCURRENCY`,
`SEED_PRODUCTS`, `BENCH_PORT` (padrão 18080), `OUT_DIR`. O script recusa
começar se a porta já estiver em uso.

## Licença

MIT.
