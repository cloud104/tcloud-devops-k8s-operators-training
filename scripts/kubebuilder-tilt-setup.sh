#!/bin/bash

###############################################################################
# Setup do Tilt para projetos Kubebuilder em cluster Kind
#
# Execute na raiz do projeto. Gera:
#   Tiltfile               recompila o manager e reaplica o Deployment
#   tilt-dev/tilt.docker   imagem mínima com o binário compilado no host
#   tilt-dev/              overlay Kustomize sobre config/default
#   .tiltignore
#
# Sem registry: em cluster Kind o Tilt carrega a imagem direto no node.
# Nada aqui altera config/: o que é só de desenvolvimento fica em tilt-dev/.
###############################################################################

set -euo pipefail

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

for dep in go kubectl tilt make; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        log "Erro: $dep não encontrado. Execute scripts/setup-tools.sh primeiro."
        exit 1
    fi
done

if [ ! -f PROJECT ]; then
    log "Erro: execute este script na raiz do projeto Kubebuilder (arquivo PROJECT)."
    exit 1
fi

PROJECT_NAME=$(awk '/^projectName:/ {print $2}' PROJECT)
if [ -z "$PROJECT_NAME" ]; then
    log "Erro: projectName não encontrado em PROJECT"
    exit 1
fi
log "Projeto: ${PROJECT_NAME}"

mkdir -p tilt-dev

cat > tilt-dev/tilt.docker <<'EOL'
FROM gcr.io/distroless/static-debian12:nonroot
COPY bin/manager /manager
USER 65532:65532
ENTRYPOINT ["/manager"]
EOL

# O .dockerignore do scaffold ignora tudo por default
if [ -f .dockerignore ] && ! grep -qx '!bin/manager' .dockerignore; then
    echo '!bin/manager' >> .dockerignore
fi

cat > tilt-dev/kustomization.yaml <<'EOL'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- ../config/default

patches:
- path: manager_patch.yaml
EOL

cat > tilt-dev/manager_patch.yaml <<'EOL'
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
        resources:
          limits:
            cpu: 1000m
            memory: 512Mi
          requests:
            cpu: 100m
            memory: 128Mi
EOL

cat > Tiltfile <<'EOL'
# Só contextos do kind: o Tilt recusa os demais
allow_k8s_contexts('kind-k8s-operators-lab')

# Regenera CRD, RBAC e DeepCopy, e reinstala a CRD quando a API muda
local_resource(
    'crd',
    'make manifests generate install',
    deps=['api'],
    ignore=['api/**/zz_generated.*'],
)

# Compila no host, com o cache do Go: bem mais rápido que dentro da imagem
local_resource(
    'recompile',
    'CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o bin/manager cmd/main.go',
    deps=['api', 'cmd', 'internal'],
    ignore=['**/*_test.go'],
    resource_deps=['crd'],
)

docker_build(
    'controller',
    '.',
    dockerfile='tilt-dev/tilt.docker',
    only=['bin/manager'],
)

k8s_yaml(local('make -s kustomize >/dev/null && bin/kustomize build tilt-dev', quiet=True))
EOL

cat >> Tiltfile <<EOL

k8s_resource('${PROJECT_NAME}-controller-manager', resource_deps=['recompile'])
EOL

cat > .tiltignore <<'EOL'
.git
bin/k8s
cover.out
*.test
*.swp
*~
EOL

log "Configuração concluída. Para iniciar: tilt up"
