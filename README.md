# Treinamento: Operators Kubernetes

Este repositório contém o material para o treinamento básico de desenvolvimento de Operators Kubernetes usando Kubebuilder.

## Setup Rápido

Execute este comando para configurar o ambiente:

```bash
curl -sSL https://raw.githubusercontent.com/cloud104/tcloud-devops-k8s-operators-training/main/scripts/setup.sh | bash
```

Após a instalação:

```bash
source ~/.bashrc
# Faça logout e login novamente para aplicar as mudanças do grupo docker
```

## Pré-requisitos

- Linux Ubuntu/Debian
- Acesso sudo
- Conhecimento básico de Kubernetes
- Familiaridade com Go

## Estrutura do Treinamento

- `/docs`: Documentação e guias
- `/operator`: Código do operator SampleApp
- `/scripts`: Scripts de utilidade

## Desenvolvimento do Operator

O treinamento usa um exemplo prático de um operator chamado SampleApp, que demonstra:

1. Criação de CRDs com Kubebuilder
2. Implementação de um controller básico
3. Reconciliação de recursos
4. Uso do Tilt para desenvolvimento

## Material do Treinamento

Após configurar o ambiente, obtenha o material:

```bash
git clone https://github.com/cloud104/tcloud-devops-k8s-operators-training
cd tcloud-devops-k8s-operators-training
```

## Documentação

Consulte a pasta `/docs` para:

- Conceitos básicos de Operators
- Guia passo a passo do desenvolvimento
- Referências e boas práticas

## Suporte

Para dúvidas ou problemas, abra uma issue no repositório.
