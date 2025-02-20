#!/bin/bash

###############################################################################
# Setup Ambiente Desenvolvimento Kubernetes/Go
#
# Este script automatiza a configuração de um ambiente completo para
# desenvolvimento de operadores Kubernetes, incluindo:
#
# Componentes:
# - Go: Linguagem e toolchain
# - Docker: Container runtime
# - Kind: Cluster Kubernetes local
# - Registry Local: Para imagens de desenvolvimento 
# - Kubebuilder: Framework para operadores
# - Kustomize: Gerenciamento de configurações Kubernetes
# - Tilt: Hot reload e desenvolvimento
#
# Funcionalidades:
# 1. Instalação e validação de dependências
# 2. Configuração de registry local integrado ao Kind
# 3. Setup de cluster de desenvolvimento
# 4. Configuração de ambiente Go
#
# Uso:
#   ./setup-ambiente.sh
#
# Requisitos:
# - Sudo para algumas operações
# - Ubuntu/Debian
# - Suporte a bash/zsh
###############################################################################

set -euo pipefail

# Cores para logging
readonly VERMELHO='\033[0;31m'
readonly VERDE='\033[0;32m'
readonly AMARELO='\033[1;33m'
readonly AZUL='\033[0;34m'
readonly NC='\033[0m'

# Configurações do ambiente
readonly REG_NAME='kind-registry'
readonly REG_PORT='5001'
readonly CLUSTER_NAME='k8s-operators-lab'

# Logger com níveis e timestamps
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

# Valida existência de comando
comando_existe() {
    command -v "$1" >/dev/null 2>&1
}

# Verifica se porta está em uso
verificar_porta() {
    local porta=$1
    if lsof -i ":$porta" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Handler de erros com linha
tratar_erro() {
    log "ERRO" "Ocorreu um erro na linha $1"
    exit 1
}

trap 'tratar_erro $LINENO' ERR

# Limpa e remove registry existente
limpar_registry() {
    log "INFO" "Verificando registry existente..."

    if docker ps -a --format '{{.Names}}' | grep -q "^${REG_NAME}$"; then
        log "INFO" "Registry encontrado, removendo..."
        if docker rm -f "${REG_NAME}" >/dev/null 2>&1; then
            log "SUCESSO" "Registry removido"
        else
            log "ERRO" "Falha ao remover registry"
            exit 1
        fi
    fi

    if verificar_porta "${REG_PORT}"; then
        log "ERRO" "Porta ${REG_PORT} em uso"
        log "INFO" "Use 'sudo lsof -i :${REG_PORT}' para verificar"
        exit 1
    fi
}

# Configura novo registry local
configurar_registry() {
    log "INFO" "Configurando Registry Local..."

    limpar_registry

    if docker run -d --restart=always -p "127.0.0.1:${REG_PORT}:5000" --network bridge --name "${REG_NAME}" registry:2; then
        log "SUCESSO" "Registry local criado"
        sleep 3
    else
        log "ERRO" "Falha ao criar registry"
        exit 1
    fi
}

# Cria cluster Kind com suporte a registry
criar_cluster() {
    log "INFO" "Criando cluster Kind..."

    if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
        log "INFO" "Removendo cluster existente..."
        kind delete cluster --name "$CLUSTER_NAME"
    fi

    cat <<EOF | kind create cluster --name "$CLUSTER_NAME" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry]
    config_path = "/etc/containerd/certs.d"
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30080
    hostPort: 8080
    protocol: TCP
  - containerPort: 30443
    hostPort: 8443 
    protocol: TCP
EOF
}

# Configura registry nos nós do cluster
configurar_registry_nodes() {
    REGISTRY_DIR="/etc/containerd/certs.d/localhost:${REG_PORT}"
    for node in $(kind get nodes --name "$CLUSTER_NAME"); do
        log "INFO" "Configurando nó: $node"
        docker exec "${node}" mkdir -p "${REGISTRY_DIR}"
        cat <<EOF | docker exec -i "${node}" cp /dev/stdin "${REGISTRY_DIR}/hosts.toml"
[host."http://${REG_NAME}:5000"]
  capabilities = ["pull", "resolve"]
  skip_verify = true
EOF
    done

    if [ "$(docker inspect -f='{{json .NetworkSettings.Networks.kind}}' "${REG_NAME}")" = 'null' ]; then
        if docker network connect "kind" "${REG_NAME}"; then
            log "SUCESSO" "Registry conectado à rede Kind"
        else
            log "ERRO" "Falha ao conectar registry"
            exit 1
        fi
    fi
}

