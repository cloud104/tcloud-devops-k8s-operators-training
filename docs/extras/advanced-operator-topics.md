# Tópicos Avançados em Kubernetes Operators

## 1. Admission Controllers em Operators

Admission Controllers permitem validar e/ou modificar requisições ao Kubernetes antes que sejam persistidas.

```mermaid
flowchart LR
    subgraph AC["Admission Controls"]
        VAL["Validating Webhook"]
        MUT["Mutating Webhook"]
    end
    
    API["API Server"] -->|Request| MUT
    MUT -->|Mutation| VAL
    VAL -->|Validation| API
    
    classDef default fill:#f0f0f0,stroke:#333,stroke-width:2px
    classDef webhook fill:#ccffcc,stroke:#333
    
    class AC default
    class VAL,MUT webhook
```

### Implementação

```go
// Webhook de Validação
func (v *Validator) Handle(ctx context.Context, req admission.Request) admission.Response {
    obj := &myappv1.MyApp{}
    if err := v.decoder.Decode(req, obj); err != nil {
        return admission.Errored(http.StatusBadRequest, err)
    }
    
    // Lógica de validação
    if obj.Spec.Replicas < 1 {
        return admission.Denied("replicas must be >= 1")
    }
    
    return admission.Allowed("")
}
```

## 2. Padrões de Migração de Versão

### Estratégias de Conversão

```mermaid
flowchart TD
    subgraph VER ["Versões da API"]
        V1A["v1alpha1"]
        V1B["v1beta1"]
        V1["v1"]
        
        V1A -->|"Conversão"| V1B
        V1B -->|"Conversão"| V1
    end
    
    subgraph COMP ["Compatibilidade"]
        STORE["Storage Version"]
        SERVED["Served Versions"]
    end
    
    V1A & V1B & V1 --> SERVED
    V1 --> STORE
    
    style VER fill:#f0f0f0,stroke:#333,stroke-width:2px
    style COMP fill:#e6f3ff,stroke:#333,stroke-width:2px
```

### Exemplo de Webhook de Conversão

```go
func (c *Converter) Convert(ctx context.Context, obj runtime.Object) (runtime.Object, error) {
    switch obj := obj.(type) {
    case *v1alpha1.MyApp:
        return convertV1alpha1ToV1beta1(obj), nil
    case *v1beta1.MyApp:
        return convertV1beta1ToV1(obj), nil
    default:
        return nil, fmt.Errorf("unsupported type")
    }
}
```

## 3. Gestão de Dependências

```mermaid
flowchart TD
    subgraph DEP["Gestão de Dependências"]
        DB["Database CR"]
        SVC["Service CR"]
        SEC["Secret CR"]
        
        subgraph ORDER["Ordem de Criação"]
            O1["Secret"]
            O2["Service"]
            O3["Database"]
        end
        
        DB -->|requer| SVC
        SVC -->|requer| SEC
        
        O1 -.-> O2 -.-> O3
    end
    
    classDef default fill:#f0f0f0,stroke:#333,stroke-width:2px
    classDef resources fill:#ccffcc,stroke:#333
    classDef order fill:#e6f3ff,stroke:#333
    
    class DEP default
    class DB,SVC,SEC resources
    class ORDER,O1,O2,O3 order
```

### Implementação de Dependências

```go
func (r *Reconciler) ensureDependencies(ctx context.Context, obj *myappv1.MyApp) error {
    // 1. Garantir Secret
    secret := &corev1.Secret{}
    if err := r.ensureSecret(ctx, obj, secret); err != nil {
        return fmt.Errorf("ensuring secret: %w", err)
    }
    
    // 2. Garantir Service
    svc := &corev1.Service{}
    if err := r.ensureService(ctx, obj, svc); err != nil {
        return fmt.Errorf("ensuring service: %w", err)
    }
    
    // 3. Configurar Database
    return nil
}
```

## 4. Alta Disponibilidade

### Leader Election

```mermaid
flowchart LR
    subgraph LE ["Leader Election"]
        L1["Pod 1 (Leader)"]
        L2["Pod 2 (Standby)"]
        L3["Pod 3 (Standby)"]
        
        LOCK["Lock Resource"]
        
        L1 -->|"mantém"| LOCK
        L2 -.->|"monitora"| LOCK
        L3 -.->|"monitora"| LOCK
    end
    
    style LE fill:#f0f0f0,stroke:#333,stroke-width:2px
    style L1 fill:#ccffcc,stroke:#333
    style L2,L3 fill:#ffcccc,stroke:#333
```

### Implementação

```go
func main() {
    mgr, err := ctrl.NewManager(ctrl.GetConfigOrDie(), ctrl.Options{
        LeaderElection:          true,
        LeaderElectionID:        "myapp-operator",
        LeaderElectionNamespace: "default",
    })
    // ...
}
```

## 5. Rate Limiting e Backoff

### Estratégias de Rate Limiting

```mermaid
flowchart TD
    subgraph RL ["Rate Limiting"]
        Q["Work Queue"]
        RL1["Rate Limiter"]
        BK["Backoff"]
        
        Q -->|"controla"| RL1
        RL1 -->|"aplica"| BK
    end
    
    subgraph POL ["Políticas"]
        P1["Token Bucket"]
        P2["Leaky Bucket"]
        P3["Fixed Window"]
    end
    
    POL -->|"implementa"| RL1
    
    style RL fill:#f0f0f0,stroke:#333,stroke-width:2px
    style POL fill:#e6f3ff,stroke:#333,stroke-width:2px
```

### Implementação

