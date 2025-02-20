# Desenvolvimento do Operator

Este guia aborda o desenvolvimento completo do nosso operator SampleApp usando Kubebuilder.

## 1. Criando o Projeto

```bash
# Certifique-se que o KUBECONFIG está configurado
echo $KUBECONFIG

# Crie e entre no diretório do projeto
mkdir sampleapp-operator
cd sampleapp-operator

# Inicialize com Kubebuilder
kubebuilder init --domain cloud104.com --repo github.com/cloud104/sampleapp-operator

# Crie a API
kubebuilder create api --group apps --version v1alpha1 --kind SampleApp

# Configure o ambiente de desenvolvimento com Tilt
curl -sSL https://raw.githubusercontent.com/cloud104/tcloud-devops-k8s-operators-training/main/scripts/kubebuilder-tilt-setup.sh | bash
```

## 2. Definindo a API

Edite o arquivo `api/v1alpha1/sampleapp_types.go`:

```go
package v1alpha1

import (
    metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// SampleAppSpec define o estado desejado
type SampleAppSpec struct {
    // +kubebuilder:validation:Minimum=1
    // +kubebuilder:validation:Maximum=10
    // +kubebuilder:default=1
    Replicas int32 `json:"replicas,omitempty"`

    // +kubebuilder:validation:Required
    Image string `json:"image"`

    // +kubebuilder:validation:Minimum=1
    // +kubebuilder:validation:Maximum=65535
    // +kubebuilder:default=80
    Port int32 `json:"port,omitempty"`
}

// SampleAppStatus define o estado observado
type SampleAppStatus struct {
    // +optional
    AvailableReplicas int32 `json:"availableReplicas"`

    // +optional
    Conditions []metav1.Condition `json:"conditions,omitempty"`
}

//+kubebuilder:object:root=true
//+kubebuilder:subresource:status
//+kubebuilder:printcolumn:name="Replicas",type="integer",JSONPath=".spec.replicas"
//+kubebuilder:printcolumn:name="Available",type="integer",JSONPath=".status.availableReplicas"
//+kubebuilder:printcolumn:name="Age",type="date",JSONPath=".metadata.creationTimestamp"

// SampleApp é o Schema para a API sampleapps
type SampleApp struct {
    metav1.TypeMeta   `json:",inline"`
    metav1.ObjectMeta `json:"metadata,omitempty"`

    Spec   SampleAppSpec   `json:"spec,omitempty"`
    Status SampleAppStatus `json:"status,omitempty"`
}
```

## 3. Implementando o Controller

Edite o arquivo `controllers/sampleapp_controller.go`:

```go
package controllers

import (
    "context"
    appsv1 "k8s.io/api/apps/v1"
    corev1 "k8s.io/api/core/v1"
    "k8s.io/apimachinery/pkg/runtime"
    ctrl "sigs.k8s.io/controller-runtime"
    "sigs.k8s.io/controller-runtime/pkg/client"
    "sigs.k8s.io/controller-runtime/pkg/log"
    
    appsv1alpha1 "github.com/cloud104/sampleapp-operator/api/v1alpha1"
)

type SampleAppReconciler struct {
    client.Client
    Scheme *runtime.Scheme
}

func (r *SampleAppReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
    log := log.FromContext(ctx)
    
    // Obter o recurso
    sampleApp := &appsv1alpha1.SampleApp{}
    if err := r.Get(ctx, req.NamespacedName, sampleApp); err != nil {
        return ctrl.Result{}, client.IgnoreNotFound(err)
    }
    
    // Reconciliar Deployment
    deployment, err := r.reconcileDeployment(ctx, sampleApp)
    if err != nil {
        return ctrl.Result{}, err
    }
    
    // Reconciliar Service
    if err := r.reconcileService(ctx, sampleApp); err != nil {
        return ctrl.Result{}, err
    }
    
    // Atualizar Status
    sampleApp.Status.AvailableReplicas = deployment.Status.AvailableReplicas
    if err := r.Status().Update(ctx, sampleApp); err != nil {
        return ctrl.Result{}, err
    }
    
    return ctrl.Result{}, nil
}
```

## 4. Criando um Exemplo

Crie o arquivo `config/samples/apps_v1alpha1_sampleapp.yaml`:

```yaml
apiVersion: apps.cloud104.com/v1alpha1
kind: SampleApp
metadata:
  name: sampleapp-example
spec:
  replicas: 3
  image: nginx:1.14.2
  port: 80
```

## 5. Desenvolvendo com Tilt

Inicie o ambiente de desenvolvimento:

```bash

tilt up
```

- Acesse o dashboard do Tilt em <http://localhost:10350>
- Edite o código e veja as mudanças sendo aplicadas automaticamente

Em outro terminal, aplique o exemplo

```bash
kubectl apply -f config/samples/apps_v1alpha1_sampleapp.yaml

# Verifique os recursos
kubectl get sampleapp
kubectl get deployments
kubectl get services
kubectl get pods
```

## 6. Testando o Operator

```bash
# Verifique o status
kubectl get sampleapp sampleapp-example -o yaml

# Modifique o número de réplicas
kubectl patch sampleapp sampleapp-example --type='json' \
  -p='[{"op": "replace", "path": "/spec/replicas", "value":5}]'

# Observe a reconciliação acontecendo
kubectl get pods -w
```

## Próximos Passos

1. Adicione validações customizadas
2. Implemente métricas
3. Adicione mais funcionalidades como:
   - Health checks
   - Recursos configuráveis
   - Backup/restore
