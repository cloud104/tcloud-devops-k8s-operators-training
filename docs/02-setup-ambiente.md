# Setup do Ambiente de Desenvolvimento

## Instalação do Ambiente Base

```bash
curl -sSL https://raw.githubusercontent.com/cloud104/tcloud-devops-k8s-operators-training/main/scripts/setup.sh | bash
source ~/.bashrc
# Faça logout e login para aplicar o grupo docker
```

## Criação do Operator

1. Crie e entre no diretório do projeto:

```bash
mkdir sampleapp-operator
cd sampleapp-operator
```

2. Inicialize o projeto com Kubebuilder:

```bash
kubebuilder init --domain cloud104.com --repo github.com/cloud104/sampleapp-operator
kubebuilder create api --group apps --version v1alpha1 --kind SampleApp
```

3. Configure o ambiente de desenvolvimento com Tilt:

```bash
curl -sSL https://raw.githubusercontent.com/cloud104/tcloud-devops-k8s-operators-training/main/scripts/kubebuilder-tilt-setup.sh | bash
```

## Verificação

```bash
go version         # Deve mostrar Go 1.23+
docker version    # Deve mostrar o cliente e servidor
kind version      # Deve mostrar a versão do Kind
kubebuilder version
kubectl version
tilt version
```

## Desenvolvimento

1. O ambiente está pronto para desenvolvimento
2. Use `tilt up` para iniciar o ambiente de desenvolvimento
3. Edite o código e veja as mudanças em tempo real
