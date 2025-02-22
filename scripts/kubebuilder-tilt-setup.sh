#!/bin/bash

###############################################################################
# Setup de Ambiente de Desenvolvimento para Operadores Kubernetes com Tilt
# 
# Este script configura um ambiente de desenvolvimento otimizado para 
# projetos Kubebuilder usando overlays Kustomize.
# 
# Funcionalidades:
# 1. Debug Remoto: Configuração do Delve para debug do operador
#    - Suporte para VSCode, GoLand e Helix
#    - Port-forward automático da porta 40000
#    - Delve em modo headless para debug remoto
#
# 2. Hot Reload: Atualização do código sem rebuild de imagem
#    - Live update via Tilt
#    - Recompilação automática do binário
#    - Sincronização eficiente de arquivos
#
# 3. Recursos Otimizados: 
#    - Ajuste de memória/CPU para desenvolvimento
#    - Remoção de health checks em dev
#    - Cache de dependências Go
#
# 4. Multi-stage Build:
#    - Dockerfile otimizado para produção (multi-stage)
#    - Imagem de desenvolvimento com ferramentas de debug
#    - Configuração de usuário não-root
#
# 5. Configuração Automática de IDE:
#    - VSCode: launch.json para debug remoto
#    - GoLand: Remote Debug configuration
#    - Helix: config.toml com setup de debug
#
# 6. Registry Efêmero:
#    - Integração com ttl.sh
#    - Imagens temporárias para CI/CD
#    - Expiração automática em 24h
#
# Estrutura de Arquivos:
# .
# ├── Dockerfile              # Multi-stage build para produção
# ├── config/                 # Configurações base do operator
# │   └── manager/           # Manifests do controller
# ├── tilt-dev/              # Overlay para desenvolvimento
# │   ├── kustomization.yaml # Customizações para desenvolvimento
# │   ├── manager_patch.yaml # Ajustes de recursos e debug
# │   └── tilt.docker        # Imagem de desenvolvimento com Delve
# └── [.vscode|.idea|~/.config/helix]/  # Configurações da IDE escolhida
#
# Pré-requisitos:
# - Projeto Kubebuilder existente
# - kubectl, tilt, go, kustomize
# - controller-gen, uuidgen
# - IDE (VSCode, GoLand ou Helix)
#
# Uso:
# 1. Execute o script na raiz do projeto Kubebuilder
# 2. Escolha sua IDE preferida para debug
# 3. Use 'tilt up' para iniciar o ambiente
# 4. Configure breakpoints e inicie o debug remoto
###############################################################################

# Definição de cores para logging
# Estas cores são usadas para melhorar a legibilidade do output
GREEN='\033[0;32m'  # Sucesso e conclusões
YELLOW='\033[1;33m' # Avisos e notas importantes
NC='\033[0m'        # Reset da cor

# Função para logging com timestamp
# Padroniza a saída de logs com formato consistente
# Uso: log "Mensagem aqui"
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Função para configurar o ambiente de debug na IDE escolhida
# Esta função:
# 1. Pergunta se o usuário quer configurar debug
# 2. Oferece menu de seleção de IDE
# 3. Configura os arquivos necessários para cada IDE
configure_ide() {
    local setup_debug
    local ide_choice
    
    # Prompt inicial para setup de debug
    read -p "Deseja configurar o debug na IDE? [S/n] " setup_debug
    setup_debug=${setup_debug:-S}
    
    if [[ ${setup_debug^^} == "S" ]]; then
        # Menu interativo para seleção da IDE
        echo -e "\nEscolha sua IDE:"
        echo "1 - VSCode (padrão)"
        echo "2 - GoLand"
        echo "3 - Helix"
        read -p "Opção [1]: " ide_choice
        ide_choice=${ide_choice:-1}
        
        case $ide_choice in
            1)
                # VSCode: Configuração via launch.json
                # Usa protocolo DAP (Debug Adapter Protocol) com Delve
                log "${GREEN}Configurando VSCode...${NC}"
                mkdir -p .vscode
                cat > .vscode/launch.json << 'EOL'
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "Attach to DLV-DAP",
            "type": "go",
            "request": "attach",
            "mode": "remote",
            "port": 40000
        }
    ]
}
EOL
                log "${GREEN}✓ Arquivo .vscode/launch.json criado${NC}"
                ;;
            2)
                # GoLand: Configuração via XML
                # Setup de debug remoto Go específico para GoLand
                log "${GREEN}Configurando GoLand...${NC}"
                mkdir -p .idea/runConfigurations
                cat > .idea/runConfigurations/Remote_Debug.xml << 'EOL'
