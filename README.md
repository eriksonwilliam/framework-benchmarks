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

## E a imagem nativa (GraalVM)?

Spring e Quarkus também compilam para **imagem nativa**, o que muda o jogo:
startup em **milissegundos** e memória numa **fração** da JVM. Isso **não foi
medido aqui** porque exige a toolchain do GraalVM (`native-image`), que não
estava disponível na máquina de teste — a compilação nativa é feita na CI de
cada projeto. O mesmo vale para o **.NET Native AOT**. Este comparativo cobre o
modo **JVM/CLR**, que é o mais comum no dia a dia.

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
- Medição de **uma execução** por serviço.

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

## Licença

MIT.
