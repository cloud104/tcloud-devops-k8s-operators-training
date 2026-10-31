# Guia Completo do Kubebuilder

## O que é o Kubebuilder?

Kubebuilder é um framework para construir Kubernetes APIs e controllers usando CRDs (Custom Resource Definitions). Ele proporciona uma estrutura padronizada e ferramentas para desenvolver Operators de forma eficiente.

```mermaid
flowchart TD
    subgraph KB ["Kubebuilder"]
        CLI["CLI Tools"]
        SCAF["Scaffolding"]
        TEST["Test Framework"]
        
        CLI -->|gera| SCAF
        SCAF -->|inclui| TEST
    end
    
    subgraph OUT ["Artefatos Gerados"]
        CRD["Custom Resource Definitions"]
        CTRL["Controllers"]
        RBAC["RBAC Manifests"]
        WEBB["Webhooks"]
    end
    
    KB -->|produz| OUT
```

## Arquitetura do Manager

O Manager é o componente central em um projeto Kubebuilder. Ele gerencia controllers, webhooks e recursos compartilhados.

```mermaid
flowchart TD
    subgraph MGR ["Manager"]
        CACHE["Cache Compartilhado"]
        CLIENT["Client"]
        SCHEME["Scheme"]
        METRICS["Metrics Server"]
        HEALTH["Health Probe"]
        
        subgraph CTRL ["Controllers"]
            C1["Controller 1"]
            C2["Controller 2"]
            CN["Controller N"]
        end
        
        subgraph WH ["Webhooks"]
            V["Validation"]
            M["Mutation"]
            C["Conversion"]
        end
        
        CACHE --> C1 & C2 & CN
        CLIENT --> C1 & C2 & CN
        SCHEME --> CACHE
    end
    
    API["API Server"] -->|Watch/List| CACHE
```

## Fluxo de um Controller

Diagrama mostrando como um controller processa recursos:

```mermaid
flowchart TD
    subgraph CTRL ["Controller"]
        PRED["Predicates"]
        QUEUE["WorkQueue"]
        REC["Reconciler"]
        
        subgraph INF ["Informers"]
            WATCH["Watch"]
            CACHE["Local Cache"]
            HAND["Event Handlers"]
        end
        
        WATCH -->|eventos| PRED
        PRED -->|filtrados| HAND
        HAND -->|enfileira| QUEUE
        QUEUE -->|processa| REC
        REC -->|consulta| CACHE
    end
    
    API["API Server"] -->|Watch/List| WATCH
    REC -->|CRUD| API
```

## Setup Básico

### 1. Inicialização do Projeto

```bash
# Inicializar novo projeto
kubebuilder init --domain my.domain.com --repo my.domain.com/myproject

# Criar API
kubebuilder create api --group apps --version v1alpha1 --kind MyApp
```

### 2. Estrutura do Projeto

```bash
.
├── api/                    # Definições de API (CRDs)
├── config/                 # Configurações e manifests
├── cmd/main.go             # Ponto de entrada (manager)
├── internal/controller/    # Implementação dos controllers e suite do envtest
├── internal/webhook/       # Webhooks (opcional)
├── test/e2e/               # Testes e2e em kind
└── Makefile                # Automação de build/deploy
```

## Implementação do Controller

### 1. Definição da API (CRD)

```go
// api/v1alpha1/myapp_types.go
type MyAppSpec struct {
    // Campos da spec
    Replicas *int32 `json:"replicas,omitempty"`
}

type MyAppStatus struct {
    // Campos do status
    AvailableReplicas int32 `json:"availableReplicas"`
}
```

### 2. Reconciler

```go
// internal/controller/myapp_controller.go
func (r *MyAppReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
    // O scaffold v4 não tem mais o campo r.Log: o logger vem do contexto.
    log := logf.FromContext(ctx) // import "sigs.k8s.io/controller-runtime/pkg/log"
    
    // Carregar o CR
    var myApp myappv1alpha1.MyApp
    if err := r.Get(ctx, req.NamespacedName, &myApp); err != nil {
        return ctrl.Result{}, client.IgnoreNotFound(err)
    }
    
    // Lógica de reconciliação
    return ctrl.Result{}, nil
}
```

## Uso de Informers

O Kubebuilder utiliza SharedInformers através do Manager para eficiência:

```go
// Setup do Controller com Informers
func (r *MyAppReconciler) SetupWithManager(mgr ctrl.Manager) error {
    return ctrl.NewControllerManagedBy(mgr).
        For(&myappv1alpha1.MyApp{}).                // Principal recurso
        Owns(&appsv1.Deployment{}).                 // Recursos owned
        Watches(                                    // Recursos adicionais
            &corev1.Secret{},
            handler.EnqueueRequestsFromMapFunc(r.findObjectsForSecret),
        ).
        Complete(r)
}
```