<component name="ProjectRunConfigurationManager">
  <configuration default="false" name="Remote Debug" type="GoRemoteDebugConfigurationType" factoryName="Go Remote">
    <option name="host" value="localhost" />
    <option name="port" value="40000" />
    <option name="useAutoDetect" value="false" />
    <option name="goPath" value="$PROJECT_DIR$" />
    <option name="workingDir" value="$PROJECT_DIR$" />
    <method v="2" />
  </configuration>
</component>
EOL
                log "${GREEN}✓ Configuração do GoLand criada${NC}"
                ;;
            3)
                # Helix: Configuração via config.toml
                # Setup do editor e debug configs
                log "${GREEN}Configurando Helix...${NC}"
                mkdir -p ~/.config/helix
                
                # Cria ou atualiza configuração base do Helix
                if [ ! -f ~/.config/helix/config.toml ]; then
                    cat > ~/.config/helix/config.toml << 'EOL'
theme = "default"

[editor]
line-number = "relative"
mouse = false
bufferline = "multiple"

[keys]
normal = { space = { g = ":debug" } }
EOL
                fi

                # Adiciona configuração de debug se não existir
                if ! grep -q "\[debug.configurations.go\]" ~/.config/helix/config.toml; then
                    cat >> ~/.config/helix/config.toml << 'EOL'

[debug.configurations.go]
name = "Remote Go Debugger"
type = "dlv"
request = "attach"
mode = "remote"
port = 40000
EOL
                fi
                log "${GREEN}✓ Configuração do Helix criada em ~/.config/helix/config.toml${NC}"
                log "${YELLOW}Nota: Para usar o debug no Helix:${NC}"
                log "1. Pressione <space>-g para abrir o menu de debug"
                log "2. Use 'b' para adicionar breakpoints"
                log "3. Selecione 'attach' e insira o PID do processo"
                ;;
            *)
                log "${YELLOW}Opção inválida, pulando configuração de IDE${NC}"
                ;;
        esac
    fi
}

# Validação de dependências necessárias
# Verifica se todas as ferramentas necessárias estão instaladas
# Fornece instruções de instalação se alguma estiver faltando
check_dependencies() {
    local deps=(kubectl tilt go kustomize controller-gen uuidgen)
    # Adiciona helix à lista se foi selecionado
    if [ "$ide_choice" = "3" ]; then
        deps+=(hx)
    fi
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            log "${YELLOW}Erro: $dep não encontrado${NC}"
            echo "Instale todas as dependências antes de continuar:"
            echo "- kubectl: https://kubernetes.io/docs/tasks/tools/"
            echo "- tilt: https://docs.tilt.dev/install.html"
            echo "- go: https://golang.org/doc/install"
            echo "- kustomize: https://kubectl.docs.kubernetes.io/installation/kustomize/"
            echo "- controller-gen: go install sigs.k8s.io/controller-tools/cmd/controller-gen@latest"
            echo "- uuidgen: apt-get install uuid-runtime"
            if [ "$dep" = "hx" ]; then
                echo "- helix: https://docs.helix-editor.com/install.html"
            fi
            exit 1
        fi
    done
}

