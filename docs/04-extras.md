
## Padrões de Design Comuns em Operators

### 1. Level Triggers vs Edge Triggers

#### Level Triggered (Gatilho por Nível)

- **Funcionamento**: O controller reconcilia constantemente, independente do evento que originou a reconciliação
- **Vantagens**:
  - Mais robusto contra falhas transitórias
  - Recupera-se automaticamente de estados inconsistentes
  - Melhor para sistemas que precisam de alta disponibilidade
- **Implementação**: Uso de `RequeueAfter` para reconciliação periódica

```go
return ctrl.Result{RequeueAfter: time.Minute * 5}, nil
```

#### Edge Triggered (Gatilho por Evento)

- **Funcionamento**: Reconcilia apenas quando ocorrem mudanças específicas nos recursos observados
- **Vantagens**:
  - Mais eficiente em termos de recursos computacionais
  - Reduz carga no API Server em clusters grandes
  - Menor latência para responder a mudanças
- **Implementação**: Filtros específicos no Watch para eventos relevantes

```go
func (r *DatabaseReconciler) SetupWithManager(mgr ctrl.Manager) error {
    return ctrl.NewControllerManagedBy(mgr).
        For(&databasev1.Database{}).
        Watches(
            &source.Kind{Type: &corev1.Secret{}},
            handler.EnqueueRequestsFromMapFunc(r.findDatabasesForSecret),
            builder.WithPredicates(predicate.ResourceVersionChangedPredicate{}),
        ).
        Complete(r)
}
```

### 2. Owner References

Owner References estabelecem relações hierárquicas entre recursos Kubernetes, permitindo a propagação automática de deleções (garbage collection).

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: db-instance-pod
  ownerReferences:
    - apiVersion: cloud104.com/v1alpha1
      kind: Database
      name: prod-database
      uid: d9607e19-f88f-11e6-a518-42010a800195
      controller: true
      blockOwnerDeletion: true
```

#### Implementação em código

```go
// Definir ownerReference no pod
controllerRef := metav1.NewControllerRef(database, databasev1.GroupVersion.WithKind("Database"))
pod.OwnerReferences = []metav1.OwnerReference{*controllerRef}
```

#### Benefícios

- Deleção em cascata automática
- Rastreabilidade clara de recursos relacionados
- Prevenção de recursos órfãos no cluster

### 3. Finalizers

Finalizers são mecanismos que impedem a exclusão imediata de recursos até que condições específicas sejam atendidas, essenciais para limpeza adequada de recursos externos.

```yaml
apiVersion: cloud104.com/v1alpha1
kind: Database
metadata:
  name: prod-database
  finalizers:
    - cloud104.com/database-cleanup
spec:
  size: 10Gi
  engine: postgres
```

#### Ciclo de vida com Finalizers

1. **Adição do Finalizer**: Quando o recurso é criado, o operator adiciona o finalizer
2. **Solicitação de Exclusão**: Usuário aplica `kubectl delete`
3. **Bloqueio da Exclusão**: API Server marca o objeto com `deletionTimestamp` mas não o remove
4. **Execução da Limpeza**: Operator detecta `deletionTimestamp` e executa limpeza necessária
5. **Remoção do Finalizer**: Após limpeza bem-sucedida, operator remove o finalizer
6. **Exclusão Efetiva**: Sem finalizers, o objeto é finalmente removido do etcd

#### Implementação em código

```go
const databaseFinalizer = "cloud104.com/database-cleanup"

func (r *DatabaseReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
    // ... código anterior
    
    // Verificar se o objeto está sendo excluído
    if database.GetDeletionTimestamp() != nil {
        if containsString(database.GetFinalizers(), databaseFinalizer) {
            // Executar lógica de limpeza
            if err := r.cleanupExternalResources(&database); err != nil {
                return ctrl.Result{}, err
            }
            
            // Remover finalizer
            database.SetFinalizers(removeString(database.GetFinalizers(), databaseFinalizer))
            if err := r.Update(ctx, &database); err != nil {
                return ctrl.Result{}, err
            }
        }
        return ctrl.Result{}, nil
    }
    
    // Adicionar finalizer se não existir
    if !containsString(database.GetFinalizers(), databaseFinalizer) {
        database.SetFinalizers(append(database.GetFinalizers(), databaseFinalizer))
        if err := r.Update(ctx, &database); err != nil {
            return ctrl.Result{}, err
        }
    }
    
    // ... resto do código
}

