# Desenvolvimento do Operator

Este guia aborda o desenvolvimento completo do nosso Operator **SampleApp** usando **Kubebuilder**.

## 1. Configuração Inicial

### 1.1 Criando o Cluster de Desenvolvimento

Execute o script de setup do cluster Kind e registry

```bash
export KUBECONFIG=$HOME/.kube/k8s-operators-lab-config
curl -sSL https://raw.githubusercontent.com/cloud104/tcloud-devops-k8s-operators-training/main/scripts/setup-cluster.sh | bash
```

Verifique o cluster

```bash
kubectl cluster-info  # Deve mostrar o cluster Kind
```

### 1.2 Criando o Projeto

Certifique-se que o KUBECONFIG está configurado

```bash
echo $KUBECONFIG
export KUBECONFIG=$HOME/.kube/k8s-operators-lab-config
```

Crie e entre no diretório do projeto

```bash
mkdir sampleapp-operator
cd sampleapp-operator
```

Inicialize o projeto com Kubebuilder

```bash
kubebuilder init --domain cloud104.com --repo github.com/cloud104/sampleapp-operator
```

Crie a API (CRD & Controller)

```bash
kubebuilder create api --group apps --version v1alpha1 --kind SampleApp
```

Responder "y"

```bash
INFO Create Resource [y/n]
y
INFO Create Controller [y/n]
y
```

Abrir seu editor de código (ex. vscode)

```bash
code .
```

### 1.3 Verificação e Instalação dos CRDs

#### Geração e Instalação

Gerar códigos e manifestos

```bash
make manifests
make generate
```

Verifique o cluster

```bash
export KUBECONFIG=$HOME/.kube/k8s-operators-lab-config
kubectl cluster-info  # Deve mostrar o cluster Kind
```

Teste antes da instalação

```bash
kubectl get sampleapp -A
```

Instalar CRDs no cluster

```bash
make install
```

#### Verificação Final

Teste após a instalação

```bash
kubectl get sampleapp -A
```

Listar o CRD

```bash
kubectl get crds sampleapps.apps.cloud104.com
```

Teste aplicando manifesto após a instalação

```bash
kubectl apply -f config/samples/apps_v1alpha1_sampleapp.yaml -n default
```

Listar todos os sampleapp em todos os namespaces

```bash
kubectl get sampleapp -A
```

Detalhar o sampleapp (sampleapp-sample) criado

```bash
kubectl get sampleapp sampleapp-sample -o yaml -n default
```

Excluindo o recurso

```bash
kubectl delete -f config/samples/apps_v1alpha1_sampleapp.yaml -n default
```

### 1.4 Comandos Make Explicados

| Comando | Descrição |
|---------|-----------|
| `make manifests` | Gera os manifestos YAML para CRDs e configurações |
| `make generate` | Gera código boilerplate baseado nas anotações Kubebuilder |
| `make install` | Aplica os CRDs gerados ao cluster Kubernetes |

## 2. Ambiente de Desenvolvimento

### 2.1 Configuração do Tilt

Configurar ambiente Tilt

```bash
curl -sSL https://raw.githubusercontent.com/cloud104/tcloud-devops-k8s-operators-training/main/scripts/kubebuilder-tilt-setup.sh | bash
```

## 3. Implementação

### 3.1 Definição da API

Editar o arquivo api/v1alpha1/sampleapp_types.go

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

// +kubebuilder:object:root=true

// SampleAppList contém uma lista de SampleApp.
type SampleAppList struct {
 metav1.TypeMeta `json:",inline"`
 metav1.ListMeta `json:"metadata,omitempty"`
 Items           []SampleApp `json:"items"`
}

func init() {
 SchemeBuilder.Register(&SampleApp{}, &SampleAppList{})
}
```

Regerar e instalar

```bash
make generate; make manifests; make install
```

Ajustando o manifesto (config/samples/apps_v1alpha1_sampleapp.yaml)

```yaml
apiVersion: apps.cloud104.com/v1alpha1
kind: SampleApp
metadata:
  name: sampleapp-example
