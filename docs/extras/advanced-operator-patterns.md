# Padrões Avançados de Design para Kubernetes Operators

## 1. Padrões de Reconciliação

### Level Triggers vs Edge Triggers

Os dois termos descrevem **o que a lógica olha**, não com que frequência ela roda. Eventos disparam o reconcile nos
dois casos.

```mermaid
flowchart TD
    subgraph LT ["Level Triggered"]
        L1[Evento ou requeue] -->|"só o nome do objeto"| L2[Reconcile]
        L2 -->|"lê"| L3[Estado atual e desejado]
        L3 -->|"corrige a diferença"| L2
    end

    subgraph ET ["Edge Triggered"]
        E1[Evento] -->|"o que mudou"| E2[Handler]
        E2 -->|"reage àquela mudança"| E3[Ação]
        E3 -.->|"evento perdido = estado errado"| E1
    end
```

#### Level Triggered (o modelo do controller-runtime)

- **Funcionamento**: o `Reconcile` recebe só namespace e nome, lê o estado e corrige a diferença
- **Vantagens**:
  - Evento perdido ou repetido não importa: a próxima passada corrige
  - Eventos em rajada viram uma passada só, porque a fila deduplica por nome
  - Reiniciar o operator é seguro: ao subir, ele reconcilia tudo

`Owns()` e `Watches()` decidem **quando** acordar; o que o `Reconcile` faz não depende de qual evento foi.

```go
func (r *Reconciler) SetupWithManager(mgr ctrl.Manager) error {
    return ctrl.NewControllerManagedBy(mgr).
        For(&myappv1.MyApp{}).
        Owns(&appsv1.Deployment{}).
        Watches(
            &corev1.Secret{},
            handler.EnqueueRequestsFromMapFunc(r.findAppsForSecret),
        ).
        Complete(r)
}
```

`RequeueAfter` é para o que **não gera evento**, como um estado externo que precisa ser consultado. Não é o que torna
o controller level-triggered.

```go
return ctrl.Result{RequeueAfter: time.Minute * 5}, nil
```

#### Edge Triggered

- **Funcionamento**: a ação depende do evento em si ("criaram X, então faço Y")
- **Problema**: evento perdido, por queda do operator, por exemplo, nunca é compensado

Evite em operators. Se o código precisa saber "o que mudou", normalmente falta gravar algo no status.

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

### Rollout ordenado

`CreateOrUpdate` de vários Deployments de uma vez sobe tudo junto. Quando a aplicação tem ordem (um componente migra
o banco e os outros só podem subir depois), a chain precisa de um **gate**: o ensurer só avança quando o anterior
terminou, e devolve requeue enquanto espera.

```mermaid
flowchart TD
    REC["Reconcile"] --> M["sobe o migrator"]
    M --> G{"migrator pronto?<br/>observedGeneration == generation<br/>e réplicas disponíveis"}
    G -->|não| W["requeue: workers ficam parados"]
    W -.->|próxima passada| REC
    G -->|sim| K["libera os workers"]
    K --> R["Ready"]
    R -.->|"na descida, ordem inversa:<br/>drena os workers antes de reiniciar o migrator"| REC
```

```go
if migrator.Status.AvailableReplicas < *migrator.Spec.Replicas {
    state.Waiting = "migrator"
    return nil // os nós seguintes leem state.Waiting e não sobem os workers
}
```

Pontos que mordem:

- `Available` não quer dizer "terminou": confira que o `observedGeneration` do Deployment alcançou o `generation`,
  senão você lê o status do rollout anterior.
- Health check verde pode vir antes do trabalho real. Se o componente responde 200 antes de migrar, o gate precisa de
  um sinal próprio.
- Ordem de descida costuma ser a inversa da de subida, e precisa ser modelada também: esvaziar os workers antes de
  reiniciar quem migra.

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
