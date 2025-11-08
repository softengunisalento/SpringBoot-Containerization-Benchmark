#!/bin/bash
# =================================================================
# Verifica Prerequisiti Benchmark
# Controlla che l'ambiente sia pronto per i test
# =================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}  Verifica Prerequisiti Benchmark${NC}"
echo -e "${BLUE}=====================================${NC}"
echo ""

# Funzioni di check
check_ok() {
    echo -e "  ${GREEN}✓${NC} $1"
}

check_warning() {
    echo -e "  ${YELLOW}⚠${NC} $1"
    WARNINGS=$((WARNINGS + 1))
}

check_error() {
    echo -e "  ${RED}✗${NC} $1"
    ERRORS=$((ERRORS + 1))
}

# 1. Sistema Operativo
echo -e "${YELLOW}[1/10] Sistema Operativo${NC}"
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    check_ok "Linux rilevato: $(uname -r)"
else
    check_error "Sistema non Linux. I test richiedono Linux."
fi
echo ""

# 2. Docker
echo -e "${YELLOW}[2/10] Docker${NC}"
if command -v docker &> /dev/null; then
    VERSION=$(docker --version)
    check_ok "Docker installato: $VERSION"

    if docker ps &> /dev/null; then
        check_ok "Docker daemon attivo"
    else
        check_error "Docker daemon non attivo o permessi insufficienti"
        echo "       Prova: sudo usermod -aG docker \$USER && newgrp docker"
    fi
else
    check_error "Docker non trovato"
    echo "       Installa da: https://docs.docker.com/engine/install/"
fi
echo ""

# 3. BuildKit
echo -e "${YELLOW}[3/10] Docker BuildKit${NC}"
if docker buildx version &> /dev/null; then
    check_ok "BuildKit disponibile"
else
    check_warning "BuildKit non disponibile (opzionale per layered)"
    echo "       Abilita con: docker buildx create --use"
fi
echo ""

# 4. perf
echo -e "${YELLOW}[4/10] perf${NC}"
if command -v perf &> /dev/null; then
    check_ok "perf installato"

    # Test permessi
    if perf stat sleep 0.1 &> /dev/null; then
        check_ok "perf funzionante"

        # Test energy counters
        if perf stat -e power/energy-pkg/ sleep 0.1 &> /dev/null; then
            check_ok "Energy counters disponibili"
        else
            check_warning "Energy counters non accessibili"
            echo "       Esegui: sudo sysctl -w kernel.perf_event_paranoid=-1"
        fi
    else
        check_error "perf: permessi insufficienti"
        echo "       Esegui: sudo sysctl -w kernel.perf_event_paranoid=-1"
    fi
else
    check_error "perf non trovato"
    echo "       Installa: sudo apt install linux-tools-\$(uname -r)"
fi
echo ""

# 5. RAPL Support
echo -e "${YELLOW}[5/10] RAPL (Energy Monitoring)${NC}"
if ls /sys/devices/power/events/energy-* &> /dev/null; then
    COUNT=$(ls /sys/devices/power/events/energy-* 2>/dev/null | wc -l)
    check_ok "RAPL supportato (${COUNT} contatori)"
else
    check_warning "RAPL non supportato dal processore"
    echo "       Le misurazioni energetiche potrebbero non funzionare"
    echo "       CPU supportate: Intel Sandy Bridge+ o AMD Zen+"
fi
echo ""

# 6. Apache Bench
echo -e "${YELLOW}[6/10] Apache Bench${NC}"
if command -v ab &> /dev/null; then
    VERSION=$(ab -V 2>&1 | head -1)
    check_ok "ab installato: $VERSION"
else
    check_error "Apache Bench (ab) non trovato"
    echo "       Installa: sudo apt install apache2-utils"
fi
echo ""

# 7. Utility
echo -e "${YELLOW}[7/10] Utility Richieste${NC}"
MISSING=()

command -v curl &> /dev/null || MISSING+=("curl")
command -v jq &> /dev/null || MISSING+=("jq")
command -v bc &> /dev/null || MISSING+=("bc")

if [ ${#MISSING[@]} -eq 0 ]; then
    check_ok "Tutte le utility presenti (curl, jq, bc)"
else
    check_error "Utility mancanti: ${MISSING[*]}"
    echo "       Installa: sudo apt install ${MISSING[*]}"
fi
echo ""

# 8. Spazio Disco
echo -e "${YELLOW}[8/10] Spazio Disco${NC}"
AVAILABLE=$(df -BG . | tail -1 | awk '{print $4}' | tr -d 'G')
if [ "$AVAILABLE" -gt 10 ]; then
    check_ok "Spazio disponibile: ${AVAILABLE}GB (sufficiente)"
elif [ "$AVAILABLE" -gt 5 ]; then
    check_warning "Spazio disponibile: ${AVAILABLE}GB (limite)"
else
    check_error "Spazio disponibile: ${AVAILABLE}GB (insufficiente, minimo 5GB)"
fi
echo ""

# 9. Memoria
echo -e "${YELLOW}[9/10] Memoria RAM${NC}"
TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
if [ "$TOTAL_MEM" -gt 8 ]; then
    check_ok "RAM totale: ${TOTAL_MEM}GB (ottima)"
elif [ "$TOTAL_MEM" -gt 4 ]; then
    check_ok "RAM totale: ${TOTAL_MEM}GB (sufficiente)"
else
    check_warning "RAM totale: ${TOTAL_MEM}GB (potrebbe essere insufficiente per native build)"
fi
echo ""

# 10. Porte
echo -e "${YELLOW}[10/10] Disponibilità Porte${NC}"
if lsof -i :8080 &> /dev/null || netstat -tuln 2>/dev/null | grep -q ":8080 "; then
    check_warning "Porta 8080 in uso"
    echo "       Il processo verrà terminato o usa un'altra porta"
else
    check_ok "Porta 8080 disponibile"
fi
echo ""

# Riepilogo
echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}  Riepilogo${NC}"
echo -e "${BLUE}=====================================${NC}"
echo ""

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ Sistema pronto per i benchmark!${NC}"
    echo ""
    echo "Puoi procedere con:"
    echo -e "  ${YELLOW}./run-benchmark.sh${NC}"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠ Sistema pronto con alcuni avvisi (${WARNINGS})${NC}"
    echo ""
    echo "I test possono funzionare ma alcuni dati potrebbero mancare."
    echo ""
    echo "Per procedere comunque:"
    echo -e "  ${YELLOW}./run-benchmark.sh${NC}"
    exit 0
else
    echo -e "${RED}✗ Trovati ${ERRORS} errori e ${WARNINGS} avvisi${NC}"
    echo ""
    echo "Risolvi gli errori prima di procedere."
    echo ""
    echo "Per installare dipendenze automaticamente:"
    echo -e "  ${YELLOW}./setup-benchmark.sh${NC}"
    exit 1
fi

