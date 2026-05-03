# finAInce AI Roadmap

## Objetivo

Transformar o finAInce de um app que **coleta e organiza dados financeiros** em um app que **age como assistente financeiro diário**, usando IA para:

- antecipar riscos
- reduzir trabalho manual
- sugerir ações práticas
- melhorar decisões do usuário
- explicar causas e consequências de forma simples

O princípio central deste roadmap é:

> Não adicionar IA como camada cosmética.
> Adicionar IA como comportamento útil do produto.

---

## Visão de Produto

Hoje o app já tem uma base muito forte:

- entrada de dados manual
- importação de extratos
- leitura de recibos
- categorização
- metas
- contas e cartões
- calendário
- insights
- chat com IA

O próximo salto não é “mais coleta”.
O próximo salto é **inteligência aplicada ao dia a dia**, especialmente em:

- prevenção
- previsão
- automação
- explicação
- recomendação contextual

---

## Princípios para priorização

Toda nova funcionalidade de IA deve ser avaliada por 5 critérios:

1. `Frequência`
- Quantas vezes por semana o usuário se beneficia disso?

2. `Acionabilidade`
- A saída sugere uma ação concreta ou só uma observação?

3. `Confiabilidade`
- A lógica é estável o suficiente para não gerar ruído?

4. `Aproveitamento do que já existe`
- Usa dados que o app já coleta bem?

5. `Diferenciação`
- Isso torna o produto mais memorável e menos genérico?

Prioridade alta deve ir para itens com:

- alto uso
- alta utilidade prática
- baixa fricção de implementação
- baixa dependência de entrada extra do usuário

---

## Macrofrentes

O roadmap é organizado em 5 frentes:

1. Assistência Proativa
2. Previsão e Simulação
3. Automação Inteligente
4. IA Contextual em cada tela
5. Assistente Estratégico / Coach Financeiro

---

# 1. Assistência Proativa

## Objetivo

Fazer o app perceber situações relevantes antes do usuário pedir.

## Problema atual

Hoje o app já mostra insights, mas em muitos casos ainda depende de o usuário abrir a tela certa ou interpretar o contexto sozinho.

## Evolução desejada

Criar uma camada de “assistente ativo”, que:

- observa o contexto do mês
- percebe risco ou oportunidade
- recomenda ações simples
- fala em linguagem curta

## Quick Wins

### 1.1 Insight diário prioritário

Mostrar um “insight do dia” no dashboard, escolhido entre:

- risco de meta
- pressão de cartão
- gasto acima do ritmo
- conta vencendo
- janela boa para compra no cartão

#### Valor

- reduz carga cognitiva
- faz o app parecer vivo
- ajuda o usuário a saber “o que importa hoje”

#### Dependências

- aproveitar `InsightEngine`
- criar ranking diário com desempate mais agressivo

#### Critério de sucesso

- o insight do topo deve ser entendível em menos de 3 segundos
- o usuário deve conseguir responder: “o que devo fazer com isso?”

---

### 1.2 Alertas preventivos de estouro de meta

Hoje já existe alerta de 80% da meta.

Evoluir para:

- “se você mantiver esse ritmo, essa meta deve estourar em X dias”
- “categoria X é a principal causa”

#### Valor

- transforma alerta estático em orientação prática

#### Dependências

- ritmo por categoria
- consumo projetado até fim do mês

---

### 1.3 Alertas inteligentes de cartão

Expandir o que já foi iniciado:

- véspera do fechamento
- dia do vencimento

Adicionar:

- “limite do cartão já passou de X%”
- “essa fatura deve fechar acima do mês anterior”
- “compras pequenas frequentes estão acelerando essa fatura”

#### Valor

- cartão costuma ser ponto cego emocional do usuário
- ajuda muito no dia a dia

---

## Médio Prazo

### 1.4 Feed de prioridades da semana

Um bloco na dashboard ou perfil com:

- 3 prioridades financeiras da semana
- uma por cartão
- uma por meta
- uma por despesa/categoria

#### Exemplo

- “Evite novas compras no Visa até o fechamento”
- “Restaurantes já consomem 82% da meta”
- “Quinta-feira concentra seus maiores gastos”

---

# 2. Previsão e Simulação

## Objetivo

Ajudar o usuário a entender o futuro próximo, não só o passado.

## Problema atual

Já existem previsões pontuais, mas ainda não existe uma camada forte de simulação prática.

## Quick Wins

### 2.1 Previsão de fechamento por categoria

Para as categorias principais do mês:

- quanto já foi gasto
- quanto deve fechar
- comparação com mês passado

#### Exemplo

