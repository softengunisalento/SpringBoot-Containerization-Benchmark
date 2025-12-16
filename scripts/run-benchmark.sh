#!/bin/bash
# =================================================================
# Script di Benchmark per Configurazioni Docker Spring Boot
# Monitora consumo energetico, tempi, CPU, RAM e dimensioni
# =================================================================

set -e
export LC_NUMERIC=C

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Directory e file
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_BASE_DIR="../benchmark-results"
RESULTS_DIR="${RESULTS_BASE_DIR}/${TIMESTAMP}"
RESULTS_FILE="${RESULTS_DIR}/results.txt"
CSV_FILE="${RESULTS_DIR}/results.csv"

# Configurazioni Docker
# Accetta configurazioni da linea di comando, altrimenti usa default
if [ $# -gt 0 ]; then
    CONFIGS=("$@")
else
    # Default: tutte le configurazioni
    CONFIGS=("fatjar" "layered" "native")
fi

IMAGE_PREFIX="tesi-benchmark"

# Parametri test
WARMUP_TIME=5
IDLE_DURATION=20
LOAD_TEST_DURATION=30
LOAD_TEST_THREADS=50
LOAD_TEST_CONNECTIONS=100

# Dipendenza temporanea per test rebuild (parametrizzabile)
REBUILD_DEP_GROUP_ID="org.apache.commons"
REBUILD_DEP_ARTIFACT_ID="commons-lang3"
REBUILD_DEP_VERSION="3.19.0"

# Variabile per baseline energetica
BASELINE_POWER_W=0

# URL di test
APP_URL="http://localhost:8080"
HEALTH_URL="${APP_URL}/actuator/health"
API_URL="${APP_URL}/api/users"

# Funzione di help
show_help() {
    cat << EOF
${GREEN}=====================================${NC}
${GREEN}  Spring Boot Benchmark Suite${NC}
${GREEN}=====================================${NC}

Uso: $0 [configurazioni...]

Configurazioni disponibili:
  fatjar   - Fat JAR tradizionale
  layered  - Layered JAR con cache ottimizzate
  native   - Native image GraalVM

Esempi:
  $0                    # Esegue tutte le configurazioni (default)
  $0 layered            # Esegue solo layered
  $0 fatjar layered     # Esegue fatjar e layered
  $0 native             # Esegue solo native

EOF
    exit 0
}

# Verifica se è richiesto help
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_help
fi

# Validazione configurazioni
VALID_CONFIGS=("fatjar" "layered" "native")
for config in "${CONFIGS[@]}"; do
    valid_config_string=" ${VALID_CONFIGS[*]} "
    if [[ ! ${valid_config_string} =~  ${config}  ]]; then
        echo -e "${RED}Errore: configurazione '${config}' non valida${NC}"
        echo "Configurazioni valide: ${VALID_CONFIGS[*]}"
        echo ""
        echo "Usa '$0 --help' per maggiori informazioni"
        exit 1
    fi
done

echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}  Spring Boot Benchmark Suite${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""
echo -e "${BLUE}Configurazioni da testare:${NC} ${CONFIGS[*]}"
echo ""

# Crea directory risultati
mkdir -p "${RESULTS_DIR}"


# Inizializza file risultati
cat > "${RESULTS_FILE}" << EOF
Spring Boot Containerization Benchmark
Timestamp: ${TIMESTAMP}
Date: $(date)
Host: $(hostname)
CPU: $(lscpu | grep "Model name" | cut -d':' -f2 | xargs)
Kernel: $(uname -r)

=====================================
EOF

# Inizializza CSV
cat > "${CSV_FILE}" << 'EOF'
Config,Test,BuildTime_s,BuildEnergy_J,ImageSize_MB,StartupTime_s,StartupEnergy_J,IdleEnergy_J,LoadTotalEnergy_J,LoadPeakPower_W,MemoryAvg_MB,MemoryPeak_MB,CPUAvg_%
EOF

# Crea README nella cartella risultati
cat > "${RESULTS_DIR}/README.md" << EOF
# Benchmark Results - ${TIMESTAMP}

Esecuzione del: $(date)
Host: $(hostname)
CPU: $(lscpu | grep "Model name" | cut -d':' -f2 | xargs)
Kernel: $(uname -r)

## Configurazioni Testate

${CONFIGS[*]}

## File Generati

- \`results.txt\` - Report testuale completo
- \`results.csv\` - Dati tabulari CSV
- \`perf_*.txt\` - Output raw perf per energia
- \`stats_*.csv\` - Statistiche Docker (CPU, RAM)
- \`build_*.log\` - Log build Docker
- \`load_*.txt\` - Output Apache Bench

## Analisi

\`\`\`bash
# Visualizza risultati
cat results.txt

# CSV formattato
column -t -s',' results.csv | less -S

# Analisi comparativa
../../scripts/analyze-results.py results.csv
\`\`\`
EOF

# Funzione per logging
log() {
    echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $1" | tee -a "${RESULTS_FILE}"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1" | tee -a "${RESULTS_FILE}"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1" | tee -a "${RESULTS_FILE}"
}

log_section() {
    echo "" | tee -a "${RESULTS_FILE}"
    echo -e "${YELLOW}═══════════════════════════════════${NC}" | tee -a "${RESULTS_FILE}"
    echo -e "${YELLOW}  $1${NC}" | tee -a "${RESULTS_FILE}"
    echo -e "${YELLOW}═══════════════════════════════════${NC}" | tee -a "${RESULTS_FILE}"
    echo "" | tee -a "${RESULTS_FILE}"
}

# Funzione per verificare dipendenze
check_dependencies() {
    log "Verifico dipendenze..."

    local missing=()

    command -v docker &> /dev/null || missing+=("docker")
    command -v perf &> /dev/null || missing+=("perf")
    command -v curl &> /dev/null || missing+=("curl")
    command -v jq &> /dev/null || missing+=("jq")
    command -v ab &> /dev/null || missing+=("apache-bench")

    if [ ${#missing[@]} -ne 0 ]; then
        log_error "Dipendenze mancanti: ${missing[*]}"
        echo "Installa con: sudo apt install linux-tools-common linux-tools-generic apache2-utils jq"
        exit 1
    fi

    # Verifica permessi perf
    if ! perf stat -e power/energy-pkg/ sleep 0.1 &> /dev/null; then
        log_error "perf non ha permessi per leggere energy counters"
        echo "Esegui: sudo sysctl -w kernel.perf_event_paranoid=-1"
        echo "O aggiungi l'utente al gruppo power"
        exit 1
    fi

    log_success "Tutte le dipendenze sono disponibili"
}

# Funzione per misurare baseline energetica
measure_baseline() {
    log_section "Misurazione Baseline Energetica (Idle PC)"
    local duration=10
    local temp_file="${RESULTS_DIR}/baseline_energy.txt"

    log "Misuro consumo idle del sistema per ${duration}s..."
    measure_energy "${duration}" "${temp_file}"

    local total_energy=$(extract_total_energy "${temp_file}")

    # Calcola potenza media in Watt
    BASELINE_POWER_W=$(echo "${total_energy} / ${duration}" | bc -l)

    # Arrotonda a 2 decimali
    BASELINE_POWER_W=$(printf "%.2f" "${BASELINE_POWER_W}")

    log_success "Baseline calcolata: ${BASELINE_POWER_W} W"
    log "Questo valore verrà sottratto da tutte le misurazioni energetiche."
}

# Funzione per misurare energia con perf
measure_energy() {
    local duration=$1
    local output_file=$2

    # Usa solo power/energy-pkg/ perché energy-cores e energy-ram non sono disponibili su tutti i sistemi
    # Forza locale C per avere punto come separatore decimale
    # -a monitora tutte le CPU del sistema (non solo un singolo processo)
    LC_ALL=C timeout "${duration}" perf stat -e power/energy-pkg/ \
        -I 1000 -x ',' -a sleep "${duration}" 2> "${output_file}" || true
}

# Funzione per estrarre energia totale da output perf
extract_total_energy() {
    local perf_output=$1

    # Estrai energia package in Joules
    # Con LC_ALL=C il formato è: valore,unità,label,event,...
    # Il valore è nel primo campo con punto come decimale
    local energy=$(grep "power/energy-pkg/" "${perf_output}" 2>/dev/null | \
        awk -F',' '{sum+=$1} END {if (sum > 0) printf "%.2f", sum; else print "0"}')

    echo "${energy:-0}"
}

# Funzione per estrarre energia media da output perf
extract_avg_energy() {
    local perf_output=$1

    # Calcola la media dei sample di energia
    local energy=$(grep "power/energy-pkg/" "${perf_output}" 2>/dev/null | \
        awk -F',' '{sum+=$1; count++} END {if (count > 0) printf "%.2f", sum/count; else print "0"}')

    echo "${energy:-0}"
}

# Funzione per estrarre energia di picco da output perf
extract_peak_energy() {
    local perf_output=$1

    # Trova il valore massimo di energia in un singolo sample
    local energy=$(grep "power/energy-pkg/" "${perf_output}" 2>/dev/null | \
        awk -F',' '{if ($1 > max) max=$1} END {if (max > 0) printf "%.2f", max; else print "0"}')

    echo "${energy:-0}"
}

# Nome del container postgres per il benchmark
POSTGRES_CONTAINER_NAME="tesi-benchmark-postgres"

# Funzione per cleanup container
cleanup_container() {
    local container_name=$1

    if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        log "Rimuovo container ${container_name}..."
        docker stop "${container_name}" &> /dev/null || true
        docker rm "${container_name}" &> /dev/null || true
    fi
}

# Funzione per cleanup completo di tutti i container del benchmark
cleanup_all_containers() {
    log "Pulizia di tutti i container del benchmark..."

    # Ferma e rimuovi container di test
    for config in "${CONFIGS[@]}"; do
        cleanup_container "${IMAGE_PREFIX}-${config}-startup"
        cleanup_container "${IMAGE_PREFIX}-${config}-idle"
        cleanup_container "${IMAGE_PREFIX}-${config}-load"
    done

    # Ferma e rimuovi postgres
    cleanup_container "${POSTGRES_CONTAINER_NAME}"

    log_success "Tutti i container sono stati rimossi"

    # Rimuovi le immagini create durante il benchmark
    log "Rimozione immagini Docker del benchmark..."
    for config in "${CONFIGS[@]}"; do
        local image_name="${IMAGE_PREFIX}-${config}"
        if docker images -q "${image_name}" 2> /dev/null | grep -q .; then
            log "Rimuovo immagine ${image_name}..."
            docker rmi "${image_name}" &> /dev/null || true
        fi
    done

    log_success "Tutte le immagini sono state rimosse"
}

# Funzione per avviare postgres per il benchmark
start_postgres() {
    log "Avvio database PostgreSQL per il benchmark..."

    # Rimuovi eventuali container postgres precedenti
    cleanup_container "${POSTGRES_CONTAINER_NAME}"

    # Avvia postgres con rimozione automatica
    docker run -d --rm \
        --name "${POSTGRES_CONTAINER_NAME}" \
        -e POSTGRES_DB=testdb \
        -e POSTGRES_USER=postgres \
        -e POSTGRES_PASSWORD=postgres \
        -p 5436:5432 \
        postgres:15-alpine > /dev/null

    log "Attendo che PostgreSQL sia pronto..."
    local max_attempts=30
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if docker exec "${POSTGRES_CONTAINER_NAME}" pg_isready -U postgres &> /dev/null; then
            log_success "PostgreSQL pronto"
            break
        fi
        sleep 1
        attempt=$((attempt + 1))
    done

    if [ $attempt -eq $max_attempts ]; then
        log_error "PostgreSQL non si è avviato in tempo"
        return 1
    fi

    # Crea il database tesidb se non esiste
    log "Verifico database tesidb..."
    docker exec "${POSTGRES_CONTAINER_NAME}" psql -U postgres -d testdb -tc "SELECT 1 FROM pg_database WHERE datname = 'tesidb'" | grep -q 1

    if [ $? -ne 0 ]; then
        docker exec "${POSTGRES_CONTAINER_NAME}" psql -U postgres -d testdb -c "CREATE DATABASE tesidb;" > /dev/null
        log_success "Database tesidb creato"
    else
        log_success "Database tesidb già presente"
    fi

    return 0
}

# Trap per cleanup automatico in caso di interruzione o errore
trap cleanup_all_containers EXIT INT TERM

# Funzione per attendere che l'app sia pronta
wait_for_app() {
    local container_name=$1
    local max_attempts=60
    local attempt=0

    log "Attendo avvio applicazione..."

    while [ $attempt -lt $max_attempts ]; do
        # Verifica se il container è ancora in esecuzione
        if ! docker ps --filter "name=${container_name}" --filter "status=running" --format '{{.Names}}' | grep -q "^${container_name}$"; then
            log_error "Container ${container_name} non è più in esecuzione!"
            log "Ultimi log del container:"
            docker logs --tail 50 "${container_name}" 2>&1 | tee -a "${RESULTS_FILE}"
            return 1
        fi

        # Verifica se l'applicazione risponde
        if curl -s "${HEALTH_URL}" &> /dev/null || \
           curl -s "${APP_URL}" &> /dev/null || \
           curl -s "${API_URL}" &> /dev/null; then
            log_success "Applicazione pronta!"
            return 0
        fi

        sleep 1
        attempt=$((attempt + 1))

        if [ $((attempt % 10)) -eq 0 ]; then
            log "Tentativo ${attempt}/${max_attempts}..."
            # Mostra uno snippet dei log per debugging
            docker logs --tail 5 "${container_name}" 2>&1 | head -3
        fi
    done

    log_error "Timeout in attesa dell'applicazione"
    log "Log completi del container:"
    docker logs "${container_name}" 2>&1 | tail -100 | tee -a "${RESULTS_FILE}"
    return 1
}

# Funzione per ottenere statistiche container
get_container_stats() {
    local container_name=$1
    local duration=$2
    local output_file=$3

    # Monitora stats per durata specificata
    local end_time=$(($(date +%s) + duration))

    echo "timestamp,cpu_percent,memory_mb" > "${output_file}"

    while [ $(date +%s) -lt ${end_time} ]; do
        local stats=$(docker stats --no-stream --format "{{.CPUPerc}},{{.MemUsage}}" "${container_name}" 2>/dev/null || echo "0%,0MiB / 0MiB")
        local cpu=$(echo "${stats}" | cut -d',' -f1 | tr -d '%')
        local mem=$(echo "${stats}" | cut -d',' -f2 | cut -d'/' -f1 | tr -d 'MiB' | xargs)

        echo "$(date +%s),${cpu},${mem}" >> "${output_file}"
        sleep 1
    done
}

# Funzione per calcolare medie da stats
calculate_stats_avg() {
    local stats_file=$1

    awk -F',' 'NR>1 {cpu+=$2; mem+=$3; count++} END {
        if (count > 0) {
            printf "%.2f,%.2f", cpu/count, mem/count
        } else {
            printf "0,0"
        }
    }' "${stats_file}"
}

# Funzione per calcolare peak da stats
calculate_stats_peak() {
    local stats_file=$1

    awk -F',' 'NR>1 {
        if ($2 > max_cpu) max_cpu=$2;
        if ($3 > max_mem) max_mem=$3;
    } END {
        printf "%.2f,%.2f", max_cpu, max_mem
    }' "${stats_file}"
}

# =================================================================
# Funzioni per gestione dipendenze temporanee pom.xml
# =================================================================

# Funzione per fare backup del pom.xml
backup_pom() {
    local pom_file="../pom.xml"
    local backup_file="../pom.xml.backup"

    if [ -f "${pom_file}" ]; then
        cp "${pom_file}" "${backup_file}"
        log "Backup pom.xml creato"
        return 0
    else
        log_error "pom.xml non trovato"
        return 1
    fi
}

# Funzione per ripristinare il pom.xml dal backup
restore_pom() {
    local pom_file="../pom.xml"
    local backup_file="../pom.xml.backup"

    if [ -f "${backup_file}" ]; then
        mv "${backup_file}" "${pom_file}"
        log "pom.xml ripristinato"
        return 0
    else
        log_error "Backup pom.xml non trovato"
        return 1
    fi
}

# Funzione per aggiungere una dipendenza al pom.xml
add_dependency_to_pom() {
    local group_id=$1
    local artifact_id=$2
    local version=$3
    local pom_file="../pom.xml"

    log "Aggiunta dipendenza temporanea: ${group_id}:${artifact_id}:${version}"

    # Trova la riga con </dependencies> e inserisci prima la nuova dipendenza
    local temp_file="${pom_file}.tmp"

    awk -v gid="${group_id}" -v aid="${artifact_id}" -v ver="${version}" '
    /<\/dependencies>/ {
        print "\t\t<!-- TEMPORARY DEPENDENCY FOR REBUILD TEST -->"
        print "\t\t<dependency>"
        print "\t\t\t<groupId>" gid "</groupId>"
        print "\t\t\t<artifactId>" aid "</artifactId>"
        print "\t\t\t<version>" ver "</version>"
        print "\t\t</dependency>"
    }
    { print }
    ' "${pom_file}" > "${temp_file}"

    mv "${temp_file}" "${pom_file}"

    log "Dipendenza aggiunta al pom.xml"
}

# Funzione per modificare una classe Java (trigger rebuild)
touch_java_file() {
    local java_file="../src/main/java/com/example/tesi/model/User.java"

    if [ -f "${java_file}" ]; then
        touch "${java_file}"
        log "File Java modificato: ${java_file}"
    else
        log_warning "File Java non trovato, uso solo modifica pom.xml"
    fi
}

# =================================================================
# TEST 1: Build Time, Size & Energy
# =================================================================
test_build() {
    local config=$1
    local is_rebuild=$2

    local test_name="Build"
    [ "${is_rebuild}" = "true" ] && test_name="Rebuild"

    log_section "${test_name}: ${config}"

    local image_name="${IMAGE_PREFIX}-${config}"
    local dockerfile="../Dockerfile.${config}"
    local perf_file="${RESULTS_DIR}/perf_build_${config}.txt"
    local build_log="${RESULTS_DIR}/build_${config}.log"

    # Determina se usare BuildKit in base alla configurazione
    local use_buildkit=""
    if [[ "${config}" == "layered" || "${config}" == "native" ]]; then
        use_buildkit="DOCKER_BUILDKIT=1"
        log "BuildKit ABILITATO per ${config} (usa mount cache)"
    else
        use_buildkit="DOCKER_BUILDKIT=0"
        log "BuildKit DISABILITATO per ${config} (non usa mount cache)"
    fi

    # Pulizia pre-build
    local build_args=""
    if [ "${is_rebuild}" != "true" ]; then
        log "Pulizia cache e immagini precedenti..."
        docker rmi "${image_name}" &> /dev/null || true
        docker builder prune -af &> /dev/null || true
        build_args="--no-cache"
        log "Build senza cache (cold build)"
    else
        # Per il rebuild: backup pom.xml e aggiungi dipendenza temporanea
        log "Simulazione modifica per rebuild: aggiunta dipendenza temporanea"
        backup_pom || return 1
        add_dependency_to_pom "${REBUILD_DEP_GROUP_ID}" "${REBUILD_DEP_ARTIFACT_ID}" "${REBUILD_DEP_VERSION}"
        touch_java_file
        log "Build con cache (rebuild)"
    fi

    log "Avvio build per ${config}..."

    # Misura build time
    local start_time=$(date +%s.%N)

    # Esegui docker build in background (con o senza cache) con BuildKit configurato
    env ${use_buildkit} docker build ${build_args} -t "${image_name}" -f "${dockerfile}" .. &> "${build_log}" &
    local build_pid=$!

    # Monitora energia durante la build con perf in loop
    rm -f "${perf_file}"
    while kill -0 ${build_pid} 2>/dev/null; do
        LC_ALL=C perf stat -e power/energy-pkg/ -o "${perf_file}.tmp" -a -x ',' sleep 1 2>/dev/null || true
        if [ -f "${perf_file}.tmp" ]; then
            cat "${perf_file}.tmp" >> "${perf_file}"
            rm -f "${perf_file}.tmp"
        fi
    done

    # Attendi completamento build
    wait ${build_pid}
    local build_exit=$?

    local end_time=$(date +%s.%N)
    local build_time=$(echo "${end_time} - ${start_time}" | bc)

    if [ ${build_exit} -ne 0 ]; then
        log_error "Build fallita per ${config}"
        cat "${build_log}"
        return 1
    fi

    log_success "Build completata in ${build_time}s"

    # Estrai energia totale sommando tutti i sample
    local energy_raw=$(grep "power/energy-pkg/" "${perf_file}" 2>/dev/null | \
        awk -F',' '{sum+=$1} END {printf "%.2f", sum}')
    [ -z "$energy_raw" ] && energy_raw="0"

    # Calcola energia netta sottraendo baseline
    local baseline_energy=$(echo "${BASELINE_POWER_W} * ${build_time}" | bc -l)
    local energy=$(echo "${energy_raw} - ${baseline_energy}" | bc -l)
    if (( $(echo "$energy < 0" | bc -l) )); then energy=0; fi
    energy=$(printf "%.2f" "${energy}")

    log "Energia consumata: ${energy} J (Netta, Baseline: ${BASELINE_POWER_W} W)"

    # Dimensione immagine
    local image_size=$(docker images "${image_name}" --format "{{.Size}}" | head -1)
    local size_mb=$(echo "${image_size}" | sed 's/MB//; s/GB/*1024/' | bc 2>/dev/null || echo "0")

    log "Dimensione immagine: ${image_size} (${size_mb} MB)"

    # Salva risultati parziali
    echo "${config},${test_name},${build_time},${energy},${size_mb},-,-,-,-,-,-,-,-" >> "${CSV_FILE}"

    echo "" | tee -a "${RESULTS_FILE}"
    echo "Configuration: ${config}" | tee -a "${RESULTS_FILE}"
    echo "Test: ${test_name}" | tee -a "${RESULTS_FILE}"
    echo "Build Time: ${build_time} s" | tee -a "${RESULTS_FILE}"
    echo "Build Energy: ${energy} J" | tee -a "${RESULTS_FILE}"
    echo "Image Size: ${size_mb} MB" | tee -a "${RESULTS_FILE}"
    echo "" | tee -a "${RESULTS_FILE}"

    # Se era un rebuild, ripristina il pom.xml originale
    if [ "${is_rebuild}" = "true" ]; then
        log "Ripristino pom.xml originale"
        restore_pom
    fi
}

# =================================================================
# TEST 2: Startup Time & Energy
# =================================================================
test_startup() {
    local config=$1

    log_section "Startup: ${config}"

    local image_name="${IMAGE_PREFIX}-${config}"
    local container_name="${IMAGE_PREFIX}-${config}-startup"
    local perf_file="${RESULTS_DIR}/perf_startup_${config}.txt"

    cleanup_container "${container_name}"

    log "Avvio container e misurazione startup..."

    local start_time=$(date +%s.%N)

    # Avvia container in background con network host per accedere al database sull'host
    docker run -d --name "${container_name}" --network host "${image_name}" > /dev/null

    # Crea file marker per il loop perf
    touch "${perf_file}.monitor"

    # Monitora energia durante lo startup con perf in loop
    rm -f "${perf_file}"

    # Avvia monitoraggio energia in background
    (
        while [ -f "${perf_file}.monitor" ]; do
            LC_ALL=C perf stat -e power/energy-pkg/ -o "${perf_file}.tmp" -a -x ',' sleep 1 2>/dev/null || true
            if [ -f "${perf_file}.tmp" ]; then
                cat "${perf_file}.tmp" >> "${perf_file}"
                rm -f "${perf_file}.tmp"
            fi
        done
    ) &
    local perf_monitor_pid=$!

    # Attendi che l'app sia pronta
    if ! wait_for_app "${container_name}"; then
        log_error "Startup fallito per ${config}"
        docker logs "${container_name}"
        rm -f "${perf_file}.monitor"
        kill ${perf_monitor_pid} 2>/dev/null || true
        wait ${perf_monitor_pid} 2>/dev/null || true
        cleanup_container "${container_name}"
        return 1
    fi

    local end_time=$(date +%s.%N)
    local startup_time=$(echo "${end_time} - ${start_time}" | bc)

    # Ferma monitoraggio energia
    rm -f "${perf_file}.monitor"
    sleep 1  # Attendi ultimo sample
    kill ${perf_monitor_pid} 2>/dev/null || true
    wait ${perf_monitor_pid} 2>/dev/null || true

    log_success "Startup completato in ${startup_time}s"

    # Debug: verifica sample raccolti
    local sample_count=$(grep -c "power/energy-pkg/" "${perf_file}" 2>/dev/null || echo "0")
    log "Sample energia raccolti: ${sample_count}"

    # Estrai energia totale sommando tutti i sample
    local energy_raw=$(grep "power/energy-pkg/" "${perf_file}" 2>/dev/null | \
        awk -F',' '{sum+=$1} END {printf "%.2f", sum}')
    [ -z "$energy_raw" ] && energy_raw="0"

    # Calcola energia netta
    local baseline_energy=$(echo "${BASELINE_POWER_W} * ${startup_time}" | bc -l)
    local energy=$(echo "${energy_raw} - ${baseline_energy}" | bc -l)
    if (( $(echo "$energy < 0" | bc -l) )); then energy=0; fi
    energy=$(printf "%.2f" "${energy}")

    log "Energia consumata startup: ${energy} J (Netta)"

    # Cleanup
    cleanup_container "${container_name}"

    echo "" | tee -a "${RESULTS_FILE}"
    echo "Configuration: ${config}" | tee -a "${RESULTS_FILE}"
    echo "Test: Startup" | tee -a "${RESULTS_FILE}"
    echo "Startup Time: ${startup_time} s" | tee -a "${RESULTS_FILE}"
    echo "Startup Energy: ${energy} J" | tee -a "${RESULTS_FILE}"
    echo "" | tee -a "${RESULTS_FILE}"

    # Aggiungi al CSV (update riga se esiste, altrimenti crea)
    echo "${config},Startup,-,-,-,${startup_time},${energy},-,-,-,-,-,-" >> "${CSV_FILE}"
}

# =================================================================
# TEST 3: Idle Energy
# =================================================================
test_idle() {
    local config=$1

    log_section "Idle: ${config}"

    local image_name="${IMAGE_PREFIX}-${config}"
    local container_name="${IMAGE_PREFIX}-${config}-idle"
    local perf_file="${RESULTS_DIR}/perf_idle_${config}.txt"
    local stats_file="${RESULTS_DIR}/stats_idle_${config}.csv"

    cleanup_container "${container_name}"

    log "Avvio container..."
    docker run -d --name "${container_name}" --network host "${image_name}" > /dev/null

    if ! wait_for_app "${container_name}"; then
        log_error "Startup fallito per ${config}"
        cleanup_container "${container_name}"
        return 1
    fi

    log "Warmup di ${WARMUP_TIME}s..."
    sleep ${WARMUP_TIME}

    log "Misurazione idle per ${IDLE_DURATION}s..."

    # Avvia monitoraggio energia e stats
    measure_energy ${IDLE_DURATION} "${perf_file}" &
    local perf_pid=$!

    get_container_stats "${container_name}" ${IDLE_DURATION} "${stats_file}" &
    local stats_pid=$!

    # Attendi completamento
    wait ${perf_pid} 2>/dev/null || true
    wait ${stats_pid} 2>/dev/null || true

    # Estrai metriche
    local energy_raw=$(extract_total_energy "${perf_file}")

    # Calcola energia netta
    local baseline_energy=$(echo "${BASELINE_POWER_W} * ${IDLE_DURATION}" | bc -l)
    local energy=$(echo "${energy_raw} - ${baseline_energy}" | bc -l)
    if (( $(echo "$energy < 0" | bc -l) )); then energy=0; fi
    energy=$(printf "%.2f" "${energy}")

    local avg_stats=$(calculate_stats_avg "${stats_file}")
    local cpu_avg=$(echo "${avg_stats}" | cut -d',' -f1)
    local mem_avg=$(echo "${avg_stats}" | cut -d',' -f2)

    log_success "Idle completato"
    log "Energia: ${energy} J"
    log "CPU media: ${cpu_avg}%"
    log "RAM media: ${mem_avg} MB"

    # Cleanup
    cleanup_container "${container_name}"

    echo "" | tee -a "${RESULTS_FILE}"
    echo "Configuration: ${config}" | tee -a "${RESULTS_FILE}"
    echo "Test: Idle" | tee -a "${RESULTS_FILE}"
    echo "Duration: ${IDLE_DURATION} s" | tee -a "${RESULTS_FILE}"
    echo "Idle Energy: ${energy} J" | tee -a "${RESULTS_FILE}"
    echo "CPU Average: ${cpu_avg}%" | tee -a "${RESULTS_FILE}"
    echo "Memory Average: ${mem_avg} MB" | tee -a "${RESULTS_FILE}"
    echo "" | tee -a "${RESULTS_FILE}"

    echo "${config},Idle,-,-,-,-,-,${energy},-,-,${mem_avg},-,${cpu_avg}" >> "${CSV_FILE}"
}

# =================================================================
# TEST 4: Load Test Energy
# =================================================================
test_load() {
    local config=$1

    log_section "Load Test: ${config}"

    local image_name="${IMAGE_PREFIX}-${config}"
    local container_name="${IMAGE_PREFIX}-${config}-load"
    local perf_file="${RESULTS_DIR}/perf_load_${config}.txt"
    local stats_file="${RESULTS_DIR}/stats_load_${config}.csv"
    local load_file="${RESULTS_DIR}/load_${config}.txt"

    cleanup_container "${container_name}"

    log "Avvio container..."
    docker run -d --name "${container_name}" --network host "${image_name}" > /dev/null

    if ! wait_for_app "${container_name}"; then
        log_error "Startup fallito per ${config}"
        cleanup_container "${container_name}"
        return 1
    fi

    log "Warmup di ${WARMUP_TIME}s..."
    sleep ${WARMUP_TIME}

    # Popola alcuni dati di test
    log "Popolamento dati di test..."
    for i in {1..10}; do
        curl -s -X POST "${API_URL}" \
            -H "Content-Type: application/json" \
            -d "{\"name\":\"User${i}\",\"email\":\"user${i}@test.com\"}" > /dev/null || true
    done

    log "Avvio load test per ${LOAD_TEST_DURATION}s..."

    # Avvia monitoraggio energia e stats
    measure_energy ${LOAD_TEST_DURATION} "${perf_file}" &
    local perf_pid=$!

    get_container_stats "${container_name}" ${LOAD_TEST_DURATION} "${stats_file}" &
    local stats_pid=$!

    # Esegui load test con apache bench
    ab -t ${LOAD_TEST_DURATION} -c ${LOAD_TEST_CONNECTIONS} -n 1000000 "${API_URL}/" > "${load_file}" 2>&1 &
    local ab_pid=$!

    # Attendi completamento
    wait ${ab_pid} 2>/dev/null || true
    wait ${perf_pid} 2>/dev/null || true
    wait ${stats_pid} 2>/dev/null || true

    # Estrai metriche energia
    local energy_total_raw=$(extract_total_energy "${perf_file}")    # Energia totale in Joules
    local power_avg_raw=$(extract_avg_energy "${perf_file}")         # Potenza media in Watt (J/s)
    local power_peak=$(extract_peak_energy "${perf_file}")       # Potenza di picco in Watt (J/s)

    # Calcola valori netti
    local baseline_energy=$(echo "${BASELINE_POWER_W} * ${LOAD_TEST_DURATION}" | bc -l)
    local energy_total=$(echo "${energy_total_raw} - ${baseline_energy}" | bc -l)
    if (( $(echo "$energy_total < 0" | bc -l) )); then energy_total=0; fi
    energy_total=$(printf "%.2f" "${energy_total}")

    local power_avg=$(echo "${power_avg_raw} - ${BASELINE_POWER_W}" | bc -l)
    if (( $(echo "$power_avg < 0" | bc -l) )); then power_avg=0; fi
    power_avg=$(printf "%.2f" "${power_avg}")

    # Estrai metriche CPU/RAM
    local avg_stats=$(calculate_stats_avg "${stats_file}")
    local peak_stats=$(calculate_stats_peak "${stats_file}")

    local cpu_avg=$(echo "${avg_stats}" | cut -d',' -f1)
    local mem_avg=$(echo "${avg_stats}" | cut -d',' -f2)
    local cpu_peak=$(echo "${peak_stats}" | cut -d',' -f1)
    local mem_peak=$(echo "${peak_stats}" | cut -d',' -f2)

    # Estrai statistiche load test
    local requests_per_sec=$(grep "Requests per second" "${load_file}" | awk '{print $4}')
    local time_per_request=$(grep "Time per request" "${load_file}" | head -1 | awk '{print $4}')

    log_success "Load test completato"
    log "Energia totale: ${energy_total} J, potenza media: ${power_avg} W, potenza picco: ${power_peak} W"
    log "CPU media: ${cpu_avg}%, peak: ${cpu_peak}%"
    log "RAM media: ${mem_avg} MB, peak: ${mem_peak} MB"
    log "Requests/sec: ${requests_per_sec}"

    # Cleanup
    cleanup_container "${container_name}"

    echo "" | tee -a "${RESULTS_FILE}"
    echo "Configuration: ${config}" | tee -a "${RESULTS_FILE}"
    echo "Test: Load" | tee -a "${RESULTS_FILE}"
    echo "Duration: ${LOAD_TEST_DURATION} s" | tee -a "${RESULTS_FILE}"
    echo "Load Energy Total: ${energy_total} J" | tee -a "${RESULTS_FILE}"
    echo "Load Power Average: ${power_avg} W" | tee -a "${RESULTS_FILE}"
    echo "Load Power Peak: ${power_peak} W" | tee -a "${RESULTS_FILE}"
    echo "CPU Average: ${cpu_avg}%, Peak: ${cpu_peak}%" | tee -a "${RESULTS_FILE}"
    echo "Memory Average: ${mem_avg} MB, Peak: ${mem_peak} MB" | tee -a "${RESULTS_FILE}"
    echo "Requests/sec: ${requests_per_sec}" | tee -a "${RESULTS_FILE}"
    echo "Time/request: ${time_per_request} ms" | tee -a "${RESULTS_FILE}"
    echo "" | tee -a "${RESULTS_FILE}"

    # Nel CSV: LoadAvgEnergy_J è l'energia totale, LoadPeakEnergy_J è la potenza di picco
    echo "${config},Load,-,-,-,-,-,-,${energy_total},${power_peak},${mem_avg},${mem_peak},${cpu_avg}" >> "${CSV_FILE}"
}

# =================================================================
# MAIN EXECUTION
# =================================================================

main() {
    log_section "Inizio Benchmark Suite"

    log "Risultati salvati in: ${RESULTS_DIR}"
    echo ""

    # Verifica dipendenze
    check_dependencies

    # Misura baseline energetica
    measure_baseline

    # Avvia database PostgreSQL
    start_postgres || {
        log_error "Impossibile avviare PostgreSQL"
        exit 1
    }

    # Loop su tutte le configurazioni
    for config in "${CONFIGS[@]}"; do
        log_section "CONFIGURAZIONE: ${config}"

        # Test 1a: Prima build
        test_build "${config}" false

        # Test 1b: Rebuild (simula modifica codice e aggiunta dipendenza)
        test_build "${config}" true

        # Test 2: Startup
        test_startup "${config}"

        # Test 3: Idle
        test_idle "${config}"

        # Test 4: Load
        test_load "${config}"

        log_success "Completati tutti i test per ${config}"
        echo ""
    done

    # Riepilogo finale
    log_section "BENCHMARK COMPLETATO"

    log_success "Risultati salvati in:"
    log "  - ${RESULTS_DIR}/"
    log ""
    log "File principali:"
    log "  - results.txt - Report completo"
    log "  - results.csv - Dati CSV"
    log "  - README.md - Guida ai risultati"

    echo ""
    log "Per visualizzare un riepilogo:"
    log "  cat ${RESULTS_DIR}/results.txt"
    log ""
    log "Per analisi CSV:"
    log "  column -t -s',' ${RESULTS_DIR}/results.csv | less -S"
    log ""
    log "Per analisi comparativa:"
    log "  ./analyze-results.py ${RESULTS_DIR}/results.csv"
}

# Esegui main
main "$@"