func (r *DatabaseReconciler) cleanupExternalResources(db *databasev1.Database) error {
    // Lógica para limpar recursos externos (ex: instâncias RDS, volumes, DNS, etc)
    return nil
}
```

## Boas Práticas para Desenvolvimento de Operators

### 1. Idempotência

**Definição**: Operações devem poder ser executadas múltiplas vezes sem efeitos colaterais além da primeira execução.

**Implementação**:

- Sempre verifique se um recurso existe antes de criá-lo
- Use `CreateOrUpdate` ao invés de criar/atualizar separadamente
- Evite assumir o estado do sistema; verifique tudo

```go
// Exemplo de padrão idempotente
result, err := controllerutil.CreateOrUpdate(ctx, r.Client, deployment, func() error {
    // Configurar o deployment aqui
    return nil
})
if err != nil {
    return ctrl.Result{}, err
}

switch result {
case controllerutil.OperationResultCreated:
    log.Info("Deployment criado")
case controllerutil.OperationResultUpdated:
    log.Info("Deployment atualizado")
case controllerutil.OperationResultNone:
    log.Info("Deployment não mudou")
}
```

### 2. Status Subresource

O campo `status` armazena o estado atual do recurso e deve ser gerenciado de forma consistente.

```yaml
apiVersion: cloud104.com/v1alpha1
kind: Database
metadata:
  name: prod-database
spec:
  engine: postgres
  version: "13.4"
  size: 20Gi
status:
  phase: Provisioning  # Valores possíveis: Pending, Provisioning, Running, Failed
  observedGeneration: 12
  conditions:
    - type: Available
      status: "False"
      reason: Creating
      message: "Criando instância de banco de dados"
      lastTransitionTime: "2023-04-15T10:30:00Z"
    - type: Healthy
      status: "Unknown"
      reason: Initializing
      message: "Verificações de saúde ainda não iniciadas"
      lastTransitionTime: "2023-04-15T10:30:00Z"
  externalEndpoint: ""
  connectionDetails:
    secretName: "prod-database-credentials"
```

**Recomendações**:

- Use `observedGeneration` para detectar se já processou a versão mais recente
- Implemente condições seguindo o padrão Kubernetes Conditions
- Atualize status usando `Status().Update()` separadamente do spec

```go
// Atualização do status separadamente do spec
if err := r.Status().Update(ctx, &database); err != nil {
    log.Error(err, "Falha ao atualizar status")
    return ctrl.Result{}, err
}
```

### 3. Backup e Recuperação

**Estratégias para implementação**:

- **Snapshots automatizados**: Programar backups periódicos dos recursos gerenciados
- **Backup sob demanda**: Permitir backup manual através de CRs adicionais
- **Validação de backups**: Verificar integridade periodicamente
- **Restauração simplificada**: API clara para restaurar a partir de backups

**Exemplo de CR para gerenciamento de backup**:

```yaml
apiVersion: cloud104.com/v1alpha1
kind: DatabaseBackup
metadata:
  name: prod-database-daily
spec:
  databaseRef:
    name: prod-database
  schedule: "0 2 * * *"  # Cron syntax (diariamente às 2h)
  retention: 7           # Manter últimos 7 backups
status:
  lastBackupTime: "2023-04-15T02:00:00Z"
  lastSuccessfulBackup: "backup-20230415"
  backups:
    - name: "backup-20230415"
      timestamp: "2023-04-15T02:00:00Z"
      size: "5.2GB"
      status: "Completed"
    - name: "backup-20230414"
      timestamp: "2023-04-14T02:00:00Z"
      size: "5.1GB"
      status: "Completed"
