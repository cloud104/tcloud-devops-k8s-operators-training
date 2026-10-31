# Setup do Ambiente de Desenvolvimento

Este guia descreve os passos para configurar um ambiente de desenvolvimento para operators Kubernetes usando Kubebuilder e Tilt.

## Pré-requisitos

- Linux Ubuntu/Debian
- Acesso sudo
- Conhecimento básico de Kubernetes e Go
- Cerca de 3 GB livres em disco para a imagem do node, o cache do Go e os binários do envtest

## Configuração do Ambiente

Os scripts vêm do clone deste repositório. Rode os comandos a partir da raiz dele.

### 1. Instale as Ferramentas

```bash
scripts/setup-tools.sh
```

O script instala o que faltar, nas versões pinadas no topo dele. O que já existe não é trocado: se a versão divergir,
ele avisa com `[AVISO]`.

| Ferramenta | Versão |
|---|---|
| Go | 1.26.8 |
| Docker | a do repositório oficial |
| kind | 0.33.0 |
| kubectl | 1.37.0 |
| Kubebuilder | 4.16.0 |
| Kustomize | 5.8.1 |
| Tilt | 0.37.8 |

`SKIP_APT=1` pula o `apt-get`, e `BIN_DIR=<dir>` instala os binários em outro diretório, sem sudo.

### 2. Aplique as Alterações

```bash
source ~/.bashrc   # ou ~/.zshrc
```

- IMPORTANTE: na primeira instalação do Docker, faça logout e login para aplicar o grupo `docker`

### 3. Crie o Cluster

Use um KUBECONFIG dedicado, para não tocar nos seus outros clusters:

```bash
export KUBECONFIG="$HOME/.kube/k8s-operators-lab-config"
scripts/setup-cluster.sh
```

### 4. Verifique a Instalação

```bash
go version
docker version
kind version
kubebuilder version
kubectl version
tilt version
kubectl cluster-info
```

## Problemas Comuns

1. **Erro de permissão do Docker**
   - Certifique-se de ter feito logout e login após a instalação do Docker
   - Verifique se seu usuário está no grupo docker: `groups $USER`

2. **Cluster Kind não inicia**
   - Verifique se o Docker está rodando: `systemctl status docker`
   - Verifique se a porta do NodePort está livre: `ss -ltn | grep 30000`

3. **KUBECONFIG não configurado**
   - Execute novamente o export do KUBECONFIG, em cada terminal
   - Confira: `kubectl config current-context` deve mostrar `kind-k8s-operators-lab`

4. **Porta 30000 ocupada**
   - O cluster mapeia essa porta no host: `ss -ltn | grep 30000`

## Limpeza

Para remover o ambiente de desenvolvimento:

```bash
# Remova o cluster Kind
kind delete cluster --name k8s-operators-lab
rm -f "$HOME/.kube/k8s-operators-lab-config"
```
