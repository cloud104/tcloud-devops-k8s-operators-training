#!/bin/bash

###############################################################################
# Setup Ferramentas Desenvolvimento Kubernetes/Go
###############################################################################

set -euo pipefail

# Versões pinadas: alterar aqui e conferir os docs e o scaffold juntos
readonly GO_VERSION='1.26.8'
readonly KIND_VERSION='0.33.0'
readonly KUBECTL_VERSION='1.37.0'
readonly KUBEBUILDER_VERSION='4.16.0'
readonly KUSTOMIZE_VERSION='5.8.1'
readonly TILT_VERSION='0.37.8'

# Destino dos binários; BIN_DIR permite instalar sem sudo
readonly BIN_DIR="${BIN_DIR:-/usr/local/bin}"

# Cores para logging
readonly VERMELHO='\033[0;31m'
readonly VERDE='\033[0;32m'
readonly AMARELO='\033[1;33m'
readonly AZUL='\033[0;34m'
readonly NC='\033[0m'

# Funções de utilidade
log() {
    local nivel=$1
    local msg=$2
    local cor=""
    case $nivel in
        "INFO") cor=$AZUL ;;
        "SUCESSO") cor=$VERDE ;;
        "AVISO") cor=$AMARELO ;;
        "ERRO") cor=$VERMELHO ;;
    esac
    echo -e "${cor}[$(date +'%Y-%m-%d %H:%M:%S')] [$nivel]${NC} $msg"
}

comando_existe() {
    command -v "$1" >/dev/null 2>&1
}

# Instala um binário em BIN_DIR, com sudo só se o diretório não for gravável
instalar_binario() {
    mkdir -p "$BIN_DIR" 2>/dev/null || true
    if [ -w "$BIN_DIR" ]; then
        install -m 0755 "$1" "$BIN_DIR/$2"
    else
        sudo install -m 0755 "$1" "$BIN_DIR/$2"
    fi
    rm -f "$1"
}

# Avisa quando a ferramenta já instalada difere da versão pinada
conferir_versao() {
    local nome=$1 esperada=$2 atual=$3
    if [[ "$atual" == *"$esperada"* ]]; then
        log "INFO" "$nome $esperada já está instalado"
    else
        log "AVISO" "$nome instalado difere do pinado ($esperada): $atual"
    fi
}

# Funções de instalação
instalar_go() {
    if comando_existe go; then
        conferir_versao "Go" "go$GO_VERSION" "$(go version)"
        return
    fi
    log "INFO" "Instalando Go $GO_VERSION..."
    curl -fsSLo go.tar.gz "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz"
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf go.tar.gz
    rm go.tar.gz
    echo 'export PATH=$PATH:/usr/local/go/bin' >> "$PROFILE_FILE"
    echo 'export PATH=$PATH:$HOME/go/bin' >> "$PROFILE_FILE"
    export PATH="$PATH:/usr/local/go/bin"
    log "SUCESSO" "Go instalado"
}

instalar_docker() {
    if ! comando_existe docker; then
        log "INFO" "Instalando Docker..."
        sudo apt-get install -y ca-certificates gnupg
        sudo install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg
        echo \
            "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
            "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
            sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        sudo usermod -aG docker "$USER"
        log "SUCESSO" "Docker instalado"
    else
        log "INFO" "Docker já está instalado"
    fi
}

instalar_kind() {
    if comando_existe kind; then
        conferir_versao "Kind" "v$KIND_VERSION" "$(kind version)"
        return
    fi
    log "INFO" "Instalando Kind $KIND_VERSION..."
    curl -fsSLo kind "https://kind.sigs.k8s.io/dl/v${KIND_VERSION}/kind-linux-amd64"
    instalar_binario kind kind
    log "SUCESSO" "Kind instalado"
}

instalar_kubectl() {
    if comando_existe kubectl; then
        conferir_versao "kubectl" "v$KUBECTL_VERSION" "$(kubectl version --client 2>/dev/null | head -1)"
        return
    fi
    log "INFO" "Instalando kubectl $KUBECTL_VERSION..."
    curl -fsSLo kubectl "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
    instalar_binario kubectl kubectl
    log "SUCESSO" "kubectl instalado"
}

