# Benchmark Scripts

Script per eseguire test di performance e consumo energetico sulle tre configurazioni Docker.

## 📋 Prerequisiti

- Linux con kernel >= 4.0
- Docker con BuildKit
- Processore con supporto RAPL (Intel Sandy Bridge+ o AMD Zen+)
- Permessi sudo per configurazione perf
- ~10 GB spazio disco
- Tempo stimato: 45-90 minuti

## 🚀 Setup

### 1. Installa dipendenze

```bash
./setup-benchmark.sh
```

Questo script installa automaticamente:
- `perf` (Linux performance counter)
- `apache2-utils` (Apache Bench per load test)
- `jq` (parsing JSON)
- `curl`, `bc` (utility)

E configura:
- Permessi per `perf` energy counters
- Docker BuildKit
- Parametri kernel necessari

### 2. Esegui benchmark

```bash
./run-benchmark.sh
```

## 📊 Test Eseguiti

### Test 1: Build Time, Size & Energy

**Cosa misura:**
- Tempo di build iniziale (cold build)
- Tempo di rebuild dopo modifica codice
- Consumo energetico durante build
- Dimensione immagine Docker finale

**Output:**
- `Build Time`: Secondi per completare la build
- `Build Energy`: Joules consumati durante build
- `Image Size`: MB occupati dall'immagine

### Test 2: Startup Time & Energy

**Cosa misura:**
- Tempo dall'avvio container all'applicazione ready
- Consumo energetico durante startup

**Output:**
- `Startup Time`: Secondi fino a first response
- `Startup Energy`: Joules durante startup

### Test 3: Idle Energy

**Cosa misura:**
- Consumo a riposo (applicazione avviata ma inattiva)
- Durata: 30 secondi dopo warmup di 10s
- Metriche CPU e RAM medie

**Output:**
- `Idle Energy`: Joules in 30s idle
- `CPU Average`: % CPU media
- `Memory Average`: MB RAM media

### Test 4: Load Test Energy

**Cosa misura:**
- Consumo sotto carico intenso
- Durata: 60 secondi
- Apache Bench: 100 connessioni concorrenti
- Metriche CPU e RAM (media e picco)

**Output:**
- `Load Energy`: Joules durante load test
- `CPU Average/Peak`: % CPU media e picco
- `Memory Average/Peak`: MB RAM media e picco
- `Requests/sec`: Throughput

## 📁 Risultati

Tutti i risultati vengono salvati in `./benchmark-results/`:

```
benchmark-results/
├── results_YYYYMMDD_HHMMSS.txt          # Report testuale completo
├── results_YYYYMMDD_HHMMSS.csv          # Dati in formato CSV
├── perf_*_YYYYMMDD_HHMMSS.txt          # Raw output perf
├── stats_*_YYYYMMDD_HHMMSS.csv         # Statistiche container
├── build_*_YYYYMMDD_HHMMSS.log         # Log build Docker
└── load_*_YYYYMMDD_HHMMSS.txt          # Output Apache Bench
```

## 📈 Analisi Risultati

### Visualizza risultati in terminale

```bash
# Leggi report completo
cat benchmark-results/results_*.txt

# Visualizza CSV formattato
column -t -s',' benchmark-results/results_*.csv | less -S
```

### Genera report e confronti

```bash
./analyze-results.py benchmark-results/results_YYYYMMDD_HHMMSS.csv
```

Output:
- Tabelle riassuntive per test
- Confronti percentuali vs baseline (Fat JAR)
- Indicatori visivi (🟢 migliore, 🔴 peggiore)

### Genera report Markdown

```bash
./analyze-results.py benchmark-results/results_*.csv -m report.md
```

Genera tabelle Markdown pronte per documentazione.

## ⚙️ Configurazione

### Modificare parametri test

Edita `run-benchmark.sh` e modifica:

```bash
# Durate
WARMUP_TIME=10              # Secondi warmup prima test
IDLE_DURATION=30            # Secondi misurazione idle
LOAD_TEST_DURATION=60       # Secondi load test

# Parametri load test
LOAD_TEST_THREADS=50        # Thread Apache Bench
LOAD_TEST_CONNECTIONS=100   # Connessioni concorrenti
```

### Configurazioni testate

Lo script testa automaticamente tutte e tre le configurazioni:

1. **fatjar** (`Dockerfile.fatjar`): Fat JAR tradizionale
2. **layered** (`Dockerfile.layered`): Layered JAR ottimizzato
3. **native** (`Dockerfile.native`): GraalVM Native Image

## 📝 Note

### Accuratezza misurazioni

Per risultati accurati:

1. **Chiudi applicazioni non essenziali**
2. **Disabilita power management**: `sudo cpupower frequency-set -g performance`
3. **Esegui su sistema idle** (no altri task intensivi)
4. **Ripeti test multiple volte** e fai la media

### Limitazioni energy counters

- **RAPL** misura consumo CPU/package, non sistema totale
- Risultati sono relativi (confronti tra configurazioni)
- Precisione dipende dal processore

**Totale per 3 configurazioni: 45-90 minuti**

## 📊 Metriche Chiave

### Build

- **Time**: Più basso = migliore
- **Energy**: Più basso = più efficiente
- **Size**: Più basso = deployment più veloce

### Startup

- **Time**: Critico per scaling rapido
- **Energy**: Impatto su cold starts frequenti

### Idle

- **Energy**: Critico per servizi long-running
- **Memory**: Impatto su densità container

### Load

- **Energy**: Efficienza sotto carico
- **Memory**: Capacità di gestire picchi
- **Throughput**: Performance pura

## 🎯 Interpretazione Risultati

### Aspettative

**Fat JAR (baseline)**
- Build veloce, size grande
- Startup medio, consumo medio-alto
- Buone performance sotto carico

**Layered JAR**
- Rebuild molto veloce (cache)
- Startup simile a fatjar
- Size leggermente più grande
- Efficiente per CI/CD

**Native Image**
- Build molto lenta (AOT compilation)
- Startup quasi istantaneo (<100ms)
- Size molto piccola
- Memory footprint minimo
- Ottimo per microservizi, serverless

## 📚 Riferimenti

- [perf Wiki](https://perf.wiki.kernel.org/)
- [RAPL Interface](https://www.kernel.org/doc/html/latest/power/powercap/powercap.html)
- [Docker BuildKit](https://docs.docker.com/build/buildkit/)
- [GraalVM Native Image](https://www.graalvm.org/native-image/)
- [Apache Bench Guide](https://httpd.apache.org/docs/2.4/programs/ab.html)