# Início da execução do script
log "${GREEN}Iniciando configuração do ambiente Tilt...${NC}"
check_dependencies

# Validação do projeto Kubebuilder
# Verifica se estamos na raiz de um projeto válido
if [ ! -f "PROJECT" ]; then
    log "${YELLOW}Erro: Execute este script na raiz do projeto Kubebuilder${NC}"
    echo "Um projeto Kubebuilder deve conter o arquivo PROJECT na raiz."
    echo "Para criar um novo projeto:"
    echo "  kubebuilder init --domain example.com --repo example.com/project"
    exit 1
fi

# Extração do nome do projeto do arquivo PROJECT
log "Verificando arquivo PROJECT..."
CONTROLLER_NAME=$(grep "projectName:" PROJECT | awk '{print $2}')
if [ -z "$CONTROLLER_NAME" ]; then
    log "${YELLOW}Erro: projectName não encontrado em PROJECT${NC}"
    exit 1
fi
log "Nome do projeto encontrado: ${CONTROLLER_NAME}"

# Geração de UUID para o registry ttl.sh
# Usado para criar um namespace único no registry efêmero
UUID=$(uuidgen | tr '[:upper:]' '[:lower:]')
REGISTRY="ttl.sh/${CONTROLLER_NAME}-${UUID}"
log "Registry configurado: ${REGISTRY}"

# Criação da estrutura de diretórios para desenvolvimento
log "Criando estrutura de diretórios para desenvolvimento..."
mkdir -p tilt-dev

# Geração do Dockerfile otimizado para produção
# Multi-stage build com otimizações para tamanho e segurança
log "Criando Dockerfile de produção na raiz..."
cat > Dockerfile << 'EOL'
# Stage 1: Build com cache de dependências e compilação otimizada
FROM golang:1.23 AS builder
ARG TARGETOS
ARG TARGETARCH

WORKDIR /workspace
COPY go.mod go.mod
COPY go.sum go.sum
RUN go mod download

COPY cmd/main.go cmd/main.go
COPY api/ api/
COPY internal/controller/ internal/controller/

RUN CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH} go build -a -o manager cmd/main.go

# Stage 2: Imagem minimal com apenas o binário
FROM gcr.io/distroless/static:nonroot
WORKDIR /app
COPY --from=builder /workspace/manager .
USER 65532:65532

ENTRYPOINT ["/app/manager"]
EOL

# Geração do Dockerfile para desenvolvimento com debug
# Inclui Delve e configurações para debug remoto
log "Criando tilt.docker para ambiente de desenvolvimento..."
cat > tilt-dev/tilt.docker << 'EOL'
FROM golang:1.23

# Instalação do Delve para debug
RUN go install github.com/go-delve/delve/cmd/dlv@latest
WORKDIR /app

# Setup de usuário não-root e permissões
COPY ./bin/manager .
RUN chmod +x ./manager && \
    addgroup --gid 65532 appgroup && \
    adduser --uid 65532 --gid 65532 --disabled-password --gecos "" appuser && \
    chown -R 65532:65532 /app /go

USER 65532
EOL

# Configuração do .dockerignore para otimizar builds
if [ -f ".dockerignore" ]; then
    log "Ajustando .dockerignore..."
    sed -i 's|^bin/|#bin/|' ".dockerignore"
    log "${GREEN}✓ .dockerignore atualizado${NC}"
fi

# Geração do patch para ajuste de recursos em desenvolvimento
# Customiza recursos e remove health checks para dev
log "Criando patch do manager para desenvolvimento..."
cat > tilt-dev/manager_patch.yaml << 'EOL'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: controller-manager
  namespace: system
spec:
  template:
    spec:
      containers:
      - name: manager
        # Recursos ajustados para desenvolvimento
        resources:
          limits:
            cpu: 1000m
            memory: 512Mi
          requests:
            cpu: 100m
            memory: 256Mi
        # Remove health checks em dev
        livenessProbe: null
        readinessProbe: null
        # Configura porta para debug
        ports:
        - containerPort: 40000
          name: delve
          protocol: TCP
