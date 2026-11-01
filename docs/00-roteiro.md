# Roteiro do treinamento

Sessão de 3 horas com um intervalo, conduzida com tela compartilhada. O time assiste: toda a parte prática é feita ao
vivo pelo instrutor, e ninguém prepara máquina.

Público: Go e Kubernetes básicos. Não conhece controller nem o produto.

Os comandos do lab vêm prontos em [`03-desenvolvimento.md`](03-desenvolvimento.md). A demo do encerramento tem guia
interno próprio, porque depende do produto.

## Tempos

| Horário | Bloco | Tempo | Máquina (medido) | Pode cortar? |
|---|---|---|---|---|
| 0:00 | [Por que operators](#bloco-1-por-que-operators) | 20 min | - | sim, até 10 min |
| 0:20 | [Conceitos](#bloco-2-conceitos) | 25 min | - | sim, até 15 min |
| 0:45 | [Lab 1](#bloco-3-lab-1) | 30 min | 40 s | não |
| 1:15 | Intervalo | 10 min | - | não |
| 1:25 | [Lab 2](#bloco-4-lab-2) | 45 min | 20 s | não; só 2.6 encurta |
| 2:10 | [Lab 3](#bloco-5-lab-3) | 15 min | 1 min 45 s | não |
| 2:25 | [Do lab ao PDV](#bloco-6-do-lab-ao-pdv) | 10 min | - | sim, até 5 min |
| 2:35 | [Demo](#bloco-7-demo) | 20 min | 2 min até `Ready`, até 5 min no link | não |
| 2:55 | [Perguntas](#bloco-8-perguntas-e-próximos-passos) | 5 min | - | sim |
| 3:00 | Fim | | | |

**Soma: 180 minutos.** "Máquina" é o tempo dos comandos no ensaio, com cache do Go aquecido e sem fala. O restante é
explicação e leitura de código, **estimado, não medido**: nenhum ensaio foi feito com fala. Se atrasar, a ordem de corte
é: bloco 1, bloco 2, bloco 6 e o item 2.6 do lab. Dá até 25 minutos. Teoria sai primeiro; lab e demo, nunca.

Com cache do Go frio, os comandos levam bem mais: 1 min 25 s no Lab 1, 2 min no Lab 2 e 46 s só no `make test`. O Tilt
com cache frio não foi medido. Por isso o preparo é obrigatório.

## Preparo

Na véspera, com o repositório clonado e as ferramentas de [`02-setup-ambiente.md`](02-setup-ambiente.md):

1. Rode o [lab](03-desenvolvimento.md) inteiro uma vez: aquece o cache do Go e baixa os binários do envtest.
2. Prepare a demo pelo guia interno.
3. Confira 3 GB livres em disco e as portas 30000 e 10350.

Na hora: dois terminais com fonte grande, editor aberto, e o terminal do log do manager sempre à vista.

## Bloco 1: Por que operators

**0:00, 20 min.**

**Objetivo:** entender que problema um operator resolve, usando um caso real.

**Mostrar:** a primeira seção de [`01-conceitos-basicos.md`](01-conceitos-basicos.md) e, sem código, a forma do
operator do PDV: uma `PdvTopology` por cliente, um namespace por topologia, um produto com vários componentes, broker,
cache e share próprios, banco fora do cluster. Na demo, por exceção, o Oracle de teste roda no
namespace.

**Dizer:** "Um Deployment mantém réplicas. Ele não sabe que um componente tem de subir antes do outro, nem que reiniciá-lo
com os workers no ar quebra tudo. Esse conhecimento morava num runbook; o operator é esse runbook virando código."

**Combinar:** o que existe hoje. O produto completo subiu no dev do TKS, com banco de teste. O Portal existe, mas o PDV
ainda não está integrado a ele, e o operator ainda não roda em hmg nem em produção.

**Saída esperada:** ninguém ainda vê terminal. O time sabe dizer por que um Deployment não basta.

## Bloco 2: Conceitos

**0:20, 25 min.**

**Objetivo:** ter o vocabulário do lab: CRD, CR, controller, reconcile, level-triggered, owner reference, conditions,
chain.

**Mostrar:** [`01-conceitos-basicos.md`](01-conceitos-basicos.md), seção por seção, com o diagrama do loop.

**Dizer:** "O `Reconcile` não recebe o evento, só o nome do objeto. Ele olha o mundo e corrige. Perder um evento não
importa: é isso que level-triggered quer dizer."

**Corte, se atrasar:** pule "Chain de ensurers" aqui. Ela aparece no Lab 2 de qualquer jeito.

**Saída esperada:** o time responde "o que acontece se o operator cair e voltar?".

## Bloco 3: Lab 1

**0:45, 30 min. Scaffold, API, CEL, CRD instalada.**

**Objetivo:** sair do nada a uma API nova no cluster, com validação.

**Mostrar:** as seções 1.1 a 1.4 de [`03-desenvolvimento.md`](03-desenvolvimento.md), lendo os tipos Go com calma.

```bash
export TREINAMENTO="$PWD"
export KUBECONFIG="$HOME/.kube/k8s-operators-lab-config"
"$TREINAMENTO/scripts/setup-cluster.sh"
kubebuilder init --domain cloud104.com --repo github.com/cloud104/sampleapp-operator
kubebuilder create api --group apps --version v1alpha1 --kind SampleApp --resource --controller
make generate manifests install
kubectl apply -f config/samples/apps_v1alpha1_sampleapp.yaml
kubectl patch sampleapp sampleapp-example --type=merge -p '{"spec":{"image":"nginx:latest"}}'
```

**Dizer:** "A CRD sai dos tipos Go. CEL roda dentro do API Server, sem webhook: o CR inválido nem chega a existir." E, no
CR válido: "Ninguém está olhando ainda. O objeto só fica guardado."

**Saída esperada:** `No resources found` para Deployment, e a recusa:

```text
The SampleApp "sampleapp-example" is invalid: spec: Invalid value: image precisa de uma tag fixa, diferente de latest
```

## Intervalo

**1:15, 10 min.** Deixe o cluster e o terminal como estão.

## Bloco 4: Lab 2

**1:25, 45 min. Chain, ensurers, status, drift.**

**Objetivo:** escrever o controller e ver level-triggered acontecer.

**Mostrar:** as seções 2.1 a 2.7. Leia cada ensurer antes de seguir. Manager num segundo terminal, com o log à vista.

```bash
make manifests generate fmt vet
make run                                  # segundo terminal
kubectl apply -f config/samples/apps_v1alpha1_sampleapp.yaml
kubectl wait sampleapp/sampleapp-example --for=condition=Ready --timeout=120s
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:30000/
kubectl delete service sampleapp-example
kubectl patch sampleapp sampleapp-example --type=merge -p '{"spec":{"replicas":3}}'
kubectl delete sampleapp sampleapp-example
```

**Dizer:** "Cada ensurer cuida de um recurso e é idempotente. O `CreateOrUpdate` só define o que é nosso." Ao apagar o
Service: "Não tem código de 'recriar'. O `Owns()` acordou o reconcile, e ele só comparou." Ao apagar o CR: "Também não tem
código de deleção: a owner reference basta."

**Saída esperada:** `READY True`, `200`, Service de volta com `operation: created` no log, `READY False` e depois
`AVAILABLE 3`, e `No resources found` no fim.

**Corte, se atrasar:** em 2.6, mostre só o patch e o `kubectl get sampleapp` final.

## Bloco 5: Lab 3

**2:10, 15 min. envtest e Tilt.**

**Objetivo:** ver como isso se testa e como é o ciclo de desenvolvimento no dia a dia.

**Mostrar:** as seções 3.1 e 3.2. Pare o `make run` antes.

```bash
make test
"$TREINAMENTO/scripts/kubebuilder-tilt-setup.sh"
tilt up --stream
```

**Dizer:** "O envtest é um API Server de verdade, sem kubelet: a CEL roda de verdade, e o status do Deployment o teste
escreve à mão." No Tilt: "Mudei uma linha e em menos de um minuto o pod novo está no ar."

**Saída esperada:** `ok ... internal/controller`, e a linha `reconcile concluído pelo Tilt` no log. No ensaio, 45 s
depois da edição.

Depois: Ctrl+C e a [limpeza](03-desenvolvimento.md#limpeza).

## Bloco 6: Do lab ao PDV

**2:25, 10 min.**

**Objetivo:** reconhecer no código real o que acabou de ser escrito.

**Mostrar:** a tabela conceito → arquivo do guia interno, abrindo a chain e o teste que trava a ordem dela.

**Dizer:** "É o mesmo desenho, com mais nós. A maior parte do que vocês vão ver lá tem um equivalente pequeno no lab."

**Saída esperada:** o time sabe onde abrir o código na primeira tarefa.

## Bloco 7: Demo

**2:35, 20 min.**

**Objetivo:** ver o operator real provisionando o produto real no cluster de dev, a partir de um manifesto, e abrir o
frontend pelo domínio público.

**Mostrar e comandos:** a sequência ao vivo do guia interno, que traz os comandos, uma tabela de minutos e três
diagramas para a tela:

1. **Antes do `apply`:** o log do manager num segundo terminal e a leitura do manifesto, campo a campo, comparado ao
   `SampleApp`. Explique a estrutura: dois controllers, o da topologia, que cria um workload por componente, e o do
   workload, que cria o Deployment e o Service. É o `Owns()` do lab em dois níveis.
2. **Durante o `apply`:** a topologia criada do zero, de `Provisioning` até `Ready`. Enquanto o `-w` roda, leia as colunas
   e narre a ordem de subida: os workers nascem com zero réplicas e só sobem quando o componente central fica estável.
3. **Depois:** as conditions na ordem da chain, os recursos criados, o link do frontend para a turma e um filho apagado
   voltando.

**Dizer:** "O que fiz foi um `kubectl apply`. Quem sabe a ordem é o operator."

**Saída esperada:** `Ready` em cerca de 2 minutos. A tela de login vem depois: o link foi medido em 5 minutos, numa amostra só, e
responde 404 até lá. Abra-o só depois do `Ready`, avise a turma e siga para as conditions enquanto ele não sobe. Um Service
apagado volta em menos de 1 s. Se o Orchestrator não estabilizar em 10 minutos, vá para a contingência do guia interno.

## Bloco 8: Perguntas e próximos passos

**2:55, 5 min.**

**Mostrar:** as [leituras extras](extras/README.md) e a documentação interna do operator.

**Dizer:** qual é a primeira tarefa de cada um e por onde começar a ler.