- “Restaurantes deve fechar em €310, acima de €220 no mês passado”

#### Valor

- mais útil do que apenas total do mês
- ajuda a agir onde importa

---

### 2.2 Projeção consolidada de faturas de cartão

Para cada cartão:

- valor atual da fatura
- valor previsto até fechamento
- percentual do limite
- comparação com ciclo anterior

#### Valor

- une limite, ciclo, velocidade e risco

---

### 2.3 Simulação “e se”

Primeira versão simples:

- “se você não gastar mais em X categoria, fecha em Y”
- “se mantiver o ritmo atual, fecha em Z”

Mais tarde:

- “se adiar compras para depois do fechamento”
- “se mover parte do gasto para débito”

#### Valor

- produto começa a ensinar comportamento

---

## Médio Prazo

### 2.4 Projeção de caixa de curto prazo

Janela de 7, 15 e 30 dias:

- despesas previstas
- pagamentos de fatura
- saldo estimado

#### Observação

Esse item exige cuidado, porque projeção ruim destrói confiança.
Deve ser liberado só quando as entradas mínimas estiverem consistentes.

---

# 3. Automação Inteligente

## Objetivo

Reduzir o trabalho do usuário usando padrões já detectáveis.

## Problema atual

O app já automatiza parte da leitura, mas ainda há muito espaço para sugerir em vez de esperar input manual.

## Quick Wins

### 3.1 Sugestão automática de recorrência

Quando o app detectar padrão mensal/trimestral/anual:

- sugerir transformar em recorrente
- sugerir tipo de recorrência

#### Exemplo

- streaming
- academia
- seguro
- mensalidade

---

### 3.2 Sugestão de pagamento de fatura

Quando o sistema detectar:

- transação saindo da conta corrente perto do vencimento
- descrição compatível com cartão

Sugerir:

- “isso parece pagamento da fatura do cartão X”

#### Valor

- melhora qualidade do dado
- ajuda previsões e insights

---

### 3.3 Sugerir subcategoria com mais precisão

Hoje a categorização já está forte.

Próximo passo:

- sugerir subcategoria com mais confiança
- reaproveitar merchant intelligence
- criar correções automáticas por histórico do próprio usuário

#### Exemplo

- supermercado habitual sempre vira a mesma subcategoria

---

### 3.4 Regras pessoais aprendidas

O app aprende preferências do usuário:

- merchant X -> categoria Y
- conta preferida para tipo de gasto Z
- projeto padrão para merchant/contexto W

#### Valor

- IA mais personalizada
- menos atrito manual

---

## Médio Prazo

### 3.5 Auto-split inteligente

Quando uma despesa parecer compartilhada ou ambígua:

- sugerir divisão entre categoria/projeto/família

---

# 4. IA Contextual em cada tela

## Objetivo

Fazer cada tela ficar mais útil sem exigir que o usuário vá ao chat.

## Problema atual

O chat é poderoso, mas nem toda ajuda deve depender de conversa.

## Estratégia

Cada tela principal deve ter micro-inteligência contextual.

## Dashboard

### 4.1 Explicação do insight

Adicionar ação tipo:

- “por que estou vendo isso?”

Explica:

- dados usados
- causa principal
- próximo passo sugerido

---

### 4.2 Calendário com explicação contextual

Ao tocar num dia:

- explicar por que aquele dia é relevante
- pagamento de fatura
- fechamento
- concentração de despesas
- dia com comportamento recorrente

---

## Tela do cartão

### 4.3 Conselhos de timing

Exemplos:

- “você está no começo do ciclo”
- “espere 1 dia e ganhe mais prazo”
- “esta fatura já está mais pressionada que a anterior”

---

## Lista de transações

### 4.4 Explicação de agrupamentos

Exemplos:

- “estes gastos parecem pertencer ao mesmo evento”
- “há um padrão de compras pequenas repetidas”

---

## Metas

### 4.5 Recomendações de ajuste

Exemplos:

- “para bater essa meta, reduza cerca de X por semana”
- “categoria Y é a principal origem do excesso”

---

# 5. Assistente Estratégico / Coach Financeiro

## Objetivo

Evoluir do “assistant that answers” para “assistant that guides”.

## Problema atual

O chat já responde, mas ainda pode evoluir para orientar rotinas e comportamento.

## Médio Prazo

### 5.1 Revisão semanal automática

Toda semana gerar um resumo com:

- o que piorou
- o que melhorou
- o que merece atenção
- uma sugestão prática

#### Exemplo

- “Seu cartão acelerou nesta semana por delivery e transporte”
- “Você está abaixo da meta em lazer”
- “A melhor ação agora é segurar novas compras no Visa até sexta”

