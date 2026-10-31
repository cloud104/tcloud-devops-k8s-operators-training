# Desenvolvimento do Operator

Passo a passo do lab: um operator **SampleApp** escrito do zero com Kubebuilder. Um `SampleApp` vira um
Deployment e um Service, com status, validação na CRD e reação a drift.

Tudo aqui roda copiando e colando, na ordem. Os blocos correspondem aos do [roteiro](00-roteiro.md).

## Preparação

Pré-requisito: as ferramentas do [setup do ambiente](02-setup-ambiente.md). Na raiz do clone deste repositório:

```bash
export TREINAMENTO="$PWD"
export KUBECONFIG="$HOME/.kube/k8s-operators-lab-config"
"$TREINAMENTO/scripts/setup-cluster.sh"
kubectl config current-context
```

Saída esperada: `kind-k8s-operators-lab`.

## Lab 1: scaffold, API, CEL, CRD instalada

### 1.1 Scaffold

```bash
export LAB="$(mktemp -d)/sampleapp-operator"
mkdir -p "$LAB" && cd "$LAB"
git init -q
kubebuilder init --domain cloud104.com --repo github.com/cloud104/sampleapp-operator
kubebuilder create api --group apps --version v1alpha1 --kind SampleApp --resource --controller
```

O que nasceu e importa para o lab:

| Caminho | Papel |
|---|---|
| `api/v1alpha1/sampleapp_types.go` | os tipos Go: é daqui que sai a CRD |
| `internal/controller/sampleapp_controller.go` | o `Reconcile` |
| `internal/controller/suite_test.go` | sobe o envtest |
| `config/crd/bases/` | CRD gerada: não se edita à mão |
| `config/samples/` | exemplo de CR |
| `cmd/main.go` | o manager, que registra o controller |

| Comando | O que faz |
|---|---|
| `make manifests` | gera CRD e RBAC a partir dos marcadores `+kubebuilder` |
| `make generate` | gera o `DeepCopy` dos tipos |
| `make install` | aplica a CRD no cluster |
| `make run` | roda o manager na sua máquina, contra o cluster do `KUBECONFIG` |
| `make test` | roda os testes com envtest |

### 1.2 A API

Os marcadores `Minimum`/`Maximum` validam um campo. O que compara campos, ou olha o conteúdo de uma string, é
**CEL**: uma regra que roda dentro do API Server, sem webhook. Só enxerga o próprio objeto.

```bash
cat > api/v1alpha1/sampleapp_types.go <<'EOF'
package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
)

// SampleAppSpec define o estado desejado.
// +kubebuilder:validation:XValidation:rule="self.image.contains(':') && !self.image.endsWith(':latest')",message="image precisa de uma tag fixa, diferente de latest"
// +kubebuilder:validation:XValidation:rule="self.port != self.nodePort",message="port e nodePort precisam ser diferentes"
type SampleAppSpec struct {
	// +kubebuilder:validation:Minimum=1
	// +kubebuilder:validation:Maximum=10
	// +kubebuilder:default=1
	// +optional
	Replicas int32 `json:"replicas,omitempty"`

	// +required
	Image string `json:"image"`

	// +kubebuilder:validation:Minimum=1
	// +kubebuilder:validation:Maximum=65535
	// +kubebuilder:default=80
	// +optional
	Port int32 `json:"port,omitempty"`

	// +kubebuilder:validation:Minimum=30000
	// +kubebuilder:validation:Maximum=32767
	// +kubebuilder:default=30000
	// +optional
	NodePort int32 `json:"nodePort,omitempty"`
}

// SampleAppStatus define o estado observado.
type SampleAppStatus struct {
	// +optional
	AvailableReplicas int32 `json:"availableReplicas,omitempty"`

	// +listType=map
	// +listMapKey=type
	// +optional
	Conditions []metav1.Condition `json:"conditions,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:printcolumn:name="Replicas",type="integer",JSONPath=".spec.replicas"
// +kubebuilder:printcolumn:name="Available",type="integer",JSONPath=".status.availableReplicas"
// +kubebuilder:printcolumn:name="Ready",type="string",JSONPath=".status.conditions[?(@.type==\"Ready\")].status"
// +kubebuilder:printcolumn:name="Age",type="date",JSONPath=".metadata.creationTimestamp"

