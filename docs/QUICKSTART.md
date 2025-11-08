# Quick Start Benchmark

## 🎯 Esecuzione Rapida

```bash
# 1. Setup (prima volta)
./setup-benchmark.sh

# 2. Esegui benchmark (45-90 min)
./run-benchmark.sh

# 3. Visualizza risultati
./analyze-results.py benchmark-results/results_*.csv

# 4. Genera report markdown
./analyze-results.py benchmark-results/results_*.csv -m report.md
```

## 📊 Struttura Risultati

```
benchmark-results/
├── results_TIMESTAMP.txt    # Report completo
├── results_TIMESTAMP.csv    # Dati CSV
└── *.txt, *.csv, *.log      # Dati raw
```

## 🔍 Comandi Utili

```bash
# Visualizza ultimo report
cat benchmark-results/results_*.txt | tail -n 100

# CSV formattato
column -t -s',' benchmark-results/results_*.csv | less -S

# Pulisci risultati vecchi
rm -rf benchmark-results/*

# Test singola configurazione (modifica script)
# In run-benchmark.sh: CONFIGS=("fatjar")

# Verifica stato perf
perf stat -e power/energy-pkg/ sleep 1

# Verifica Docker
docker run --rm hello-world
```

## ⚡ Test Eseguiti per Config

1. ✅ **Build** - Prima build (cold)
2. ✅ **Rebuild** - Build dopo modifica
3. ✅ **Startup** - Tempo avvio + energia
4. ✅ **Idle** - Consumo a riposo (30s)
5. ✅ **Load** - Sotto carico (60s, 100 conn)

## 📈 Metriche Chiave

| Metrica | Unità | Migliore |
|---------|-------|----------|
| Build Time | secondi | ⬇️ più basso |
| Build Energy | Joules | ⬇️ più basso |
| Image Size | MB | ⬇️ più basso |
| Startup Time | secondi | ⬇️ più basso |
| Idle Energy | Joules | ⬇️ più basso |
| Load Energy | Joules | ⬇️ più basso |
| Memory | MB | ⬇️ più basso |
| Throughput | req/s | ⬆️ più alto |

## 🎭 Risultati Attesi

### Fat JAR (baseline)
- 🟡 Build: veloce
- 🟡 Size: grande (~50-100MB)
- 🟡 Startup: medio (5-15s)
- 🔴 Memory: alta (200-400MB)

### Layered JAR
- 🟢 Rebuild: velocissimo (cache)
- 🟡 Size: media (~60-110MB)
- 🟡 Startup: medio (5-15s)
- 🔴 Memory: alta (200-400MB)
- 🟢 CI/CD: ottimo

### Native Image
- 🔴 Build: lentissimo (5-20min)
- 🟢 Size: piccola (30-80MB)
- 🟢 Startup: flash (<1s)
- 🟢 Memory: bassa (50-150MB)
- 🟢 Cold starts: eccellente

## ⚠️ Troubleshooting Rapido

```bash
# Perf non funziona
sudo sysctl -w kernel.perf_event_paranoid=-1

# Porta 8080 occupata
sudo lsof -i :8080
docker stop $(docker ps -q)

# Spazio disco insufficiente
docker system prune -a --volumes -f

# Build native fallisce - aumenta memoria Docker
# Docker Desktop: Settings > Resources > Memory > 8GB+

# Performance mode (per risultati accurati)
sudo cpupower frequency-set -g performance
```

## 🧹 Cleanup

```bash
# Rimuovi immagini benchmark
docker rmi tesi-benchmark-fatjar tesi-benchmark-layered tesi-benchmark-native

# Rimuovi container orfani
docker container prune -f

# Pulizia completa Docker
docker system prune -a --volumes -f

# Rimuovi risultati
rm -rf benchmark-results/
```

## 📚 Documentazione

- [BENCHMARK.md](BENCHMARK.md) - Documentazione completa
- [Readme.md](../Readme.md) - Overview progetto
- Script: `run-benchmark.sh`, `setup-benchmark.sh`, `analyze-results.py`

