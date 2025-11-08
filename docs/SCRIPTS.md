# 📦 Script di Benchmark - Indice

Tutti gli script necessari per eseguire i benchmark sulle tre configurazioni Docker.

## 📜 Script Disponibili

### 1️⃣ `check-prerequisites.sh` 
**Verifica prerequisiti**

```bash
./check-prerequisites.sh
```

- Controlla che tutte le dipendenze siano installate
- Verifica supporto RAPL per misurazioni energetiche
- Valida configurazione Docker e perf
- Controlla disponibilità risorse (disco, RAM, porte)
- **Esegui questo prima di tutto!**

---

### 2️⃣ `setup-benchmark.sh`
**Installazione automatica dipendenze**

```bash
./setup-benchmark.sh
```

- Installa `perf`, `apache2-utils`, `jq`, `curl`, `bc`
- Configura permessi per energy counters
- Configura Docker BuildKit
- Imposta parametri kernel necessari
- **Esegui una volta al primo setup**

---

### 3️⃣ `run-benchmark.sh` ⭐
**Script principale di benchmark**

```bash
./run-benchmark.sh
```

**Cosa fa:**
- Esegue tutti i test su tutte e 3 le configurazioni
- Misura consumo energetico con `perf`
- Raccoglie metriche CPU, RAM, dimensioni
- Genera report e CSV con risultati

**Test eseguiti:**
1. Build iniziale (cold build)
2. Rebuild dopo modifica codice
3. Startup time & energy
4. Idle consumption (30s)
5. Load test (60s, 100 connessioni)

**Durata:** 45-90 minuti

**Output:**
- `benchmark-results/results_TIMESTAMP.txt` - Report completo
- `benchmark-results/results_TIMESTAMP.csv` - Dati CSV
- File raw per analisi dettagliate

---

### 4️⃣ `analyze-results.py`
**Analisi e visualizzazione risultati**

```bash
# Visualizza risultati in terminale
./analyze-results.py benchmark-results/results_TIMESTAMP.csv

# Genera report Markdown
./analyze-results.py benchmark-results/results_TIMESTAMP.csv -m report.md
```

**Output:**
- Tabelle riassuntive formattate
- Confronti percentuali vs baseline (Fat JAR)
- Indicatori visivi (🟢 meglio, 🔴 peggio)
- Report Markdown esportabile

---

## 🚀 Workflow Completo

### Prima Esecuzione

```bash
# Step 1: Verifica sistema
./check-prerequisites.sh

# Step 2: Setup (se necessario)
./setup-benchmark.sh

# Step 3: Verifica di nuovo
./check-prerequisites.sh

# Step 4: Esegui benchmark
./run-benchmark.sh

# Step 5: Analizza risultati
./analyze-results.py benchmark-results/results_*.csv
./analyze-results.py benchmark-results/results_*.csv -m report.md
```

### Esecuzioni Successive

```bash
# Basta eseguire il benchmark
./run-benchmark.sh

# E analizzare i risultati
./analyze-results.py benchmark-results/results_*.csv
```

---

## 📚 Documentazione

- **[QUICKSTART.md](QUICKSTART.md)** - Guida rapida, comandi essenziali
- **[BENCHMARK.md](BENCHMARK.md)** - Documentazione completa e dettagliata
- **[Readme.md](../Readme.md)** - Overview generale del progetto

---

## 🎯 Quick Reference

| Task | Comando |
|------|---------|
| Verifica sistema | `./check-prerequisites.sh` |
| Installa dipendenze | `./setup-benchmark.sh` |
| Esegui benchmark | `./run-benchmark.sh` |
| Analizza risultati | `./analyze-results.py benchmark-results/results_*.csv` |
| Report Markdown | `./analyze-results.py benchmark-results/results_*.csv -m report.md` |
| Visualizza report | `cat benchmark-results/results_*.txt` |
| CSV formattato | `column -t -s',' benchmark-results/results_*.csv \| less -S` |
| Pulizia risultati | `rm -rf benchmark-results/*` |
| Pulizia Docker | `docker system prune -a -f` |

