# Treinamento de Operators Kubernetes

Este repositório contém material para treinamento básico de desenvolvimento de Operators Kubernetes usando Kubebuilder.

## Início Rápido

1. Configure o ambiente:

```bash
# Configure KUBECONFIG dedicado
export KUBECONFIG=$HOME/.kube/operators-training-config


# Instale as ferramentas necessárias
curl -sSL https://raw.githubusercontent.com/cloud104/tcloud-devops-k8s-operators-training/main/scripts/setup-tools.sh | bash

# Aplique as alterações
source ~/.bashrc

# Configure o cluster Kind e registry
curl -sSL https://raw.githubusercontent.com/cloud104/tcloud-devops-k8s-operators-training/main/scripts/setup-cluster.sh | bash

# Instale as ferramentas necessárias

curl -sSL <https://raw.githubusercontent.com/cloud104/tcloud-devops-k8s-operators-training/main/scripts/setup-tools.sh> | bash

# Aplique as alterações

source ~/.bashrc

# Configure o cluster Kind e registry

curl -sSL <https://raw.githubusercontent.com/cloud104/tcloud-devops-k8s-operators-training/main/scripts/setup-cluster.sh> | bash

```

2. Crie um novo operator:

```bash
mkdir sampleapp-operator
cd sampleapp-operator

# Inicialize com Kubebuilder
kubebuilder init --domain cloud104.com --repo github.com/cloud104/sampleapp-operator
kubebuilder create api --group apps --version v1alpha1 --kind SampleApp

# Configure ambiente de desenvolvimento
curl -sSL https://raw.githubusercontent.com/cloud104/tcloud-devops-k8s-operators-training/main/scripts/kubebuilder-tilt-setup.sh | bash
```

## Estrutura do Treinamento

- `docs/`: Documentação e guias
  - `01-conceitos-basicos.md`: Fundamentos de Operators
  - `02-setup-ambiente.md`: Configuração do ambiente
  - `03-desenvolvimento.md`: Desenvolvimento do operator

- `operator/sampleapp/`: Código fonte do operator exemplo
- `scripts/`: Scripts de configuração do ambiente

## Pré-requisitos

- Linux Ubuntu/Debian
- Acesso sudo
- Conhecimento básico de Kubernetes
- Familiaridade com Go

## Suporte

Em caso de dúvidas ou problemas, abra uma issue no repositório.
