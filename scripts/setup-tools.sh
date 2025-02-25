#!/bin/bash

###############################################################################
# Setup Ferramentas Desenvolvimento Kubernetes/Go
###############################################################################

set -euo pipefail

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

# Funções de instalação
instalar_go() {
    if ! comando_existe go; then
        log "INFO" "Instalando Go..."
        wget -q https://golang.org/dl/go1.21.6.linux-amd64.tar.gz
        sudo rm -rf /usr/local/go 
        sudo tar -C /usr/local -xzf go1.21.6.linux-amd64.tar.gz
        rm go1.21.6.linux-amd64.tar.gz
        echo 'export PATH=$PATH:/usr/local/go/bin' >> "$PROFILE_FILE"
        echo 'export PATH=$PATH:$(go env GOPATH)/bin' >> "$PROFILE_FILE"
        log "SUCESSO" "Go instalado"
    else
        log "INFO" "Go já está instalado"
    fi
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
    if ! comando_existe kind; then
        log "INFO" "Instalando Kind..."
        curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
        chmod +x ./kind
        sudo mv ./kind /usr/local/bin/kind
        log "SUCESSO" "Kind instalado"
    else
        log "INFO" "Kind já está instalado"
    fi
}

instalar_kubectl() {
    if ! comando_existe kubectl; then
        log "INFO" "Instalando kubectl..."
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        chmod +x kubectl
        sudo mv kubectl /usr/local/bin/
        log "SUCESSO" "kubectl instalado"
    else
        log "INFO" "kubectl já está instalado"
    fi
}

instalar_kubebuilder() {
    if ! comando_existe kubebuilder; then
        log "INFO" "Instalando Kubebuilder..."
        curl -L -o kubebuilder https://go.kubebuilder.io/dl/latest/$(go env GOOS)/$(go env GOARCH)
        chmod +x kubebuilder
        sudo mv kubebuilder /usr/local/bin/
        log "SUCESSO" "Kubebuilder instalado"
    else
        log "INFO" "Kubebuilder já está instalado"
    fi
}

instalar_kustomize() {
    if ! comando_existe kustomize; then
        log "INFO" "Instalando Kustomize..."
        curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
        sudo mv kustomize /usr/local/bin/
        log "SUCESSO" "Kustomize instalado"
    else
        log "INFO" "Kustomize já está instalado"
    fi
}

instalar_tilt() {
    if ! comando_existe tilt; then
        log "INFO" "Instalando Tilt..."
        curl -fsSL https://raw.githubusercontent.com/tilt-dev/tilt/master/scripts/install.sh | bash
        log "SUCESSO" "Tilt instalado"
    else
        log "INFO" "Tilt já está instalado"
    fi
}

verificar_versoes() {
    log "INFO" "Verificando versões instaladas:"
    echo -e "\n${AZUL}=== Versões das Ferramentas Instaladas ===${NC}"
    echo -e "${VERDE}Go:${NC}          $(go version 2>/dev/null || echo 'não instalado')"
    echo -e "${VERDE}Docker:${NC}      $(docker --version 2>/dev/null || echo 'não instalado')"
    echo -e "${VERDE}Kind:${NC}        $(kind --version 2>/dev/null || echo 'não instalado')"
    echo -e "${VERDE}Kubectl:${NC}     $(kubectl version --client 2>/dev/null | grep -o 'GitVersion:.*' || echo 'não instalado')"
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

# Update do sistema
log "INFO" "Atualizando sistema..."
if sudo apt-get update -y && sudo apt-get upgrade -y; then
    log "SUCESSO" "Sistema atualizado"
else
    log "ERRO" "Falha ao atualizar sistema"
    exit 1
fi

# Dependências básicas
log "INFO" "Instalando dependências básicas..."
sudo apt-get install -y curl wget git make gcc

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
echo -e "   ${AMARELO}./setup-cluster.sh${NC}"
echo
log "INFO" "Para mais informações, consulte a documentação do projeto"