```go
// Configuração de Rate Limiting
workqueue.NewRateLimitingQueue(workqueue.NewMaxOfRateLimiter(
    workqueue.NewItemExponentialFailureRateLimiter(5*time.Millisecond, 1000*time.Second),
    &workqueue.BucketRateLimiter{Limiter: rate.NewLimiter(rate.Limit(10), 100)},
))
```

## 6. Métricas e Monitoramento

### Arquitetura de Observabilidade

```mermaid
flowchart LR
    subgraph OBS ["Observabilidade"]
        M["Métricas"]
        L["Logs"]
        T["Traces"]
        
        PROM["Prometheus"]
        GRAF["Grafana"]
        
        M --> PROM
        PROM --> GRAF
    end
    
    subgraph ALERT ["Alerting"]
        AM["AlertManager"]
        RUL["Rules"]
    end
    
    PROM -->|"gera"| AM
    
    style OBS fill:#f0f0f0,stroke:#333,stroke-width:2px
    style ALERT fill:#e6f3ff,stroke:#333,stroke-width:2px
```

### Métricas Customizadas

```go
var (
    reconcileTotal = prometheus.NewCounterVec(
        prometheus.CounterOpts{
            Name: "myapp_reconcile_total",
            Help: "Total number of reconciliations per status",
        },
        []string{"status"},
    )
    
    reconcileDuration = prometheus.NewHistogramVec(
        prometheus.HistogramOpts{
            Name:    "myapp_reconcile_duration_seconds",
            Help:    "Time spent doing reconciliations",
            Buckets: prometheus.DefBuckets,
        },
        []string{"status"},
    )
)
```

## 7. Multi-tenancy

### Arquitetura Multi-tenant

```mermaid
flowchart TD
    subgraph MT ["Multi-tenancy"]
        subgraph T1 ["Tenant 1"]
            N1["Namespace"]
            R1["Resource Quotas"]
            NP1["Network Policies"]
        end
        
        subgraph T2 ["Tenant 2"]
            N2["Namespace"]
            R2["Resource Quotas"]
            NP2["Network Policies"]
        end
    end
    
    CTRL["Operator Controller"] -->|"gerencia"| MT
    
    style MT fill:#f0f0f0,stroke:#333,stroke-width:2px
    style T1,T2 fill:#e6f3ff,stroke:#333,stroke-width:2px
```

### Implementação

```go
// Configuração por Tenant
type TenantConfig struct {
    ResourceQuota corev1.ResourceQuota
    NetworkPolicy networkingv1.NetworkPolicy
    ServiceAccount corev1.ServiceAccount
}

func (r *Reconciler) reconcileTenant(ctx context.Context, tenant string) error {
    config := r.getTenantConfig(tenant)
    
    // Criar/atualizar recursos do tenant
    if err := r.reconcileResourceQuota(ctx, tenant, config.ResourceQuota); err != nil {
        return err
    }
    // ...
}
```

## 8. Patterns de Deployment

### Estratégias Avançadas

```mermaid
flowchart LR
    subgraph DEPLOY ["Deployment Strategies"]
        BG["Blue-Green"]
        CAN["Canary"]
        AB["A/B Testing"]
    end
    
    subgraph CTRL ["Controller"]
        TRAF["Traffic Control"]
        MON["Monitoring"]
        ROLL["Rollback Logic"]
    end
    
    DEPLOY -->|"implementa"| CTRL
    
    style DEPLOY fill:#f0f0f0,stroke:#333,stroke-width:2px
    style CTRL fill:#e6f3ff,stroke:#333,stroke-width:2px
```

## 9. Integração com Service Mesh

### Arquitetura com Service Mesh

```mermaid
flowchart TD
    subgraph SM ["Service Mesh"]
        PROXY["Sidecar Proxy"]
        CTRL["Mesh Control Plane"]
        POL["Traffic Policies"]
    end
    
    subgraph OP ["Operator"]
        RECON["Reconciler"]
        MESH["Mesh Config"]
    end
    
    OP -->|"configura"| SM
    
    style SM fill:#f0f0f0,stroke:#333,stroke-width:2px
    style OP fill:#e6f3ff,stroke:#333,stroke-width:2px
```

## 10. Extensibilidade

### Arquitetura Plugável

```mermaid
flowchart LR
    subgraph PLUG ["Sistema de Plugins"]
        CORE["Core Controller"]
        REG["Plugin Registry"]
        
        P1["Plugin 1"]
        P2["Plugin 2"]
        P3["Plugin 3"]
    end
    
    REG -->|"registra"| P1 & P2 & P3
    CORE -->|"usa"| REG
    
    style PLUG fill:#f0f0f0,stroke:#333,stroke-width:2px
```

### Implementação

```go
// Interface de Plugin
type Plugin interface {
    Name() string
    Init(ctx context.Context) error
    Reconcile(ctx context.Context, obj runtime.Object) error
}

// Registro de Plugins
type PluginRegistry struct {
    plugins map[string]Plugin
}

func (r *PluginRegistry) Register(p Plugin) {
    r.plugins[p.Name()] = p
}
```

## Conclusão

Estes tópicos avançados são cruciais para desenvolver Operators robustos e escaláveis. Cada aspecto requer consideração cuidadosa e implementação apropriada conforme os requisitos específicos do seu caso de uso.

Pontos-chave para lembrar:

1. Use Admission Controllers para validação e mutação
2. Planeje migrações de versão com antecedência
3. Gerencie dependências adequadamente
4. Implemente alta disponibilidade
5. Configure rate limiting e backoff
6. Monitore e colete métricas
7. Considere multi-tenancy desde o início
8. Use padrões de deployment apropriados
9. Integre com service mesh quando necessário
10. Mantenha o código extensível
