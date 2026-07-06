# framework-benchmarks

Comparativo **com números reais** dos quatro serviços da minha série que
implementam a **mesma API** (um catálogo de produtos), medindo **startup**,
**memória** e **throughput**:

- [spring-boot-graalvm-native](https://github.com/eriksonwilliam/spring-boot-graalvm-native) — Java · Spring Boot 3
- [quarkus-catalog](https://github.com/eriksonwilliam/quarkus-catalog) — Java · Quarkus
- [ktor-catalog](https://github.com/eriksonwilliam/ktor-catalog) — Kotlin · Ktor
- [dotnet-aspire-catalog](https://github.com/eriksonwilliam/dotnet-aspire-catalog) — C# · .NET 9

> Como a API e a arquitetura são idênticas, a diferença medida é essencialmente
> do **framework/runtime** — não da implementação.

## Resultados (modo JVM / CLR)

### Startup — do lançamento até a primeira resposta HTTP 200 (menor é melhor)

```
dotnet   ███████ 1193 ms
ktor     ███████████ 1906 ms
quarkus  ██████████████ 2382 ms
spring   ████████████████████████████████████████ 6822 ms
```

### Memória ociosa — RSS após subir, antes de carga (menor é melhor)

```
dotnet   ████████████████ 72 MB
quarkus  █████████████████████████ 114 MB
ktor     █████████████████████████████ 136 MB
spring   ████████████████████████████████████████ 185 MB
```

### Throughput — GET /products, 50 conexões por 8s (maior é melhor)

```
quarkus  ████████████████████████████████████████ 3748 req/s
spring   ██████████████████████████████████ 3203 req/s
ktor     ██████████████████████████████████ 3168 req/s
dotnet   █████████████████████████████ 2731 req/s
```

### Tabela

| Framework     | Startup (ms) | Memória (MB) | Throughput (req/s) | p99 (ms) |
| ------------- | -----------: | -----------: | -----------------: | -------: |
| .NET 9        |         1193 |           72 |               2731 |    52.72 |
| Ktor          |         1906 |          136 |               3168 |    53.46 |
| Quarkus       |         2382 |          114 |               3748 |    47.33 |
| Spring Boot 3 |         6822 |          185 |               3203 |    57.99 |

**Leitura rápida:** .NET arranca mais rápido e mais leve; Quarkus lidera o
throughput; Spring na JVM é o mais pesado para subir (era esperado — é o
framework mais "cheio"). Nenhum é "o melhor": depende do que pesa no seu caso.

## Nativo (GraalVM) — números reais

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

Para cada serviço, o script [`bench.sh`](bench.sh):

1. **Startup:** marca o tempo entre lançar o processo e a primeira resposta
   `200` em `GET /products` (inclui o boot da JVM/CLR).
2. **Memória:** lê o RSS (working set) do processo que está escutando na porta,
   em repouso, logo após subir.
3. **Throughput:** um *warm-up* de 3s e então
   [`bombardier`](https://github.com/codesenberg/bombardier) com 50 conexões por
   8s em `GET /products`; registra req/s médio e a latência p99.

## Ambiente da medição

- Máquina de desenvolvimento (Windows 11, 8 vCPU).
- JDK: Temurin 21. .NET SDK: 9.0. Serviços em modo release/produção.
- Imagens nativas: **Oracle GraalVM 21** (`native-image` 21.0.11).
- JVM/CLR: medição de **uma execução** por serviço. Nativo: melhor de 3
  (descartando a penalidade de antivírus na 1ª execução).

## ⚠️ Ressalvas (leia antes de tirar conclusões)

- São números **indicativos de uma única rodada** numa máquina de dev — não um
  laboratório controlado. Use como ordem de grandeza, não como verdade absoluta.
- A JVM tem *warm-up* (JIT): o throughput tende a subir depois de mais tempo sob
  carga. O *warm-up* aqui é curto.
- Startup e memória variam com disco, cache e o que mais está rodando na máquina.
- Reproduza no **seu** ambiente antes de decidir qualquer coisa.

## Como reproduzir

```bash
# tenha os 4 repositórios como pastas irmãs e cada um buildado:
#   spring-boot-graalvm-native  -> mvn package -DskipTests
#   quarkus-catalog             -> mvn package -DskipTests
#   ktor-catalog                -> mvn package -DskipTests
#   dotnet-aspire-catalog       -> dotnet publish -c Release -o publish

# instale o bombardier (load tool):
go install github.com/codesenberg/bombardier@latest

BASE=/caminho/para/os/repos bash bench.sh
```

Para os binários **nativos** (precisa do GraalVM `native-image` no `JAVA_HOME`):

```bash
# Spring  -> target/catalog-service.exe
cd spring-boot-graalvm-native && mvn -B -Pnative -DskipTests package native:compile
# Quarkus -> target/quarkus-catalog-0.1.0-runner.exe
cd quarkus-catalog && mvn -B package -Dnative -DskipTests
```

## Licença

MIT.