```

### 4. Versionamento e Compatibilidade API

**Estratégias de versionamento**:

- **Conversão entre versões**: Implementar webhooks de conversão
- **Validation Webhooks**: Validar novos campos em versões mais recentes
- **Defaulting Webhooks**: Definir valores padrão para novos campos
- **API Deprecation Policy**: Seguir política de depreciação do Kubernetes (1 ano)

```go
// Exemplo de Conversion Webhook
func (whsvr *WebhookServer) ConvertV1alpha1ToV1beta1(review *apiextensionsv1.ConversionReview) error {
    for i, obj := range review.Request.Objects {
        var srcObj databasev1alpha1.Database
        if err := json.Unmarshal(obj.Raw, &srcObj); err != nil {
            return err
        }
        
        // Converter de v1alpha1 para v1beta1
        dstObj := databasev1beta1.Database{
            ObjectMeta: srcObj.ObjectMeta,
            Spec: databasev1beta1.DatabaseSpec{
                Engine:  srcObj.Spec.Engine,
                Version: srcObj.Spec.Version,
                
                // Novo campo em v1beta1, conversão do campo antigo
                Resources: databasev1beta1.ResourcesSpec{
                    Storage: resource.MustParse(srcObj.Spec.Size),
                },
            },
            Status: databasev1beta1.DatabaseStatus{
                Phase:      srcObj.Status.Phase,
                Conditions: convertConditions(srcObj.Status.Conditions),
            },
        }
        
        // Converter para Raw e adicionar ao resultado
        raw, err := json.Marshal(dstObj)
        if err != nil {
            return err
        }
        review.Response.ConvertedObjects[i] = runtime.RawExtension{Raw: raw}
    }
    return nil
}
```

### 5. Segurança

**Melhores práticas**:

- **RBAC preciso**: Limitar permissões do operator ao mínimo necessário
- **Secret Management**: Gerenciar credenciais com segurança
- **Network Policies**: Restringir comunicação entre componentes
- **Pod Security Context**: Definir contextos de segurança adequados

**Exemplo de RBAC para um Operator**:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: database-operator-role
rules:
- apiGroups: ["cloud104.com"]
  resources: ["databases", "databases/status", "databases/finalizers"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: [""]
  resources: ["secrets", "services", "configmaps"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["statefulsets", "deployments"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
```

## Depuração e Solução de Problemas

### 1. Logs Estruturados

```go
log := r.Log.WithValues(
    "database", req.NamespacedName,
    "reconcileID", uuid.New().String(),
    "generation", database.Generation,
)

log.Info("Iniciando reconciliação", "phase", database.Status.Phase)
```

### 2. Métricas Prometheus

```go
// Definição de métricas
var (
    reconcileTotal = prometheus.NewCounterVec(
        prometheus.CounterOpts{
            Name: "database_controller_reconcile_total",
            Help: "Total de reconciliações iniciadas",
        },
        []string{"result"},
    )
    reconcileDuration = prometheus.NewHistogramVec(
        prometheus.HistogramOpts{
            Name:    "database_controller_reconcile_duration_seconds",
            Help:    "Duração das reconciliações",
            Buckets: prometheus.DefBuckets,
        },
        []string{"result"},
    )
)

// Registro das métricas na função Reconcile
startTime := time.Now()
result, err := r.reconcileLogic(ctx, req, database)
duration := time.Since(startTime).Seconds()

if err != nil {
    reconcileTotal.WithLabelValues("error").Inc()
    reconcileDuration.WithLabelValues("error").Observe(duration)
} else {
    reconcileTotal.WithLabelValues("success").Inc()
    reconcileDuration.WithLabelValues("success").Observe(duration)
}
```

### 3. Events

```go
// Registrar evento no recurso
r.Recorder.Event(&database, 
    corev1.EventTypeNormal, 
    "Provisioning", 
    fmt.Sprintf("Iniciando provisionamento do banco %s", database.Name))
```

## Casos de Uso Avançados

### 1. Estratégias de Deployment

- **Blue-Green**: Implementação de atualização não-disruptiva
- **Canary**: Implantação gradual para grupos limitados
- **Rolling Updates**: Atualização progressiva de instâncias

### 2. Auto-scaling

```yaml
apiVersion: cloud104.com/v1alpha1
kind: Database
metadata:
  name: prod-database
spec:
  engine: postgres
  autoscaling:
    minNodes: 3
    maxNodes: 10
    metrics:
    - type: CPU
      threshold: 75
    - type: Connections
      threshold: 1000
```

### 3. Multi-cluster Management

- **Control Plane Central**: Operator em cluster central gerencia recursos em clusters remotos
- **Federação**: Sincronização de CRs entre múltiplos clusters
- **Multitenancy**: Isolamento de recursos entre tenants
