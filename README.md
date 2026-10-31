# Treinamento de Operators Kubernetes

Material de um treinamento de 3 horas sobre desenvolvimento de Operators Kubernetes com Kubebuilder. O lab é um
operator pequeno, o `SampleApp`, escrito do zero. Quem assiste não precisa preparar máquina: a parte prática é
conduzida ao vivo.

## Por onde começar

| Documento | Conteúdo |
|---|---|
| [`docs/00-roteiro.md`](docs/00-roteiro.md) | Roteiro da sessão, com tempos medidos |
| [`docs/01-conceitos-basicos.md`](docs/01-conceitos-basicos.md) | CRD, controller, reconcile, level-triggered |
| [`docs/02-setup-ambiente.md`](docs/02-setup-ambiente.md) | Ferramentas, versões pinadas e cluster |
| [`docs/03-desenvolvimento.md`](docs/03-desenvolvimento.md) | Passo a passo do lab |
| [`docs/extras/README.md`](docs/extras/README.md) | Índice das leituras: finalizer, rollout ordenado, predicates, informers |

## Início rápido

```bash
git clone git@github.com:cloud104/tcloud-devops-k8s-operators-training.git
cd tcloud-devops-k8s-operators-training
scripts/setup-tools.sh
```

Depois siga [`docs/03-desenvolvimento.md`](docs/03-desenvolvimento.md) a partir da raiz do clone.

## Versões

Pinadas em `scripts/setup-tools.sh` e `scripts/setup-cluster.sh`:

| Ferramenta | Versão |
|---|---|
| Go | 1.26.8 |
| Kubebuilder | 4.16.0 |
| controller-runtime | 0.25 (vem do scaffold) |
| Kubernetes (node do kind, kubectl) | 1.37.0 |
| kind | 0.33.0 |
| Kustomize | 5.8.1 |
| Tilt | 0.37.8 |

## Estrutura

- `docs/`: roteiro, conceitos, setup, passo a passo e leituras extras
- `scripts/setup-tools.sh`: instala as ferramentas
- `scripts/setup-cluster.sh`: cria o cluster kind do lab
- `scripts/kubebuilder-tilt-setup.sh`: configura o Tilt num projeto Kubebuilder

## Pré-requisitos

- Linux Ubuntu/Debian
- Acesso sudo
- Go e Kubernetes básicos (Deployment, Service)
