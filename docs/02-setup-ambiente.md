# Setup do Ambiente de Desenvolvimento

Este guia descreve os passos para configurar um ambiente de desenvolvimento para operators Kubernetes usando Kubebuilder e Tilt.

## Pré-requisitos

- Linux Ubuntu/Debian
- Acesso sudo
- Conhecimento básico de Kubernetes e Go

## Configuração do Ambiente

### 1. Configure o KUBECONFIG

Primeiro, configure um KUBECONFIG específico para este ambiente de desenvolvimento:

```bash
# Configure o KUBECONFIG para um arquivo dedicado
export KUBECONFIG=$HOME/.kube/k8s-operators-lab-config
```

### 2. Instale as Ferramentas e Crie o Cluster

Execute o script de setup que instalará todas as ferramentas necessárias:

```bash
curl -sSL https://raw.githubusercontent.com/cloud104/tcloud-devops-k8s-operators-training/main/scripts/setup-tools.sh | bash
```

Execute o script de setup do cluster Kind e registry

```bash
curl -sSL https://raw.githubusercontent.com/cloud104/tcloud-devops-k8s-operators-training/main/scripts/setup-cluster.sh | bash
```

O script instalará:

- Go 1.23+
- Docker
- Kind (Kubernetes in Docker)
- kubectl
- Kubebuilder
- Kustomize
- Tilt

### 3. Aplique as Alterações

```bash
# Carregue as novas configurações do ambiente
source ~/.bashrc
```

- IMPORTANTE: Faça logout e login para aplicar as mudanças do grupo docker

### 4. Verifique a Instalação

Confira se tudo foi instalado corretamente:

```bash
# Verifique as versões instaladas
go version         # Deve mostrar Go 1.23+
docker version     # Deve mostrar cliente e servidor
kind version       # Deve mostrar a versão do Kind
kubebuilder version
kubectl version
tilt version

# Verifique o cluster
kubectl cluster-info  # Deve mostrar o cluster Kind
```

## Problemas Comuns

1. **Erro de permissão do Docker**
   - Certifique-se de ter feito logout e login após a instalação do Docker
   - Verifique se seu usuário está no grupo docker: `groups $USER`

2. **Cluster Kind não inicia**
   - Verifique se o Docker está rodando: `systemctl status docker`
   - Verifique se as portas necessárias estão livres: `lsof -i :80 -i :443`

3. **KUBECONFIG não configurado**
   - Execute novamente o export do KUBECONFIG
   - Verifique se o diretório foi criado: `ls -la $KUBECONFIG`

## Limpeza

Para remover o ambiente de desenvolvimento:

```bash
# Remova o cluster Kind
kind delete cluster --name k8s-operators-lab
```