// SampleApp é o Schema da API sampleapps.
type SampleApp struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitzero"`

	// +required
	Spec SampleAppSpec `json:"spec"`

	// +optional
	Status SampleAppStatus `json:"status,omitzero"`
}

// +kubebuilder:object:root=true

// SampleAppList contém uma lista de SampleApp.
type SampleAppList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitzero"`
	Items           []SampleApp `json:"items"`
}

func init() {
	SchemeBuilder.Register(func(s *runtime.Scheme) error {
		s.AddKnownTypes(SchemeGroupVersion, &SampleApp{}, &SampleAppList{})
		return nil
	})
}
EOF

cat > config/samples/apps_v1alpha1_sampleapp.yaml <<'EOF'
apiVersion: apps.cloud104.com/v1alpha1
kind: SampleApp
metadata:
  name: sampleapp-example
spec:
  replicas: 1
  image: fmnapoli/teste-app:v2
  port: 5000
EOF
```

### 1.3 CRD instalada

```bash
make generate manifests install
kubectl wait crd/sampleapps.apps.cloud104.com --for=condition=Established --timeout=30s
kubectl get crd sampleapps.apps.cloud104.com
```

As regras CEL foram parar na CRD:

```bash
grep -n -A1 'rule:\|message:' config/crd/bases/apps.cloud104.com_sampleapps.yaml | head
```

### 1.4 Testar a validação

CR válido entra, mesmo sem controller. Ele só fica guardado: ninguém está olhando.

```bash
kubectl apply -f config/samples/apps_v1alpha1_sampleapp.yaml
kubectl get sampleapp
kubectl get deployment
```

Saída esperada: o `SampleApp` existe com `REPLICAS` 1, e `No resources found` para Deployment.

CR inválido é recusado pelo API Server, antes de existir:

```bash
kubectl patch sampleapp sampleapp-example --type=merge -p '{"spec":{"image":"nginx:latest"}}' || true
kubectl patch sampleapp sampleapp-example --type=merge -p '{"spec":{"nodePort":5000}}' || true
kubectl patch sampleapp sampleapp-example --type=merge -p '{"spec":{"replicas":50}}' || true
kubectl delete sampleapp sampleapp-example
```

Saída esperada, a primeira das três:

```text
The SampleApp "sampleapp-example" is invalid: spec: Invalid value: ...: image precisa de uma tag fixa, diferente de latest
```

## Lab 2: chain, ensurers, status, drift

### 2.1 A chain

Em vez de um `Reconcile` que faz tudo, cada recurso tem um **ensurer**. Os ensurers rodam em ordem e dividem um
`State`: o que um descobre, o seguinte lê.

```bash
cat > internal/controller/chain.go <<'EOF'
package controller

import (
	"context"

	appsv1 "k8s.io/api/apps/v1"

	appsv1alpha1 "github.com/cloud104/sampleapp-operator/api/v1alpha1"
)

// State é criado a cada reconcile e compartilhado por todos os ensurers.
type State struct {
	App        *appsv1alpha1.SampleApp
	Deployment *appsv1.Deployment
	// Err guarda a falha que parou a chain, para o status poder publicá-la.
	Err error
}

// Ensurer garante uma coisa só, de forma idempotente: rodar duas vezes dá no mesmo.
type Ensurer interface {
	Name() string
	Ensure(ctx context.Context, state *State) error
}
EOF
```

### 2.2 Os ensurers

`CreateOrUpdate` lê o objeto, aplica a função e só escreve se algo mudou. A função define **apenas os campos que
são nossos**: sobrescrever `Spec` inteiro apagaria o que o API Server preencheu, como o `clusterIP` do Service.

`SetControllerReference` grava a owner reference: é ela que faz o Kubernetes apagar os filhos junto com o CR, e é
por ela que o `Owns()` sabe de quem é o evento.

```bash
cat > internal/controller/ensurers.go <<'EOF'
package controller