Filtros (predicates) entram por recurso, com `builder.WithPredicates`. `WithEventFilter` vale para todos os watches:
com `GenerationChangedPredicate` ele também descartaria as mudanças de status dos Deployments, e o controller nunca
veria as réplicas ficarem disponíveis.

## Webhooks

### Tipos de Webhooks

```mermaid
flowchart LR
    subgraph WH ["Webhooks"]
        V["Validation
        Valida recursos"]
        M["Mutation
        Modifica recursos"]
        C["Conversion
        Converte versões"]
    end
    
    API["API Server"] -->|Request| WH
    WH -->|Response| API
```

### Implementação

No Kubebuilder v4 os webhooks não são métodos no tipo da API: o scaffold gera um validator e um defaulter em
`internal/webhook/<versão>/`, e o objeto chega **tipado** como parâmetro. O builder passou a ser genérico e recebe o
objeto; a validação devolve `admission.Warnings`:

```go
// internal/webhook/v1alpha1/myapp_webhook.go
func SetupMyAppWebhookWithManager(mgr ctrl.Manager) error {
    return ctrl.NewWebhookManagedBy(mgr, &myappv1alpha1.MyApp{}).
        WithValidator(&MyAppValidator{}).
        WithDefaulter(&MyAppDefaulter{}).
        Complete()
}

type MyAppValidator struct{}

// Objeto já tipado: sem type assertion.
func (v *MyAppValidator) ValidateCreate(ctx context.Context, obj *myappv1alpha1.MyApp) (admission.Warnings, error) {
    return nil, nil
}
// ValidateUpdate(ctx, oldObj, newObj) e ValidateDelete(ctx, obj) seguem o mesmo formato.

type MyAppDefaulter struct{}

func (d *MyAppDefaulter) Default(ctx context.Context, obj *myappv1alpha1.MyApp) error {
    return nil
}
```

Para regras simples de validação, prefira marcadores (`+kubebuilder:validation:...`) e **CEL** (`+kubebuilder:validation:XValidation`),
que rodam no API Server sem webhook. Webhook só quando a regra precisa consultar algo fora do objeto.

## Testes

O scaffold v4 gera testes com **Ginkgo v2 + Gomega** sobre **envtest**: um `etcd` e um `kube-apiserver` de verdade,
sem kubelet. O `suite_test.go` sobe o `testEnv` e expõe um `k8sClient`. No teste gerado, o `suite_test.go` **não** sobe
um manager; o `<kind>_controller_test.go` cria o CR e então chama o `Reconcile` do controller **à mão**, de forma
síncrona, e só depois verifica o resultado:

```go
// internal/controller/myapp_controller_test.go
var _ = Describe("MyApp controller", func() {
    It("cria o Deployment ao reconciliar", func(ctx SpecContext) {
        name := types.NamespacedName{Name: "test-app", Namespace: "default"}
        app := &myappv1alpha1.MyApp{
            ObjectMeta: metav1.ObjectMeta{Name: name.Name, Namespace: name.Namespace},
            Spec:       myappv1alpha1.MyAppSpec{Replicas: ptr.To(int32(3))},
        }
        Expect(k8sClient.Create(ctx, app)).To(Succeed())

        reconciler := &MyAppReconciler{Client: k8sClient, Scheme: k8sClient.Scheme()}
        _, err := reconciler.Reconcile(ctx, reconcile.Request{NamespacedName: name})
        Expect(err).NotTo(HaveOccurred())

        dep := &appsv1.Deployment{}
        Expect(k8sClient.Get(ctx, name, dep)).To(Succeed())
    })
})
```

Como não há kubelet, o Pod nunca fica `Running` sozinho: o teste escreve o `status` do Deployment à mão quando precisa
simular réplicas disponíveis. Se você preferir subir um manager no `BeforeSuite` (reconcile assíncrono), aí sim use
`Eventually` para esperar o estado convergir. A CEL (`XValidation`) roda de verdade no envtest, porque o API Server é
real.

## Boas Práticas

1. **Gerenciamento de Erros**
   - Devolva o erro: a fila refaz com backoff
   - Use `Result{RequeueAfter: d}` para esperar algo que não gera evento
   - Log estruturado para debugging

2. **Cache e Performance**
   - Use o cache compartilhado quando possível
   - Implemente filtros de eventos apropriados
   - Evite reconciliações desnecessárias

3. **Status Management**
   - Atualize status de forma consistente
   - Use conditions para refletir estados complexos
   - Mantenha observedGeneration atualizada

4. **RBAC**
   - Defina permissões mínimas necessárias
   - Use `+kubebuilder:rbac` markers
   - Valide permissões em testes

## Próximos passos

- Webhooks, conversão de versões, leader election e rate limiting: [Tópicos avançados](advanced-operator-topics.md).
- O lab aplica tudo isto num operator pequeno: [`03-desenvolvimento.md`](../03-desenvolvimento.md).
- Referência oficial: [Kubebuilder Book](https://book.kubebuilder.io/).
