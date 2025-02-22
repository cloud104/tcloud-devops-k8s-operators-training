#!/bin/bash

###############################################################################
# Setup Cluster Kind com Registry Local
###############################################################################

set -euo pipefail

# Configurações
readonly REG_NAME='kind-registry'
readonly REG_PORT='5001'
readonly CLUSTER_NAME='k8s-operators-lab'

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

configurar_registry() {
    log "INFO" "Configurando registry local..."
    
    # Remove registry existente se houver
    docker container rm -f "${REG_NAME}" 2>/dev/null || true
    
    # Cria registry local
    docker run -d --restart=always -p "127.0.0.1:${REG_PORT}:5000" --name "${REG_NAME}" registry:2
    
    log "SUCESSO" "Registry local configurado"
}

criar_cluster() {
    log "INFO" "Criando cluster Kind..."
    
    cat <<EOF | kind create cluster --name "${CLUSTER_NAME}" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:${REG_PORT}"]
    endpoint = ["http://${REG_NAME}:5000"]
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30000
    hostPort: 30000
    protocol: TCP
EOF
    
    log "SUCESSO" "Cluster Kind criado"
}

configurar_registry_nodes() {
    log "INFO" "Conectando registry ao cluster..."
    
    # Conecta o registry à rede do Kind
    docker network connect "kind" "${REG_NAME}" || true
    
    # Configura os nodes para usar o registry local
    for node in $(kind get nodes --name "${CLUSTER_NAME}"); do
        kubectl annotate node "${node}" "kind.x-k8s.io/registry=localhost:${REG_PORT}" || true
    done
    
    log "SUCESSO" "Registry conectado ao cluster"
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

configurar_registry
criar_cluster
configurar_registry_nodes

# Configura registry local no cluster
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${REG_PORT}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF

log "SUCESSO" "Ambiente Kind configurado com sucesso!"
log "INFO" "Use 'docker push localhost:${REG_PORT}/sua-imagem' para publicar imagens"