import (
	"context"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/util/intstr"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

func labelsFor(name string) map[string]string {
	return map[string]string{"app.kubernetes.io/name": "sampleapp", "app.kubernetes.io/instance": name}
}

// DeploymentEnsurer garante o Deployment e o publica no State.
type DeploymentEnsurer struct {
	Client client.Client
	Scheme *runtime.Scheme
}

func (e *DeploymentEnsurer) Name() string { return "deployment" }

func (e *DeploymentEnsurer) Ensure(ctx context.Context, state *State) error {
	app := state.App
	deploy := &appsv1.Deployment{ObjectMeta: metav1.ObjectMeta{Name: app.Name, Namespace: app.Namespace}}

	op, err := ctrl.CreateOrUpdate(ctx, e.Client, deploy, func() error {
		labels := labelsFor(app.Name)
		replicas := app.Spec.Replicas
		deploy.Spec.Replicas = &replicas
		deploy.Spec.Selector = &metav1.LabelSelector{MatchLabels: labels}
		deploy.Spec.Template.Labels = labels
		if len(deploy.Spec.Template.Spec.Containers) == 0 {
			deploy.Spec.Template.Spec.Containers = make([]corev1.Container, 1)
		}
		container := &deploy.Spec.Template.Spec.Containers[0]
		container.Name = "sampleapp"
		container.Image = app.Spec.Image
		container.Ports = []corev1.ContainerPort{{ContainerPort: app.Spec.Port, Protocol: corev1.ProtocolTCP}}
		return ctrl.SetControllerReference(app, deploy, e.Scheme)
	})
	if err != nil {
		return err
	}

	ctrl.LoggerFrom(ctx).Info("deployment garantido", "operation", op)
	state.Deployment = deploy
	return nil
}

// ServiceEnsurer garante o Service NodePort.
type ServiceEnsurer struct {
	Client client.Client
	Scheme *runtime.Scheme
}

func (e *ServiceEnsurer) Name() string { return "service" }

func (e *ServiceEnsurer) Ensure(ctx context.Context, state *State) error {
	app := state.App
	svc := &corev1.Service{ObjectMeta: metav1.ObjectMeta{Name: app.Name, Namespace: app.Namespace}}

	op, err := ctrl.CreateOrUpdate(ctx, e.Client, svc, func() error {
		svc.Spec.Type = corev1.ServiceTypeNodePort
		svc.Spec.Selector = labelsFor(app.Name)
		svc.Spec.Ports = []corev1.ServicePort{{
			Port:       app.Spec.Port,
			TargetPort: intstr.FromInt32(app.Spec.Port),
			NodePort:   app.Spec.NodePort,
			Protocol:   corev1.ProtocolTCP,
		}}
		return ctrl.SetControllerReference(app, svc, e.Scheme)
	})
	if err != nil {
		return err
	}

	ctrl.LoggerFrom(ctx).Info("service garantido", "operation", op)
	return nil
}

const (
	conditionReady = "Ready"

	reasonAvailable      = "AllReplicasAvailable"
	reasonProgressing    = "Progressing"
	reasonReconcileError = "ReconcileError"
)

// StatusEnsurer é o nó terminal: roda sempre, mesmo com a chain interrompida, e é
// o único que escreve o status. Uma escrita só por reconcile.
type StatusEnsurer struct {
	Client client.Client
}

func (e *StatusEnsurer) Name() string { return "status" }

func (e *StatusEnsurer) Ensure(ctx context.Context, state *State) error {
	app := state.App
	base := app.DeepCopy()

	condition := metav1.Condition{
		Type:               conditionReady,
		ObservedGeneration: app.Generation,
	}
	switch {
	case state.Err != nil:
		condition.Status = metav1.ConditionFalse
		condition.Reason = reasonReconcileError
		condition.Message = state.Err.Error()
	case state.Deployment.Status.AvailableReplicas == app.Spec.Replicas:
		condition.Status = metav1.ConditionTrue
		condition.Reason = reasonAvailable
		condition.Message = "todas as réplicas disponíveis"
	default:
		condition.Status = metav1.ConditionFalse
		condition.Reason = reasonProgressing
		condition.Message = "aguardando as réplicas do Deployment"
	}

	if state.Deployment != nil {
		app.Status.AvailableReplicas = state.Deployment.Status.AvailableReplicas
	}
	meta.SetStatusCondition(&app.Status.Conditions, condition)

	return e.Client.Status().Patch(ctx, app, client.MergeFrom(base))
}

var (
	_ Ensurer = &DeploymentEnsurer{}
	_ Ensurer = &ServiceEnsurer{}
	_ Ensurer = &StatusEnsurer{}
)
EOF
```

### 2.3 O Reconcile

O `Reconcile` fica pequeno: busca o CR, roda a chain, publica o status. Ele não recebe qual evento aconteceu, só o
nome do objeto. É isso que significa **level-triggered**: a cada passada ele olha o mundo inteiro e corrige, então
tanto faz o que causou a passada.

`Owns()` é o que traz o drift: mudou ou sumiu um Deployment ou Service nosso, o dono entra na fila.

```bash
cat > internal/controller/sampleapp_controller.go <<'EOF'
package controller

import (
	"context"
	"errors"
	"fmt"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"

	appsv1alpha1 "github.com/cloud104/sampleapp-operator/api/v1alpha1"
)

// SampleAppReconciler reconcilia um SampleApp.
type SampleAppReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=apps.cloud104.com,resources=sampleapps,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=apps.cloud104.com,resources=sampleapps/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=apps.cloud104.com,resources=sampleapps/finalizers,verbs=update
// +kubebuilder:rbac:groups=apps,resources=deployments,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups="",resources=services,verbs=get;list;watch;create;update;patch;delete

// chain define a ordem dos ensurers. O StatusEnsurer fica de fora: roda sempre.
func (r *SampleAppReconciler) chain() []Ensurer {
	return []Ensurer{
		&DeploymentEnsurer{Client: r.Client, Scheme: r.Scheme},
		&ServiceEnsurer{Client: r.Client, Scheme: r.Scheme},
	}
}

// Reconcile aproxima o cluster do estado pedido no SampleApp.
func (r *SampleAppReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	log := ctrl.LoggerFrom(ctx)

	app := &appsv1alpha1.SampleApp{}
	if err := r.Get(ctx, req.NamespacedName, app); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}
	if !app.DeletionTimestamp.IsZero() {
		return ctrl.Result{}, nil
	}

	state := &State{App: app}
	for _, ensurer := range r.chain() {
		if err := ensurer.Ensure(ctx, state); err != nil {
			state.Err = fmt.Errorf("%s: %w", ensurer.Name(), err)
			break
		}
	}

	status := &StatusEnsurer{Client: r.Client}
	if err := errors.Join(state.Err, status.Ensure(ctx, state)); err != nil {
		return ctrl.Result{}, err
	}

	log.Info("reconcile concluído", "available", app.Status.AvailableReplicas)
	return ctrl.Result{}, nil
}

