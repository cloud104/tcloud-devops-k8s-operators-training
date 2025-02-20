# Desenvolvimento do Operator

Este guia aborda o desenvolvimento completo do nosso Operator **SampleApp** usando **Kubebuilder**.

---

## 1. Criando o Projeto

```bash
# Certifique-se que o KUBECONFIG está configurado
echo $KUBECONFIG

# Crie e entre no diretório do projeto
mkdir sampleapp-operator
cd sampleapp-operator

# Inicialize o projeto com Kubebuilder
kubebuilder init --domain cloud104.com --repo github.com/cloud104/sampleapp-operator

# Crie a API
kubebuilder create api --group apps --version v1alpha1 --kind SampleApp

# Gere o código e os manifests necessários
make generate
make manifests

# Instale os CRDs no cluster
make install

# Configure o ambiente de desenvolvimento com Tilt
curl -sSL https://raw.githubusercontent.com/cloud104/tcloud-devops-k8s-operators-training/main/scripts/kubebuilder-tilt-setup.sh | bash
```

---

## Explicação dos Comandos `Make`

### `make generate`
Este comando gera o código necessário para os controladores e tipos de recursos definidos. Ele utiliza as anotações Kubebuilder presentes nos arquivos de código para criar automaticamente o código boilerplate necessário.

### `make manifests`
Este comando gera os manifests YAML necessários para definir os **Custom Resource Definitions (CRDs)** e outras configurações do Kubernetes. Ele cria os arquivos de configuração que serão aplicados ao cluster para registrar os novos tipos de recursos.

### `make install`
Este comando aplica os CRDs gerados ao cluster Kubernetes. Ele instala os CRDs no cluster, permitindo que os novos tipos de recursos sejam reconhecidos e utilizados pelo Kubernetes.

---

## Iniciando o Ambiente de Desenvolvimento

```bash
tilt up
```

- Acesse o dashboard do Tilt em [http://localhost:10350](http://localhost:10350).
- Edite o código e veja as mudanças sendo aplicadas automaticamente.

---

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

A variável `op` do CreateOrUpdate pode ter três valores:

- `OperationResultNone`: Nenhuma mudança foi necessária
- `OperationResultCreated`: Um novo recurso foi criado
- `OperationResultUpdated`: Um recurso existente foi atualizado

## 4. Criando um Exemplo

Crie o arquivo `config/samples/apps_v1alpha1_sampleapp.yaml`:

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

## 5. Exemplo

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