# Instala Go mais recente
instalar_go() {
    if ! comando_existe go; then
        log "INFO" "Instalando Go..."
        GO_LATEST=$(curl -s https://go.dev/VERSION?m=text)
        GO_ARCHIVE="${GO_LATEST}.linux-amd64.tar.gz"
        if wget "https://go.dev/dl/${GO_ARCHIVE}" &&
            sudo rm -rf /usr/local/go &&
            sudo tar -C /usr/local -xzf "$GO_ARCHIVE"; then
            rm "$GO_ARCHIVE"
            log "SUCESSO" "Go instalado"

            if [ -n "$PROFILE_FILE" ]; then
                {
                    echo 'export PATH=$PATH:/usr/local/go/bin'
                    echo 'export GOPATH=$HOME/go'
                    echo 'export PATH=$PATH:$GOPATH/bin'
                } >>"$PROFILE_FILE"
                log "SUCESSO" "Ambiente Go configurado em $PROFILE_FILE"
            fi
        else
            log "ERRO" "Falha ao instalar Go"
            exit 1
        fi
    fi
}

# Instala Docker mais recente
instalar_docker() {
    if ! comando_existe docker; then
        log "INFO" "Instalando Docker..."
        if sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release &&
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg &&
            echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" |
            sudo tee /etc/apt/sources.list.d/docker.list >/dev/null &&
            sudo apt-get update -y &&
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io; then
            sudo usermod -aG docker "$USER"
            log "SUCESSO" "Docker instalado"
            log "AVISO" "Faça logout e login para aplicar grupo Docker"
        else
            log "ERRO" "Falha ao instalar Docker"
            exit 1
        fi
    fi
}

# Instala Kind via Go
instalar_kind() {
    if ! comando_existe kind; then
        log "INFO" "Instalando Kind..."
        if GO111MODULE="on" go install sigs.k8s.io/kind@latest; then
            log "SUCESSO" "Kind instalado"
        else
            log "ERRO" "Falha ao instalar Kind"
            exit 1
        fi
    fi
}

# Instala kubectl mais recente
instalar_kubectl() {
    if ! comando_existe kubectl; then
        log "INFO" "Instalando kubectl..."
        if curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" &&
            sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl; then
            rm kubectl
            log "SUCESSO" "kubectl instalado"
        else
            log "ERRO" "Falha ao instalar kubectl"
            exit 1
        fi
    fi
}

# Instala Kubebuilder mais recente
instalar_kubebuilder() {
    if ! comando_existe kubebuilder; then
        log "INFO" "Instalando Kubebuilder..."
        if curl -L -o kubebuilder "https://go.kubebuilder.io/dl/latest/$(go env GOOS)/$(go env GOARCH)" &&
            chmod +x kubebuilder &&
            sudo mv kubebuilder /usr/local/bin/; then
            log "SUCESSO" "Kubebuilder instalado"
        else
            log "ERRO" "Falha ao instalar Kubebuilder"
            exit 1
        fi
    fi
}

# Instala Kustomize mais recente
instalar_kustomize() {
    if ! comando_existe kustomize; then
        log "INFO" "Instalando Kustomize..."
        # Obtém a versão mais recente do Kustomize
        KUSTOMIZE_VERSION=$(curl -s https://api.github.com/repos/kubernetes-sigs/kustomize/releases/latest | jq -r .tag_name)
        VERSION_NUMBER=${KUSTOMIZE_VERSION#kustomize/}
        
        if curl -L -o kustomize.tar.gz "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${VERSION_NUMBER}/kustomize_${VERSION_NUMBER}_linux_amd64.tar.gz" &&
            tar xzf kustomize.tar.gz &&
            chmod +x kustomize &&
            sudo mv kustomize /usr/local/bin/; then
            rm kustomize.tar.gz
            log "SUCESSO" "Kustomize instalado"
        else
            log "ERRO" "Falha ao instalar Kustomize"
            exit 1
        fi
    fi
}
# Instala Tilt mais recente
instalar_tilt() {
    if ! comando_existe tilt; then
        log "INFO" "Instalando Tilt..."
        if curl -fsSL https://raw.githubusercontent.com/tilt-dev/tilt/master/scripts/install.sh | bash; then
            log "SUCESSO" "Tilt instalado"
        else
            log "ERRO" "Falha ao instalar Tilt"
            exit 1
        fi
    fi
}

# Lista versões instaladas
verificar_versoes() {
    log "INFO" "Verificando instalações..."
    {
        echo "Go: $(go version)"
        echo "Docker: $(docker --version)"
        echo "Kind: $(kind version)"
        echo "kubectl: $(kubectl version --client)"
        echo "Kubebuilder: $(kubebuilder version)"
        echo "Kustomize: $(kustomize version --short)"
        echo "Tilt: $(tilt version)"
    } | while IFS= read -r linha; do
        log "SUCESSO" "$linha"
    done
}

###############################################################################
# Início da Execução
###############################################################################

log "INFO" "Iniciando setup do ambiente..."

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

# Detecta shell e configura perfil
USER_SHELL=$(basename "$SHELL")
PROFILE_FILE=""
case "$USER_SHELL" in
bash) PROFILE_FILE="$HOME/.bashrc" ;;
zsh) PROFILE_FILE="$HOME/.zshrc" ;;
*) log "AVISO" "Shell não suportado: $USER_SHELL" ;;
esac

# Instalação das ferramentas
instalar_go
instalar_docker
instalar_kind
instalar_kubectl
instalar_kubebuilder
instalar_kustomize
instalar_tilt

# Setup do ambiente Kind
configurar_registry
criar_cluster
configurar_registry_nodes

# ConfigMap para registry local
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

verificar_versoes

log "SUCESSO" "Ambiente configurado com sucesso!"
log "AVISO" "Execute 'source $PROFILE_FILE' para aplicar as alterações"