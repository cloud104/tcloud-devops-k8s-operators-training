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
    
    style KB fill:#f0f0f0,stroke:#333,stroke-width:2px
    style OUT fill:#e6f3ff,stroke:#333,stroke-width:2px
    style CLI,SCAF,TEST fill:#ffcccc,stroke:#333
    style CRD,CTRL,RBAC,WEBB fill:#ccffcc,stroke:#333
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
    
    style MGR fill:#f0f0f0,stroke:#333,stroke-width:2px
    style CTRL,WH fill:#e6f3ff,stroke:#333,stroke-width:2px
    style CACHE,CLIENT,SCHEME fill:#ffcccc,stroke:#333
    style METRICS,HEALTH fill:#ccffcc,stroke:#333
    style C1,C2,CN fill:#cce5ff,stroke:#333
    style V,M,C fill:#ffe5cc,stroke:#333
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
    
    style CTRL fill:#f0f0f0,stroke:#333,stroke-width:2px
    style INF fill:#e6f3ff,stroke:#333,stroke-width:2px
    style PRED,QUEUE,REC fill:#ffcccc,stroke:#333
    style WATCH,CACHE,HAND fill:#ccffcc,stroke:#333
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
├── controllers/           # Implementação dos controllers
├── webhooks/             # Webhooks (opcional)
├── main.go               # Ponto de entrada
└── Makefile             # Automação de build/deploy
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
// controllers/myapp_controller.go
func (r *MyAppReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
    log := r.Log.WithValues("myapp", req.NamespacedName)
    
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
            &source.Kind{Type: &corev1.Secret{}},
            handler.EnqueueRequestsFromMapFunc(r.findObjectsForSecret),
        ).
        WithEventFilter(predicate.GenerationChangedPredicate{}). // Filtros
        Complete(r)
}
```

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
    
    style WH fill:#f0f0f0,stroke:#333,stroke-width:2px
    style V,M,C fill:#ffcccc,stroke:#333
```

### Implementação

```go
// Webhook de Validação
func (r *MyApp) ValidateCreate() error {
    // Lógica de validação
    return nil
}

// Webhook de Mutação
func (r *MyApp) Default() {
    // Lógica de valores default
}
```

## Testes

O Kubebuilder fornece um framework de testes integrado:

```go
// controllers/myapp_controller_test.go
func TestMyAppController(t *testing.T) {
    g := gomega.NewGomegaWithT(t)

    // Setup do ambiente de teste
    ctx := context.Background()
    mgr, err := ctrl.NewManager(cfg, ctrl.Options{Scheme: scheme.Scheme})
    g.Expect(err).NotTo(gomega.HaveOccurred())

    // Testes
    myApp := &myappv1alpha1.MyApp{
        ObjectMeta: metav1.ObjectMeta{
            Name:      "test-app",
            Namespace: "default",
        },
        Spec: myappv1alpha1.MyAppSpec{
            Replicas: pointer.Int32Ptr(3),
        },
    }

    // Criar recurso
    g.Expect(k8sClient.Create(ctx, myApp)).To(gomega.Succeed())

    // Verificar reconciliação
    // ...
}
```

## Boas Práticas

1. **Gerenciamento de Erros**
   - Use `Result{Requeue: true}` para retry
   - Implemente backoff adequado
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

## Conclusão

O Kubebuilder proporciona uma estrutura robusta para desenvolver Operators Kubernetes, com:

- Geração automática de código e manifests
- Padrões estabelecidos de implementação
- Ferramentas de teste integradas
- Suporte a webhooks e validação
- Gerenciamento eficiente de recursos através de informers compartilhados