spec:
  replicas: 1
  image: fmnapoli/teste-app:v1
  port: 5000
```

Teste aplicando manifesto após atualização do do CRD

```bash
kubectl apply -f config/samples/apps_v1alpha1_sampleapp.yaml -n default
```

Detalhar o sampleapp (sampleapp-sample) criado

```bash
kubectl get sampleapp sampleapp-sample -o yaml -n default
```

Excluindo o recurso

```bash
kubectl delete -f config/samples/apps_v1alpha1_sampleapp.yaml -n default
```

### 3.2 Implementação do Controller

Editar o arquivo controllers/sampleapp_controller.go

```go
package controller

import (
    "context"
    appsv1 "k8s.io/api/apps/v1"
    corev1 "k8s.io/api/core/v1"
    "k8s.io/apimachinery/pkg/api/errors"
    metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
    "k8s.io/apimachinery/pkg/runtime"
    "k8s.io/apimachinery/pkg/types"
    "k8s.io/apimachinery/pkg/util/intstr"
    ctrl "sigs.k8s.io/controller-runtime"
    "sigs.k8s.io/controller-runtime/pkg/client"
    "sigs.k8s.io/controller-runtime/pkg/log"
    
    appsv1alpha1 "github.com/cloud104/sampleapp-operator/api/v1alpha1"
)

type SampleAppReconciler struct {
    client.Client
    Scheme *runtime.Scheme
}

// Controle de acesso

// +kubebuilder:rbac:groups=apps.cloud104.com,resources=sampleapps,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=apps.cloud104.com,resources=sampleapps/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=apps.cloud104.com,resources=sampleapps/finalizers,verbs=update
// +kubebuilder:rbac:groups=apps,resources=deployments,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=core,resources=services,verbs=get;list;watch;create;update;patch;delete

// Função principal de reconciliação
func (r *SampleAppReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
    log := log.FromContext(ctx)
    
    // Obter o recurso
    sampleApp := &appsv1alpha1.SampleApp{}
    if err := r.Get(ctx, req.NamespacedName, sampleApp); err != nil {
        return ctrl.Result{}, client.IgnoreNotFound(err)
    }
    
    log.Info("iniciando reconciliação", "name", req.NamespacedName)
    
    // Reconciliar Deployment
    deployment, err := r.reconcileDeployment(ctx, sampleApp)
    if err != nil {
        log.Error(err, "falha ao reconciliar deployment")
        return ctrl.Result{}, err
    }
    
    // Reconciliar Service
    if err := r.reconcileService(ctx, sampleApp); err != nil {
        log.Error(err, "falha ao reconciliar service")
        return ctrl.Result{}, err
    }
    
    // Atualizar Status
    sampleApp.Status.AvailableReplicas = deployment.Status.AvailableReplicas
    if err := r.Status().Update(ctx, sampleApp); err != nil {
        log.Error(err, "falha ao atualizar status")
        return ctrl.Result{}, err
    }
    
    log.Info("reconciliação completada com sucesso")
    return ctrl.Result{}, nil
}

// Reconcilia o Deployment
func (r *SampleAppReconciler) reconcileDeployment(ctx context.Context, app *appsv1alpha1.SampleApp) (*appsv1.Deployment, error) {
    log := log.FromContext(ctx)
    
    deploy := &appsv1.Deployment{
        ObjectMeta: metav1.ObjectMeta{
            Name:      app.Name,
            Namespace: app.Namespace,
        },
    }
    
    op, err := ctrl.CreateOrUpdate(ctx, r.Client, deploy, func() error {
        r.specDeployment(app, deploy)
        return ctrl.SetControllerReference(app, deploy, r.Scheme)
    })
    
    if err != nil {
        return nil, err
    }

    // Log da operação realizada
    log.Info("deployment reconciliado", 
        "name", app.Name,
        "operation", op,
        "replicas", app.Spec.Replicas)
    
    return deploy, nil
}