---

## ⚙️ Configurazione Script

### Modificare durata test

Edita `run-benchmark.sh`:

```bash
WARMUP_TIME=10              # Warmup prima dei test
IDLE_DURATION=30            # Durata test idle
LOAD_TEST_DURATION=60       # Durata load test
LOAD_TEST_CONNECTIONS=100   # Connessioni concorrenti
```

### Testare solo alcune configurazioni

Edita `run-benchmark.sh`:

```bash
# Tutte (default)
CONFIGS=("fatjar" "layered" "native")

# Solo fat e layered
CONFIGS=("fatjar" "layered")

# Solo native
CONFIGS=("native")
```

---

## 🔍 Struttura Output

```
benchmark-results/
├── results_YYYYMMDD_HHMMSS.txt       # Report testuale completo
├── results_YYYYMMDD_HHMMSS.csv       # Dati tabulari CSV
│
├── perf_build_CONFIG_TIMESTAMP.txt   # Output raw perf (build)
├── perf_startup_CONFIG_TIMESTAMP.txt # Output raw perf (startup)
├── perf_idle_CONFIG_TIMESTAMP.txt    # Output raw perf (idle)
├── perf_load_CONFIG_TIMESTAMP.txt    # Output raw perf (load)
│
├── stats_idle_CONFIG_TIMESTAMP.csv   # Stats Docker (idle)
├── stats_load_CONFIG_TIMESTAMP.csv   # Stats Docker (load)
│
├── build_CONFIG_TIMESTAMP.log        # Log build Docker
└── load_CONFIG_TIMESTAMP.txt         # Output Apache Bench
```

---

## 🐛 Troubleshooting

### Script non eseguibili
```bash
chmod +x *.sh *.py
```

### Perf permission denied
```bash
sudo sysctl -w kernel.perf_event_paranoid=-1
```

### Energy counters non disponibili
- Verifica CPU supporti RAPL (Intel Sandy Bridge+ o AMD Zen+)
- Alcuni contatori potrebbero non funzionare in VM
- I test di tempo/risorse funzioneranno comunque

### Porta 8080 in uso
```bash
# Trova processo
sudo lsof -i :8080

# Ferma container Docker
docker stop $(docker ps -q)
```

### Build native out of memory
- Aumenta memoria Docker (Docker Desktop: Settings > Resources > Memory > 8GB)
- Oppure aggiungi swap

---

## 📊 Metriche Raccolte

| Categoria | Metriche |
|-----------|----------|
| **Build** | Tempo, Energia, Dimensione immagine |
| **Startup** | Tempo avvio, Energia startup |
| **Idle** | Energia idle, CPU %, RAM MB |
| **Load** | Energia, CPU avg/peak %, RAM avg/peak MB, Throughput |

---

## 💡 Tips

**Per risultati accurati:**
1. Chiudi altre applicazioni
2. Disabilita power management: `sudo cpupower frequency-set -g performance`
3. Esegui su sistema idle
4. Ripeti test e fai media di più esecuzioni

**Per test veloci (development):**
- Riduci `IDLE_DURATION` e `LOAD_TEST_DURATION` in `run-benchmark.sh`
- Testa solo una configurazione per volta

**Per analisi dettagliate:**
- Importa CSV in Excel/LibreOffice
- Usa pandas in Python per grafici personalizzati
- Script raw output disponibili per analisi custom

---

## 🆘 Supporto

Per problemi o domande:
1. Controlla [BENCHMARK.md](BENCHMARK.md) - FAQ e troubleshooting completo
2. Esegui `./check-prerequisites.sh` per diagnostica
3. Verifica log in `benchmark-results/`
4. Controlla output Docker: `docker logs CONTAINER_NAME`

---

**Pronto per iniziare?** → `./check-prerequisites.sh` 🚀