EOL

# Geração do kustomization para overlay de desenvolvimento
# Aplica patches específicos para ambiente de dev
log "Criando kustomization para desenvolvimento..."
cat > tilt-dev/kustomization.yaml << EOL
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Base das configurações
resources:
- ../config/default

# Patches para desenvolvimento
patches:
- path: manager_patch.yaml

# Configuração de imagens
images:
- name: controller
  newName: ${CONTROLLER_NAME}
  newTag: latest
EOL

# Geração do Tiltfile com configurações de desenvolvimento
# Configura hot reload, debug e build otimizado
log "Criando Tiltfile..."
cat > Tiltfile << EOL
# Carrega extensão para restart de processos
load('ext://restart_process', 'docker_build_with_restart')

# Configurações base
IMG = '${CONTROLLER_NAME}:latest'
REGISTRY = '${REGISTRY}'

# Configura registry efêmero
default_registry(REGISTRY)

# Função para aplicar overlay de desenvolvimento
def k8s_yaml_dev():
    return local('kustomize build tilt-dev')

# Função para gerar manifestos
def manifests():
    return 'controller-gen rbac:roleName=manager-role crd webhook paths="./..." output:crd:artifacts:config=config/crd/bases;'

# Função para geração de código
def generate():
    return 'controller-gen object:headerFile="hack/boilerplate.go.txt" paths="./...";'

# Função para compilação com flags de debug
def binary():
    return 'CGO_ENABLED=0 GOOS=linux GOARCH=amd64 GO111MODULE=on go build -gcflags "all=-N -l" -o bin/manager cmd/main.go'

# Executa geração inicial
local(manifests() + generate())

# Configura recurso para CRDs
local_resource('crd', 
    manifests() + 'kustomize build config/crd | kubectl apply -f -', 
    deps=["api"],
    ignore=['config/crd/bases/*', 'config/rbac/*']
)

# Aplica configurações de desenvolvimento
k8s_yaml(k8s_yaml_dev())

# Configura hot reload para recompilação
local_resource(
    'recompile',
    generate() + binary() + '; echo "Recompilação concluída"',
    deps=['internal/controller', 'cmd/main.go'],
    ignore=['*.pb.go', 'config/crd/bases/*', 'config/rbac/*']
)

# Configuração do container de desenvolvimento com Delve
docker_build_with_restart(
    IMG, '.',
    dockerfile='tilt-dev/tilt.docker',
    only=['./bin/manager'],
    entrypoint='/go/bin/dlv --listen=0.0.0.0:40000 --api-version=2 --headless=true --only-same-user=false --accept-multiclient --continue --check-go-version=false exec /app/manager',
    live_update=[
        sync('./bin/manager', '/app/manager')
    ]
)

# Configuração de port-forward e dependências
k8s_resource(
    '${CONTROLLER_NAME}-controller-manager',
    port_forwards=["40000:40000"],
    resource_deps=['recompile'],
    trigger_mode=TRIGGER_MODE_AUTO
)
EOL

# Geração do .tiltignore para otimização
# Lista de arquivos e diretórios a serem ignorados pelo Tilt
log "Criando .tiltignore..."
cat > .tiltignore << 'EOL'
.git
.idea
.vscode
.kube
.DS_Store
tmp/
vendor/
testbin/
.tiltbuild/
*.out
*.test
*.pb.go
coverage.txt
**/zz_generated.*
go.work*
*.swp
*~
.env*
EOL

# Configuração da IDE escolhida
configure_ide

# Mensagem de conclusão e resumo
log "${GREEN}Configuração concluída com sucesso!${NC}"
log "${YELLOW}Para iniciar o desenvolvimento, execute: tilt up${NC}"