// Define a spec do Deployment
func (r *SampleAppReconciler) specDeployment(app *appsv1alpha1.SampleApp, deploy *appsv1.Deployment) {
    replicas := app.Spec.Replicas
    
    deploy.Spec = appsv1.DeploymentSpec{
        Replicas: &replicas,
        Selector: &metav1.LabelSelector{
            MatchLabels: map[string]string{
                "app": app.Name,
            },
        },
        Template: corev1.PodTemplateSpec{
            ObjectMeta: metav1.ObjectMeta{
                Labels: map[string]string{
                    "app": app.Name,
                },
            },
            Spec: corev1.PodSpec{
                Containers: []corev1.Container{
                    {
                        Name:  "sampleapp",
                        Image: app.Spec.Image,
                        Ports: []corev1.ContainerPort{
                            {
                                ContainerPort: app.Spec.Port,
                            },
                        },
                    },
                },
            },
        },
    }
}

// Reconcilia o Service
func (r *SampleAppReconciler) reconcileService(ctx context.Context, app *appsv1alpha1.SampleApp) error {
    log := log.FromContext(ctx)
    
    svc := &corev1.Service{
        ObjectMeta: metav1.ObjectMeta{
            Name:      app.Name,
            Namespace: app.Namespace,
        },
    }
    
    op, err := ctrl.CreateOrUpdate(ctx, r.Client, svc, func() error {
        r.specService(app, svc)
        return ctrl.SetControllerReference(app, svc, r.Scheme)
    })
    
    if err != nil {
        return err
    }

    // Log da operação realizada
    log.Info("service reconciliado", 
        "name", app.Name,
        "operation", op,
        "port", app.Spec.Port)
    
    return nil
}

// Define a spec do Service
func (r *SampleAppReconciler) specService(app *appsv1alpha1.SampleApp, svc *corev1.Service) {
    svc.Spec = corev1.ServiceSpec{
        Selector: map[string]string{
            "app": app.Name,
        },
        Type: corev1.ServiceTypeNodePort,
        Ports: []corev1.ServicePort{
            {
                Port:       app.Spec.Port,
                TargetPort: intstr.FromInt(int(app.Spec.Port)),
                NodePort:   30000,
            },
        },
    }
}

// SetupWithManager configura o controller com o manager
func (r *SampleAppReconciler) SetupWithManager(mgr ctrl.Manager) error {
    return ctrl.NewControllerManagedBy(mgr).
        For(&appsv1alpha1.SampleApp{}).
        Owns(&appsv1.Deployment{}).
        Owns(&corev1.Service{}).
        Complete(r)
}
```

Executando o controller localmente

```bash
make run
```

Executando o controller no cluster (Tilt)

```bash
tilt up
```

> **Nota**: Acesse o dashboard do Tilt em [http://localhost:10350](http://localhost:10350)

- Configurar o debugger do VSCode (.vscode/launch.json)

```json
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
```

## 4. Teste e Implantação

### 4.1 Exemplo de Recurso

```yaml
apiVersion: apps.cloud104.com/v1alpha1
kind: SampleApp
metadata:
  name: sampleapp-example
spec:
  replicas: 3
  image: fmnapoli/teste-app:v2
  port: 5000
```

### 4.2 Verificação dos Recursos

Aplicar o exemplo

```bash
kubectl apply -f config/samples/apps_v1alpha1_sampleapp.yaml
```

Verificar recursos criados

```bash
kubectl get sampleapp,deployments,services,pods
```

### 4.3 Testes do Operator

Verificar status

```bash
kubectl get sampleapp sampleapp-example -o yaml
```

Modificar réplicas e Monitorar pods

```bash
kubectl patch sampleapp sampleapp-example --type='json' \
  -p='[{"op": "replace", "path": "/spec/replicas", "value":5}]' -n default
kubectl get pods -w -n default
```