---

### 5.2 Revisão mensal com plano de ação

Mais útil que só exportar análise:

- 3 problemas
- 3 oportunidades
- 3 ações recomendadas

---

### 5.3 Coach por objetivo

O usuário define um foco:

- reduzir gasto
- controlar cartão
- aumentar sobra
- preparar viagem

O app passa a priorizar insights e alertas alinhados a esse objetivo.

#### Valor

- IA mais orientada
- menos genérica

---

# Priorização sugerida

## Fase 1: Próximas entregas

Objetivo:
colocar IA mais útil no dia a dia com baixo risco.

### Itens

1. Insight do dia no dashboard
2. Projeção de fechamento por categoria
3. Alertas expandidos de cartão
4. Sugestão automática de recorrência
5. Explicação “por que estou vendo isso?”

### Por que essa ordem

- usa dados já existentes
- gera valor visível rápido
- fortalece percepção de inteligência real

---

## Fase 2: Camada de previsão prática

Objetivo:
transformar histórico em previsão acionável.

### Itens

1. Simulação “e se”
2. Projeção consolidada de faturas
3. Previsão curta de caixa
4. Recomendações de meta por ritmo

---

## Fase 3: IA personalizada

Objetivo:
fazer o app aprender com o usuário.

### Itens

1. Regras pessoais aprendidas
2. Ajuste fino de merchant/category por histórico
3. Coach por objetivo
4. revisão semanal automática

---

# Backlog estruturado

## A. Quick Wins de alto impacto

- Insight do dia
- Explicação do insight
- Projeção de fechamento por categoria
- Pressão de cartão por limite e ritmo
- Sugestão de recorrência

## B. Melhorias fortes de produto

- Feed semanal
- Simulação “e se”
- Projeção de caixa
- Coach por objetivo

## C. Apostas mais ousadas

- IA que aprende hábitos e regras pessoais
- plano de ação mensal automático
- explicações transversais entre cartão, metas e caixa

---

# Requisitos técnicos antes de avançar muito

Para a IA ficar mais útil sem perder confiança, o app precisa manter 4 fundamentos fortes:

## 1. Consistência de dados

- pagamentos de fatura bem identificados
- transferências não confundidas com despesa
- cartão vs débito bem separados

## 2. Contexto confiável

- datas corretas
- categorias estáveis
- contas corretas
- limites e ciclos de cartão preenchidos

## 3. Explicabilidade

- o usuário precisa entender de onde veio a recomendação
- insights sem explicação parecem aleatórios

## 4. Controle de ruído

- é melhor menos alertas e mais úteis
- do que muitos alertas medianos

---

# Critérios de qualidade para qualquer funcionalidade nova de IA

Antes de considerar uma feature pronta, validar:

- a mensagem é entendível em menos de 5 segundos
- existe uma ação clara implícita ou explícita
- o texto não parece genérico
- o insight bate com os dados reais
- a recomendação não depende de premissa frágil
- a feature funciona mesmo com dados incompletos

---

# Proposta de execução incremental

## Sprint A

- Insight do dia
- Explicação do insight
- expansão de alertas de cartão

## Sprint B

- Projeção por categoria
- comparação de ritmo por categoria
- revisão do ranking de insights

## Sprint C

- Sugestão de recorrência
- sugestão de pagamento de fatura
- regras pessoais simples

## Sprint D

- simulação “e se”
- projeção consolidada de faturas
- primeiras telas de previsão de caixa

---

# O que não fazer agora

Itens que parecem interessantes, mas podem desviar foco cedo demais:

- chat excessivamente aberto e genérico
- assistente com respostas longas demais
- previsões sofisticadas sem base confiável
- recomendação “mágica” sem explicação
- automações invisíveis que o usuário não entende

---

# Próxima recomendação prática

Se for começar agora, a melhor sequência é:

1. `Insight do dia`
2. `Explicação do insight`
3. `Projeção de fechamento por categoria`
4. `Alertas expandidos de cartão`
5. `Sugestão de recorrência`

Essa sequência:

- mostra valor rápido
- aproveita a base atual
- fortalece a identidade do app
- cria uma camada real de inteligência aplicada

---

## Como usar este documento

Quando quiser executar uma parte, use este formato:

- `Vamos fazer o item 1.1`
- `Vamos começar a Fase 1 pelo Insight do dia`
- `Quero detalhar tecnicamente o item 3.1`
- `Vamos transformar o item 4.1 em tarefas`

Assim conseguimos seguir o roadmap em pedaços pequenos, mantendo consistência de produto e arquitetura.