# Lista detalhada dos arquivos criados
echo -e "\nEstrutura criada:"
echo -e "${GREEN}✓${NC} Dockerfile - Build otimizado para produção"
echo -e "${GREEN}✓${NC} tilt-dev/"
echo -e "  ${GREEN}├─${NC} kustomization.yaml - Overlay para desenvolvimento"
echo -e "  ${GREEN}├─${NC} manager_patch.yaml - Ajustes de recursos e debug"
echo -e "  ${GREEN}└─${NC} tilt.docker - Ambiente de desenvolvimento com debug"
echo -e "${GREEN}✓${NC} Tiltfile - Configuração do Tilt com hot reload"
echo -e "${GREEN}✓${NC} .tiltignore - Otimização de rebuilds"

# Exibe informações específicas da IDE configurada
if [[ -d ".vscode" ]]; then
    echo -e "${GREEN}✓${NC} .vscode/"
    echo -e "  ${GREEN}└─${NC} launch.json - Configuração de debug VSCode"
elif [[ -d ".idea" ]]; then
    echo -e "${GREEN}✓${NC} .idea/"
    echo -e "  ${GREEN}└─${NC} runConfigurations/Remote_Debug.xml - Configuração de debug GoLand"
elif [[ -d "~/.config/helix" ]]; then
    echo -e "${GREEN}✓${NC} ~/.config/helix/"
    echo -e "  ${GREEN}└─${NC} config.toml - Configuração de debug Helix"
fi

# Informações sobre o Registry efêmero
echo -e "\nRegistry ttl.sh configurado:"
echo -e "└─ ${REGISTRY}"
echo -e "   ├─ Tempo de expiração: 24h (padrão)"
echo -e "   ├─ Sem autenticação necessária"
echo -e "   └─ Imagens automaticamente removidas após expiração"

# Instruções detalhadas para próximos passos
echo -e "\nPróximos passos:"
echo "1. Inicie o ambiente: tilt up"
echo "2. Configure seu IDE para debug remoto:"
if [[ -d ".vscode" ]]; then
    echo "   - VSCode: Use o launch profile 'Attach to DLV-DAP'"
    echo "   - Certifique-se de ter a extensão Go instalada"
elif [[ -d ".idea" ]]; then
    echo "   - GoLand: Use a configuração 'Remote Debug'"
    echo "   - Verifique se o projeto Go está configurado corretamente"
else
    echo "   - Helix: Use <space>-g para acessar o menu de debug"
    echo "   - Adicione breakpoints com 'b'"
    echo "   - Use 'attach' para conectar ao processo"
    echo "   - Use 'v' para visualizar variáveis em breakpoints"
fi
echo "3. A porta 40000 está configurada para debug remoto"
echo "4. Edite o código - as alterações serão aplicadas automaticamente"
echo "5. Use breakpoints no seu IDE para debug durante o desenvolvimento"

# Resumo das configurações e recursos
echo -e "\nRecursos configurados:"
echo "- Hot Reload ativado para alterações de código"
echo "- Debug remoto na porta 40000"
echo "- Recursos do pod ajustados para desenvolvimento"
echo "- Multi-stage build para produção e desenvolvimento"
echo "- Overlay Kustomize para ambiente de desenvolvimento"
echo "- Registry efêmero ttl.sh integrado"

# Notas finais e importantes
log "${GREEN}Nota: Todas as configurações de desenvolvimento foram feitas via overlay em tilt-dev/${NC}"
log "${GREEN}      Os arquivos originais em config/ permanecem inalterados${NC}"

# Dicas para melhor utilização
log "${YELLOW}Dicas:${NC}"
echo "- Use 'tilt up --stream' para acompanhar os logs do operator em tempo real"
echo "- As imagens no ttl.sh expiram após 24h, ideal para desenvolvimento e CI"
echo "- Para builds de produção, use seu próprio registry com o Dockerfile padrão"