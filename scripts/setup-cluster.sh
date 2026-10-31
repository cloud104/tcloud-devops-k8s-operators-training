#!/bin/bash

###############################################################################
# Setup Cluster Kind do lab
###############################################################################

set -euo pipefail

# Configurações
readonly CLUSTER_NAME='k8s-operators-lab'
# Imagem default do kind 0.33.0: mesma versão, com digest
readonly NODE_IMAGE='kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5'

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

criar_cluster() {
    if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
        log "AVISO" "Cluster ${CLUSTER_NAME} já existe, nada a fazer"
        return
    fi

    log "INFO" "Criando cluster Kind..."

    cat <<EOF | kind create cluster --name "${CLUSTER_NAME}" --image "${NODE_IMAGE}" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30000
    hostPort: 30000
    protocol: TCP
EOF

    log "SUCESSO" "Cluster Kind criado"
}

###############################################################################
# Início da Execução
###############################################################################

log "INFO" "Iniciando setup do ambiente Kind..."

# Verifica dependências
for cmd in docker kind kubectl; do
    if ! comando_existe "$cmd"; then
        log "ERRO" "Comando $cmd não encontrado. Execute setup-tools.sh primeiro."
        exit 1
    fi
done

criar_cluster

log "SUCESSO" "Ambiente Kind configurado com sucesso!"
log "INFO" "- Cluster name: ${CLUSTER_NAME}"
log "INFO" "- Contexto: kind-${CLUSTER_NAME}"
log "INFO" "- NodePort disponível na porta 30000 (host) -> 30000 (container)"
log "INFO" "- O Tilt carrega as imagens direto no node (kind load), sem registry"