// SetupWithManager registra o controller e o que ele observa.
func (r *SampleAppReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&appsv1alpha1.SampleApp{}).
		Owns(&appsv1.Deployment{}).
		Owns(&corev1.Service{}).
		Named("sampleapp").
		Complete(r)
}
EOF
make manifests generate fmt vet
```

### 2.4 Ver funcionando

Rode o manager num **segundo terminal** e deixe o log à vista:

```bash
export KUBECONFIG="$HOME/.kube/k8s-operators-lab-config"
cd "$LAB"     # use o mesmo valor do primeiro terminal
make run
```

De volta ao primeiro terminal, crie o CR:

```bash
kubectl apply -f config/samples/apps_v1alpha1_sampleapp.yaml
kubectl wait sampleapp/sampleapp-example --for=condition=Ready --timeout=120s
kubectl get sampleapp,deployment,service
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:30000/
```

Saída esperada: `READY True`, o Deployment `1/1`, o Service `NodePort` em `5000:30000/TCP`, e `200`.

As conditions e a owner reference:

```bash
kubectl get sampleapp sampleapp-example -o jsonpath='{range .status.conditions[*]}{.type}={.status} ({.reason}): {.message}{"\n"}{end}'
kubectl get deployment sampleapp-example -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}{"\n"}'
```

Saída esperada:

```text
Ready=True (AllReplicasAvailable): todas as réplicas disponíveis
SampleApp/sampleapp-example
```

### 2.5 Drift: apagar um filho

Com o log do manager à vista, apague o Service. Ele volta sozinho, e o log mostra `service garantido` com
`operation: created`.

```bash
kubectl delete service sampleapp-example
kubectl wait service/sampleapp-example --for=jsonpath='{.spec.type}'=NodePort --timeout=30s
kubectl get service sampleapp-example
```

Mexer à mão também não dura. Mude as réplicas direto no Deployment e veja o valor voltar para o do CR:

```bash
kubectl scale deployment sampleapp-example --replicas=4
kubectl wait deployment/sampleapp-example --for=jsonpath='{.spec.replicas}'=1 --timeout=30s
```

### 2.6 Mudar o desejado

```bash
kubectl patch sampleapp sampleapp-example --type=merge -p '{"spec":{"replicas":3}}'
kubectl wait sampleapp/sampleapp-example --for=condition=Ready=False --timeout=30s || true
kubectl get sampleapp sampleapp-example
kubectl wait sampleapp/sampleapp-example --for=jsonpath='{.status.availableReplicas}'=3 --timeout=120s
kubectl wait sampleapp/sampleapp-example --for=condition=Ready --timeout=30s
kubectl get sampleapp sampleapp-example
```

Saída esperada: `READY False` durante a subida e, no fim, `AVAILABLE 3` com `READY True`.

### 2.7 Apagar o CR

Não há código de deleção: a owner reference basta. Finalizer só é necessário quando há limpeza **fora** do cluster
(ver [padrões avançados](extras/advanced-operator-patterns.md)).

```bash
kubectl delete sampleapp sampleapp-example
kubectl wait deployment/sampleapp-example --for=delete --timeout=60s
kubectl wait service/sampleapp-example --for=delete --timeout=60s
kubectl get sampleapp,deployment,service
```

Saída esperada: `No resources found`. Pare o `make run` (Ctrl+C) antes do próximo lab.

## Lab 3: envtest e Tilt

### 3.1 Um teste com envtest

O envtest sobe um `kube-apiserver` e um `etcd` de verdade, sem kubelet nem controllers. Serve para testar CRD, CEL e
o `Reconcile`, chamado à mão. Como não há controller de Deployment, o teste escreve o status que ele escreveria.

```bash
cat > internal/controller/sampleapp_controller_test.go <<'EOF'
package controller

