# Spring Boot Containerization Benchmark

Confronto di tre strategie di containerizzazione per applicazioni Spring Boot: consumo energetico, CPU, RAM e disco.

## Applicazione

**Stack:** Spring Boot 3.x • Java 21 • PostgreSQL • Kafka

**Funzionalità:**
- 3-4 endpoint REST (CRUD)
- Spring Data JPA

## Configurazioni

### A. Fat JAR
- Base: Alpine + JRE completo
- JAR monolitico
- Riferimento baseline

### B. Layered JAR
- Layer: dependencies, spring-boot-loader, application
- Cache mount Maven
- Ottimizzato per rebuild
- Ottimizzazioni JVM

### C. Native Image
- GraalVM AOT compilation
- Runtime nativo (no JVM)
- Gestione memoria kernel
- Startup istantaneo

## Test
1. **Build time & Size & Energy** (Energia e tempo di build, dimensione dell'immagine):
   1. Prima build
   2. Build dopo aggiunta dipendenza e modifica codice
2. **Startup Energy & Time** (Energia e tempi di avvio)
3. **Idle Energy** (Consumo a riposo)
4. **Load Test Energy** (Efficienza sotto carico)

## 🚀 Esecuzione Benchmark

### Setup
```bash
./setup-benchmark.sh
```

### Esegui tutti i test
```bash
./run-benchmark.sh                    # Tutte le configurazioni (default)
./run-benchmark.sh layered            # Solo layered
./run-benchmark.sh fatjar layered     # Fat JAR e Layered
./run-benchmark.sh native             # Solo native
./run-benchmark.sh --help             # Mostra l'help
```

### Analizza risultati
```bash
./analyze-results.py benchmark-results/results_*.csv
./analyze-results.py benchmark-results/results_*.csv -m report.md
```

**Documentazione completa:** [BENCHMARK.md](docs/BENCHMARK.md)

