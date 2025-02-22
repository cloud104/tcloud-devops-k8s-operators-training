# Padrões Avançados de Design para Kubernetes Operators

## 1. Padrões de Reconciliação

### Level Triggers vs Edge Triggers

```mermaid
flowchart TD
    subgraph LT ["Level Triggered"]
        L1[Controller] -->|"Reconcilia"| L2[Estado Atual]
        L2 -->|"Compara"| L3[Estado Desejado]
        L3 -->|"RequeueAfter"| L1
    end
    
    subgraph ET ["Edge Triggered"]
        E1[Watch] -->|"Evento"| E2[Controller]
        E2 -->|"Reconcilia"| E3[Estado]
        E3 -.->|"Aguarda próximo evento"| E1
    end
    
    style LT fill:#f0f0f0,stroke:#333,stroke-width:2px
    style ET fill:#e6f3ff,stroke:#333,stroke-width:2px
```

#### Level Triggered (Gatilho por Nível)

- **Funcionamento**: Reconciliação constante e periódica
- **Vantagens**:
  - Maior resiliência
  - Recuperação automática
  - Alta disponibilidade

```go
// Implementação Level Triggered
return ctrl.Result{RequeueAfter: time.Minute * 5}, nil
```

#### Edge Triggered (Gatilho por Evento)

- **Funcionamento**: Reconciliação baseada em eventos
- **Vantagens**:
  - Eficiência computacional
  - Menor latência
  - Menor carga no API Server

```go
// Implementação Edge Triggered
func (r *Reconciler) SetupWithManager(mgr ctrl.Manager) error {
    return ctrl.NewControllerManagedBy(mgr).
        For(&myappv1.MyApp{}).
        Watches(
            &source.Kind{Type: &corev1.Secret{}},
            handler.EnqueueRequestsFromMapFunc(r.findAppsForSecret),
        ).
        Complete(r)
}
```

## 2. Gerenciamento de Recursos

### Owner References

```mermaid
flowchart TD
    subgraph OWN ["Hierarquia de Recursos"]
        CR["Custom Resource
        Database"] -->|"owner"| D["Deployment"]
        CR -->|"owner"| S["Service"]
        CR -->|"owner"| C["ConfigMap"]
        
        D -->|"owner"| P1["Pod 1"]
        D -->|"owner"| P2["Pod 2"]
        D -->|"owner"| P3["Pod 3"]
    end
    
    style OWN fill:#f0f0f0,stroke:#333,stroke-width:2px
    style CR fill:#ffccff,stroke:#cc66ff
    style D,S,C fill:#ccccff,stroke:#6666ff
    style P1,P2,P3 fill:#ccffcc,stroke:#00cc00
```

#### Implementação

```yaml
apiVersion: v1
kind: Pod
metadata:
  ownerReferences:
    - apiVersion: databases.example.com/v1
      kind: Database
      name: prod-db
      uid: d9607e19-f88f-11e6-a518-42010a800195
      controller: true
      blockOwnerDeletion: true
```

### Finalizers

```mermaid
sequenceDiagram
    actor User
    participant API as API Server
    participant CR as Custom Resource
    participant Op as Operator
    participant Res as External Resource

    User->>API: kubectl delete
    API->>CR: Marca para deleção
    CR->>Op: Detecta deletionTimestamp
    Op->>Res: Limpa recursos externos
    Op->>CR: Remove finalizer
    CR->>API: Permite deleção
    API->>CR: Remove recurso
```

#### Ciclo de Vida

1. Adição do Finalizer
2. Solicitação de Exclusão
3. Bloqueio da Exclusão
4. Execução da Limpeza
5. Remoção do Finalizer
6. Exclusão Efetiva

## 3. Status e Condições

### Status Subresource

```mermaid
flowchart LR
    subgraph CR ["Custom Resource"]
        SPEC["Spec
        Estado Desejado"]
        STATUS["Status
        Estado Atual"]
        COND["Conditions
        Available
        Healthy
        Progressing"]
    end
    
    subgraph CTRL ["Controller"]
        WATCH["Watch"]
        RECONCILE["Reconcile"]
        UPDATE["Status Update"]
    end
    
    WATCH -->|"Detecta mudanças"| RECONCILE
    RECONCILE -->|"Atualiza"| STATUS
    RECONCILE -->|"Atualiza"| COND
    
    style CR fill:#f0f0f0,stroke:#333,stroke-width:2px
    style CTRL fill:#e6f3ff,stroke:#333,stroke-width:2px
```

