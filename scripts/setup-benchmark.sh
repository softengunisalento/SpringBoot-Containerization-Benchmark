#!/bin/bash
# =================================================================
# Script di Setup per Benchmark Environment
# Installa e configura le dipendenze necessarie
# =================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}  Benchmark Setup${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""

# Rileva distribuzione
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
else
    echo -e "${RED}Impossibile rilevare la distribuzione${NC}"
    exit 1
fi

echo -e "${YELLOW}Distribuzione rilevata: ${DISTRO}${NC}"
echo ""

# Installa dipendenze base
echo -e "${YELLOW}[1/4] Installazione dipendenze base...${NC}"

case $DISTRO in
    ubuntu|debian)
        sudo apt-get update
        sudo apt-get install -y \
            curl \
            jq \
            bc \
            apache2-utils \
            linux-tools-common \
            linux-tools-generic \
            linux-tools-$(uname -r) 2>/dev/null || \
        sudo apt-get install -y linux-tools-$(uname -r | sed 's/-generic//')
        ;;
    fedora|rhel|centos)
        sudo dnf install -y \
            curl \
            jq \
            bc \
            httpd-tools \
            perf
        ;;
    arch)
        sudo pacman -S --noconfirm \
            curl \
            jq \
            bc \
            apache \
            perf
        ;;
    *)
        echo -e "${RED}Distribuzione non supportata. Installa manualmente:${NC}"
        echo "  - curl, jq, bc, apache2-utils (ab), perf"
        exit 1
        ;;
esac

echo -e "${GREEN}✓ Dipendenze base installate${NC}"
echo ""

# Configura perf
echo -e "${YELLOW}[2/4] Configurazione permessi perf...${NC}"

# Verifica supporto energy counters
if ! ls /sys/devices/power/events/energy-* &> /dev/null; then
    echo -e "${RED}ATTENZIONE: Il sistema non supporta energy counters di perf${NC}"
    echo "I test di energia potrebbero non funzionare correttamente."
    echo "Verifica che:"
    echo "  - Il processore supporti RAPL (Intel Sandy Bridge+ o AMD Zen+)"
    echo "  - I moduli kernel necessari siano caricati"
    echo ""
fi

# Imposta paranoid level
echo -e "Impostazione kernel.perf_event_paranoid..."
sudo sysctl -w kernel.perf_event_paranoid=-1

# Rendi permanente
if ! grep -q "kernel.perf_event_paranoid" /etc/sysctl.conf; then
    echo "kernel.perf_event_paranoid = -1" | sudo tee -a /etc/sysctl.conf
fi

# Verifica accesso ai contatori energetici
if [ -d /sys/devices/power ]; then
    sudo chmod -R a+r /sys/devices/power/events/ 2>/dev/null || true
fi

echo -e "${GREEN}✓ Permessi perf configurati${NC}"
echo ""

# Verifica Docker
echo -e "${YELLOW}[3/4] Verifica Docker...${NC}"

if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker non trovato!${NC}"
    echo "Installa Docker seguendo: https://docs.docker.com/engine/install/"
    exit 1
fi

# Verifica BuildKit
if ! docker buildx version &> /dev/null; then
    echo -e "${YELLOW}BuildKit non disponibile, installo...${NC}"
    docker buildx create --use
fi

echo -e "${GREEN}✓ Docker configurato${NC}"
echo ""

# Test finale
echo -e "${YELLOW}[4/4] Test configurazione...${NC}"

echo -n "  - Docker: "
docker run --rm hello-world &> /dev/null && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"

echo -n "  - Curl: "
curl -s https://www.google.com &> /dev/null && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"

echo -n "  - Apache Bench: "
ab -V &> /dev/null && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"

echo -n "  - jq: "
echo '{"test": true}' | jq .test &> /dev/null && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"

echo -n "  - perf: "
if perf stat -e power/energy-pkg/ sleep 0.1 &> /dev/null; then
    echo -e "${GREEN}✓ (con energy counters)${NC}"
elif perf stat sleep 0.1 &> /dev/null; then
    echo -e "${YELLOW}⚠ (senza energy counters)${NC}"
    echo -e "${YELLOW}    Le misurazioni di energia potrebbero non funzionare${NC}"
else
    echo -e "${RED}✗${NC}"
fi

echo ""
echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}  Setup completato!${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""
echo "Puoi ora eseguire il benchmark con:"
echo -e "  ${YELLOW}./run-benchmark.sh${NC}"
echo ""
echo "Note:"
echo "  - I risultati verranno salvati in ./benchmark-results/"
echo "  - Ogni test può richiedere diversi minuti"
echo "  - Chiudi altre applicazioni per risultati accurati"
echo ""

