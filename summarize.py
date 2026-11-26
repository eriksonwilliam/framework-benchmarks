"""Resume results/<data>/raw.csv em results/<data>/summary.md.

Mediana entre rodadas, com minimo e maximo ao lado: com 5 rodadas a media e
puxada por uma rodada ruim, e o intervalo mostra quanto o numero oscilou.
So biblioteca padrao.
"""

import csv
import statistics
import sys
from collections import defaultdict
from pathlib import Path

LABELS = {"spring": "Spring Boot 3", "quarkus": "Quarkus", "ktor": "Ktor", "dotnet": ".NET 9"}


def spread(values):
    values = sorted(values)
    median = statistics.median(values)
    return f"{median:g} ({values[0]:g}–{values[-1]:g})"


def main(directory: Path) -> None:
    rows = list(csv.DictReader((directory / "raw.csv").open(encoding="utf-8")))
    if not rows:
        sys.exit("raw.csv vazio")

    per_round = {}
    by_load = defaultdict(list)
    for row in rows:
        per_round[(row["framework"], row["round"])] = row
        by_load[(row["framework"], int(row["concurrency"]))].append(row)

    frameworks = [f for f in LABELS if any(k[0] == f for k in per_round)]
    rounds = len({r["round"] for r in rows})
    lines = [
        f"# Resumo ({directory.name})",
        "",
        f"Mediana de {rounds} rodadas; entre parênteses, mínimo–máximo.",
        "",
        "## Startup e memória",
        "",
        "| Framework | Startup (ms) | RSS ocioso (MB) | RSS após carga (MB) |",
        "| --- | ---: | ---: | ---: |",
    ]
    for framework in frameworks:
        startups = [float(r["startup_ms"]) for (f, _), r in per_round.items() if f == framework]
        idle = [float(r["rss_idle_mb"]) for (f, _), r in per_round.items() if f == framework]
        after = [
            float(r["rss_after_load_mb"])
            for (f, _), group in by_load.items()
            if f == framework
            for r in group
        ]
        lines.append(
            f"| {LABELS[framework]} | {spread(startups)} | {spread(idle)} | {spread(after)} |"
        )

    for concurrency in sorted({c for _, c in by_load}):
        lines += [
            "",
            f"## Throughput e latência, {concurrency} conexões",
            "",
            "| Framework | req/s | p50 (ms) | p95 (ms) | p99 (ms) | não-2xx | erros |",
            "| --- | ---: | ---: | ---: | ---: | ---: | ---: |",
        ]
        for framework in frameworks:
            group = by_load.get((framework, concurrency), [])
            if not group:
                continue

            def col(name, group=group):
                return spread([float(r[name]) for r in group])

            failures = sum(int(r["non_2xx"]) for r in group)
            errors = sum(int(r["errors"]) for r in group)
            lines.append(
                f"| {LABELS[framework]} | {col('rps_mean')} | {col('latency_p50_ms')} | "
                f"{col('latency_p95_ms')} | {col('latency_p99_ms')} | {failures} | {errors} |"
            )

    payload = {(r["framework"], r["products"], r["response_bytes"]) for r in rows}
    lines += ["", "## Payload medido", "", "| Framework | produtos | bytes |", "| --- | ---: | ---: |"]
    for framework, products, size in sorted(payload):
        lines.append(f"| {LABELS[framework]} | {products} | {size} |")

    (directory / "summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines))


if __name__ == "__main__":
    main(Path(sys.argv[1]))