import (
	"context"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"

	appsv1alpha1 "github.com/cloud104/sampleapp-operator/api/v1alpha1"
)

var _ = Describe("SampleApp Controller", Ordered, func() {
	ctx := context.Background()
	key := types.NamespacedName{Name: "exemplo", Namespace: "default"}

	reconcileOnce := func() {
		r := &SampleAppReconciler{Client: k8sClient, Scheme: k8sClient.Scheme()}
		_, err := r.Reconcile(ctx, reconcile.Request{NamespacedName: key})
		Expect(err).NotTo(HaveOccurred())
	}

	readyCondition := func() *metav1.Condition {
		app := &appsv1alpha1.SampleApp{}
		Expect(k8sClient.Get(ctx, key, app)).To(Succeed())
		return meta.FindStatusCondition(app.Status.Conditions, conditionReady)
	}

	It("recusa pelo CEL uma imagem latest", func() {
		app := &appsv1alpha1.SampleApp{
			ObjectMeta: metav1.ObjectMeta{Name: "invalido", Namespace: key.Namespace},
			Spec:       appsv1alpha1.SampleAppSpec{Image: "nginx:latest"},
		}
		err := k8sClient.Create(ctx, app)
		Expect(apierrors.IsInvalid(err)).To(BeTrue())
		Expect(err.Error()).To(ContainSubstring("tag fixa"))
	})

	It("cria os filhos com owner reference e publica Progressing", func() {
		app := &appsv1alpha1.SampleApp{
			ObjectMeta: metav1.ObjectMeta{Name: key.Name, Namespace: key.Namespace},
			Spec:       appsv1alpha1.SampleAppSpec{Image: "nginx:1.27", Port: 8080, Replicas: 1, NodePort: 30001},
		}
		Expect(k8sClient.Create(ctx, app)).To(Succeed())

		reconcileOnce()

		deploy := &appsv1.Deployment{}
		Expect(k8sClient.Get(ctx, key, deploy)).To(Succeed())
		Expect(metav1.IsControlledBy(deploy, app)).To(BeTrue())
		Expect(k8sClient.Get(ctx, key, &corev1.Service{})).To(Succeed())

		condition := readyCondition()
		Expect(condition.Status).To(Equal(metav1.ConditionFalse))
		Expect(condition.Reason).To(Equal(reasonProgressing))
	})

	It("recria um filho apagado", func() {
		svc := &corev1.Service{}
		Expect(k8sClient.Get(ctx, key, svc)).To(Succeed())
		Expect(k8sClient.Delete(ctx, svc)).To(Succeed())

		reconcileOnce()

		Expect(k8sClient.Get(ctx, key, &corev1.Service{})).To(Succeed())
	})

	It("propaga a mudança de replicas", func() {
		app := &appsv1alpha1.SampleApp{}
		Expect(k8sClient.Get(ctx, key, app)).To(Succeed())
		app.Spec.Replicas = 3
		Expect(k8sClient.Update(ctx, app)).To(Succeed())

		reconcileOnce()

		deploy := &appsv1.Deployment{}
		Expect(k8sClient.Get(ctx, key, deploy)).To(Succeed())
		Expect(*deploy.Spec.Replicas).To(Equal(int32(3)))
	})

	It("publica Ready quando as réplicas ficam disponíveis", func() {
		deploy := &appsv1.Deployment{}
		Expect(k8sClient.Get(ctx, key, deploy)).To(Succeed())
		deploy.Status.Replicas = 3
		deploy.Status.ReadyReplicas = 3
		deploy.Status.AvailableReplicas = 3
		Expect(k8sClient.Status().Update(ctx, deploy)).To(Succeed())

		reconcileOnce()

		Expect(readyCondition().Status).To(Equal(metav1.ConditionTrue))
	})
})
EOF
make test
```

Saída esperada: `ok  github.com/cloud104/sampleapp-operator/internal/controller`. A primeira execução baixa os
binários do envtest para `bin/k8s/`.

### 3.2 Tilt

Até aqui o manager rodou na sua máquina. O Tilt roda dentro do cluster e refaz o ciclo a cada alteração: recompila,
gera a imagem, carrega no node e troca o pod.

```bash
"$TREINAMENTO/scripts/kubebuilder-tilt-setup.sh"
tilt up --stream
```

Aguarde `sampleapp-operator-controller-manager` subir. Painel em <http://localhost:10350>.

Num segundo terminal, com o mesmo `KUBECONFIG` e em `$LAB`, crie o CR:

```bash
kubectl apply -f config/samples/apps_v1alpha1_sampleapp.yaml
kubectl wait sampleapp/sampleapp-example --for=condition=Ready --timeout=120s
```

Edite o controller e veja o Tilt recompilar, gerar a imagem e trocar o pod. Ao subir, o manager novo reconcilia todos
os CRs, então a linha nova aparece sozinha no log:

```bash
sed -i 's/"reconcile concluído"/"reconcile concluído pelo Tilt"/' internal/controller/sampleapp_controller.go
time timeout 120 bash -c 'until kubectl logs -n sampleapp-operator-system -l control-plane=controller-manager --tail=-1 | grep "reconcile concluído pelo Tilt"; do sleep 2; done'
```

Saída esperada: uma linha de log com `reconcile concluído pelo Tilt`.

## Limpeza

Pare o `tilt up` (Ctrl+C) e, de qualquer terminal:

```bash
kind delete cluster --name k8s-operators-lab
rm -f "$KUBECONFIG"
```

## Se der errado

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| `no matches for kind "SampleApp"` | CRD não instalada | `make install` |
| `make run` falha com `address already in use` | outro manager, ou algo na `:8081` | pare o outro, ou `go run ./cmd/main.go --health-probe-bind-address=:18081` |
| Dois managers disputando o mesmo CR | `make run` e Tilt juntos | fique com um só |
| `curl` em `localhost:30000` sem resposta | pod ainda subindo | `kubectl get pods`, depois `kubectl logs` |
| Tilt recusa o contexto | `KUBECONFIG` não exportado neste terminal | exporte e confira `kubectl config current-context` |

Para ir além: [padrões avançados](extras/advanced-operator-patterns.md) (finalizer, rollout ordenado),
[predicates](extras/predicates-kubebuilder.md), [CreateOrUpdate](extras/kubernetes-create-or-update.md).