#### Exemplo de Status

```yaml
status:
  phase: Provisioning
  observedGeneration: 12
  conditions:
    - type: Available
      status: "False"
      reason: Creating
      message: "Criando recursos"
```

## 4. Padrões de Backup e Recuperação

```mermaid
flowchart TD
    subgraph BACKUP ["Sistema de Backup"]
        SCHED["Scheduler"] -->|"Agenda"| JOB["Backup Job"]
        JOB -->|"Cria"| SNAP["Snapshot"]
        SNAP -->|"Armazena"| STORE["Object Storage"]
        
        REST["Restore Job"] -->|"Recupera"| SNAP
        REST -->|"Restaura"| DB["Database"]
    end
    
    style BACKUP fill:#f0f0f0,stroke:#333,stroke-width:2px
    style SCHED fill:#ffccff,stroke:#cc66ff
    style JOB,REST fill:#ccccff,stroke:#6666ff
    style SNAP,STORE fill:#ccffcc,stroke:#00cc00
    style DB fill:#ffffcc,stroke:#cccc00
```

## 5. Monitoramento e Observabilidade

### Métricas e Logs

```mermaid
flowchart LR
    subgraph OBS ["Observabilidade"]
        LOG["Logs Estruturados"]
        MET["Métricas Prometheus"]
        EVT["Events"]
        
        CTRL["Controller"] -->|"Gera"| LOG
        CTRL -->|"Expõe"| MET
        CTRL -->|"Emite"| EVT
    end
    
    style OBS fill:#f0f0f0,stroke:#333,stroke-width:2px
    style LOG,MET,EVT fill:#ccccff,stroke:#6666ff
    style CTRL fill:#ffccff,stroke:#cc66ff
```

#### Exemplo de Métricas

```go
var (
    reconcileTotal = prometheus.NewCounterVec(
        prometheus.CounterOpts{
            Name: "controller_reconcile_total",
            Help: "Total de reconciliações",
        },
        []string{"result"},
    )
)
```

## 6. Deployment Strategies

### Blue-Green Deployment

```mermaid
flowchart LR
    subgraph BG ["Blue-Green Deployment"]
        BLUE["Blue Environment"]
        GREEN["Green Environment"]
        LB["Load Balancer"]
        
        LB -->|"Traffic"| BLUE
        LB -.->|"Switch"| GREEN
    end
    
    style BG fill:#f0f0f0,stroke:#333,stroke-width:2px
    style BLUE fill:#ccccff,stroke:#6666ff
    style GREEN fill:#ccffcc,stroke:#00cc00
    style LB fill:#ffffcc,stroke:#cccc00
```

## 7. Multi-cluster Management

```mermaid
flowchart TD
    subgraph CENTRAL ["Control Plane Central"]
        CTRL["Central Controller"]
        SYNC["Sync Manager"]
    end
    
    subgraph C1 ["Cluster 1"]
        A1["Agent"]
        R1["Resources"]
    end
    
    subgraph C2 ["Cluster 2"]
        A2["Agent"]
        R2["Resources"]
    end
    
    CTRL -->|"Gerencia"| A1 & A2
    SYNC -->|"Sincroniza"| R1 & R2
    
    style CENTRAL fill:#f0f0f0,stroke:#333,stroke-width:2px
    style C1,C2 fill:#e6f3ff,stroke:#333,stroke-width:2px
```

## Boas Práticas

1. **Idempotência**
   - Operações devem ser seguras para repetição
   - Use CreateOrUpdate consistentemente
   - Verifique estados antes de modificar

2. **Segurança**
   - RBAC com princípio do menor privilégio
   - Secrets gerenciados adequadamente
   - Network Policies restritivas

3. **Escalabilidade**
   - Cache eficiente
   - Rate limiting
   - Backoff em retentativas

4. **Observabilidade**
   - Logs estruturados
   - Métricas relevantes
   - Events informativos

Estas práticas garantem Operators robustos, seguros e manteníveis.