instalar_kubebuilder() {
    if comando_existe kubebuilder; then
        conferir_versao "Kubebuilder" "$KUBEBUILDER_VERSION" "$(kubebuilder version | head -1)"
        return
    fi
    log "INFO" "Instalando Kubebuilder $KUBEBUILDER_VERSION..."
    curl -fsSLo kubebuilder "https://github.com/kubernetes-sigs/kubebuilder/releases/download/v${KUBEBUILDER_VERSION}/kubebuilder_linux_amd64"
    instalar_binario kubebuilder kubebuilder
    log "SUCESSO" "Kubebuilder instalado"
}

instalar_kustomize() {
    if comando_existe kustomize; then
        conferir_versao "Kustomize" "$KUSTOMIZE_VERSION" "$(kustomize version)"
        return
    fi
    log "INFO" "Instalando Kustomize $KUSTOMIZE_VERSION..."
    curl -fsSL "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz" | tar -xz kustomize
    instalar_binario kustomize kustomize
    log "SUCESSO" "Kustomize instalado"
}

instalar_tilt() {
    if comando_existe tilt; then
        conferir_versao "Tilt" "v$TILT_VERSION" "$(tilt version)"
        return
    fi
    log "INFO" "Instalando Tilt $TILT_VERSION..."
    curl -fsSL "https://github.com/tilt-dev/tilt/releases/download/v${TILT_VERSION}/tilt.${TILT_VERSION}.linux.x86_64.tar.gz" | tar -xz tilt
    instalar_binario tilt tilt
    log "SUCESSO" "Tilt instalado"
}

verificar_versoes() {
    log "INFO" "Verificando versões instaladas:"
    echo -e "\n${AZUL}=== Versões das Ferramentas Instaladas ===${NC}"
    echo -e "${VERDE}Go:${NC}          $(go version 2>/dev/null || echo 'não instalado')"
    echo -e "${VERDE}Docker:${NC}      $(docker --version 2>/dev/null || echo 'não instalado')"
    echo -e "${VERDE}Kind:${NC}        $(kind --version 2>/dev/null || echo 'não instalado')"
    echo -e "${VERDE}Kubectl:${NC}     $(kubectl version --client 2>/dev/null | grep -o 'Client Version:.*' || echo 'não instalado')"
    echo -e "${VERDE}Kubebuilder:${NC} $(kubebuilder version 2>/dev/null || echo 'não instalado')"
    echo -e "${VERDE}Kustomize:${NC}   $(kustomize version 2>/dev/null || echo 'não instalado')"
    echo -e "${VERDE}Tilt:${NC}        $(tilt version 2>/dev/null || echo 'não instalado')"
    echo
}

###############################################################################
# Início da Execução
###############################################################################

log "INFO" "Iniciando instalação das ferramentas..."

# Detecta shell e configura perfil
USER_SHELL=$(basename "$SHELL")
PROFILE_FILE=""
case "$USER_SHELL" in
    bash) PROFILE_FILE="$HOME/.bashrc" ;;
    zsh) PROFILE_FILE="$HOME/.zshrc" ;;
    *) log "AVISO" "Shell não suportado: $USER_SHELL" ;;
esac

# Dependências básicas; SKIP_APT=1 pula quando já estão instaladas
if [ -z "${SKIP_APT:-}" ]; then
    log "INFO" "Instalando dependências básicas..."
    sudo apt-get update -y
    sudo apt-get install -y curl git make gcc
fi

# Instalação das ferramentas
instalar_go
instalar_docker
instalar_kind
instalar_kubectl
instalar_kubebuilder
instalar_kustomize
instalar_tilt

verificar_versoes

log "SUCESSO" "🎉 Instalação concluída com sucesso!"
echo -e "\n${AZUL}=== Próximos Passos ===${NC}"
echo -e "${VERDE}1.${NC} Execute o comando abaixo para aplicar as alterações no PATH:"
echo -e "   ${AMARELO}source $PROFILE_FILE${NC}"
echo -e "${VERDE}2.${NC} Verifique se você foi adicionado ao grupo 'docker':"
echo -e "   ${AMARELO}groups | grep docker${NC}"
echo -e "${VERDE}3.${NC} Caso não apareça o grupo 'docker', faça logout e login novamente"
echo -e "${VERDE}4.${NC} Para verificar a instalação, execute:"
echo -e "   ${AMARELO}scripts/setup-cluster.sh${NC}"
echo
log "INFO" "Para mais informações, consulte a documentação do projeto"
