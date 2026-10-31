# Leituras extras

Material de apoio, fora do tempo da sessão. O lab em [`03-desenvolvimento.md`](../03-desenvolvimento.md) não depende
de nada aqui.

| Quero entender | Leia |
|---|---|
| Finalizer, rollout ordenado, level vs. edge triggered, conditions | [Padrões avançados](advanced-operator-patterns.md) |
| Por que `CreateOrUpdate` e owner references funcionam como no lab | [CreateOrUpdate e OwnerReferences](kubernetes-create-or-update.md) |
| Como filtrar eventos antes do `Reconcile` | [Predicates](predicates-kubebuilder.md) |
| De onde vêm o cache e os eventos do controller | [Informers](kubernetes-informers.md) |
| Webhooks, conversão de versões, leader election, rate limiting | [Tópicos avançados](advanced-operator-topics.md) |
| A estrutura de um projeto e o manager do Kubebuilder | [Guia do Kubebuilder](kubebuilder-guide.md) |

Ordem sugerida depois do treinamento: CreateOrUpdate, Padrões avançados, Predicates. Os demais, conforme a necessidade.
