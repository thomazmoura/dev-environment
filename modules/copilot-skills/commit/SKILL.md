---
name: commit
description: Faz stage e commit das mudanças pendentes, um commit por grupo de mudanças relacionadas, com mensagens geradas a partir do diff, após validar que nada sensível foi adicionado. Use quando o usuário pedir para commitar o trabalho atual.
argument-hint: "instruções adicionais (opcional)"
# O `model` da Skill só é respeitado por clientes que suportam o campo; na CLI, quem garante o
# modelo é o `--model` do estágio 4 de Rodar-FluxoDeDesenvolvimento.ps1.
model: gpt-5.6-luna
allowed-tools: shell(git status), shell(git diff), shell(git add), shell(git commit), shell(git log), shell(git branch), shell(git restore), shell(rg), view(CHANGELOG.md), edit(CHANGELOG.md), ask_user
# Só por /commit: impede que o modelo a carregue por conta própria — inclusive o executor e o
# revisor na CLI, que também leem .github/skills.
disable-model-invocation: true
---

# Commit

Cria um commit por grupo de mudanças relacionadas (mais um commit de changelog, ver Passo 7).

## Passo 1 — Levantar o contexto

Rode estes comandos antes de decidir qualquer coisa (o Copilot não injeta saída de
comandos automaticamente — você precisa executá-los):

```bash
git status
git diff HEAD
git branch --show-current
git log --oneline -10
rg -m1 -n '^## \[' CHANGELOG.md || echo 'no CHANGELOG.md with hash entries'
```

Use `git log` apenas para imitar o estilo de mensagem já usado no repositório. O último
comando mostra a entrada mais recente do `CHANGELOG.md`, usada no Passo 7.

Se não houver nada para commitar, diga isso e pare — não crie commit vazio.

## Passo 2 — Stage e validação

Faça stage de todas as mudanças, incluindo arquivos novos, com `git add .`

Em seguida, rode os dois comandos **exatamente como escritos**:

```bash
git diff --cached --name-only | rg -i -e '(^|/)\.env(\.|$)' -e 'id_(rsa|ed25519|ecdsa)' -e '\.(pem|key|p12|pfx|keystore)$' -e 'credentials' -e 'secrets?\.'
```

```bash
git diff --cached -U0 | rg '^(\+\+\+ b/|\+[^+])' | rg -i -e '^\+\+\+ b/' -e 'BEGIN [A-Z ]*PRIVATE KEY' -e 'AKIA[0-9A-Z]{16}' -e 'gh[pousr]_[A-Za-z0-9]{30,}' -e 'sk-[A-Za-z0-9_-]{20,}' -e 'xox[abprs]-' -e 'eyJ[A-Za-z0-9_-]{10,}\.eyJ' -e '(password|passwd|senha|secret|token|api[_-]?key|access[_-]?key|client[_-]?secret)\W{0,3}[:=]\W{0,3}\S{6,}' -e '://[^/\s:@]+:[^/\s@]+@' -e '/home/[a-z0-9._-]+/' -e '/Users/[^/]+/' -e 'C:\\Users\\' -e '/srv/' -e '/var/www/' -e '\b(10\.\d+|192\.168|172\.(1[6-9]|2\d|3[01]))\.\d+\.\d+\b'
```

- O primeiro sinaliza arquivos que costumam guardar segredos (`.env`, chaves privadas,
  arquivos de credenciais). Código de saída 1 sem saída alguma significa que nada casou —
  isso é resultado limpo, não erro.
- O segundo imprime o cabeçalho de cada arquivo em stage (`+++ b/<arquivo>`) seguido das
  linhas adicionadas que parecem chave, token, senha, credencial em URL, caminho absoluto de
  usuário ou de servidor, ou IP privado. Cabeçalho sem linha embaixo está limpo.
- Leia também as linhas adicionadas (`+`) do diff do Passo 1 — e de `git diff --cached` para
  arquivos novos, que o diff do Passo 1 não mostra — procurando o que o padrão não pega:
  hostnames ou domínios internos, connection strings fixas no código, e-mails ou dados
  pessoais de pessoas reais, dados de cliente.
- Julgue cada achado: caminho com `~/`, placeholder óbvio (`example.com`, `changeme`, `xxx`)
  ou valor lido de variável de ambiente está tudo bem. Valor literal de segredo ou caminho
  absoluto específico de uma máquina, não.

Confira ainda:

- **Nada de conflito pendente.** Se houver marcador `<<<<<<<`, `=======` ou `>>>>>>>` nas
  linhas adicionadas, não commite: avise o usuário e pare.
- **Nada de arquivo gerado ou de artefato de build** (`bin/`, `obj/`, `node_modules/`,
  `dist/`, `*.log`, `*.bkp`) em stage. Se algum entrou, trate-o como achado.

## Passo 3 — Se algo real foi sinalizado

**Não commite.** Chame `ask_user` listando cada achado como `arquivo — trecho (motivo)`, com
os valores de segredo parcialmente mascarados (ex.: `abcd…5678`), e ofereça:

- "Abortar — eu corrijo" (Recomendado): pare aqui, deixe o index como está e não faça mais
  nenhuma chamada.
- "Tirar do stage os arquivos sinalizados e commitar o resto": rode
  `git restore --staged <arquivos>` e siga para o Passo 4.
- "Commitar mesmo assim (falso positivo)": siga para o Passo 4.

Se o usuário responder em texto livre, siga o que ele disse.

## Passo 4 — Agrupar

Agrupe o que está em stage agora (`git diff --cached --name-status`) em mudanças
relacionadas. Um grupo é um propósito: uma funcionalidade, uma correção, uma refatoração, uma
atualização de configuração ou de dependência.

- Mudanças ficam juntas quando servem ao mesmo propósito, seja qual for a parte do código em
  que estão: uma funcionalidade que toca backend, frontend, testes e documentação é um grupo só.
- Mudanças não têm relação quando cada uma faria sentido, e poderia ser revertida, sem a outra.
- Na dúvida, mantenha juntas.
- A divisão é por arquivo: um arquivo com mudanças de mais de um grupo vai para o grupo ao qual
  pertence a maior parte delas. Os caminhos antigo e novo de um rename ficam no mesmo grupo.
- Deixe de fora qualquer arquivo tirado do stage no Passo 3.

Com um único grupo, é um único commit.

## Passo 5 — Escrever as mensagens

Para cada grupo:

- **Em português.** Sempre escreva a mensagem de commit em português, mesmo que o diff,
  código ou nomes de variáveis estejam em inglês.
- Modo imperativo ("Adiciona funcionalidade", "Corrige bug", "Atualiza configuração")
- Primeira linha com menos de 72 caracteres
- **IMPORTANTE!** Nenhuma referência a Copilot, IA ou ferramentas automatizadas.
  Isso inclui o trailer `Co-authored-by: Copilot <...>`: **não** adicione trailer
  de co-autoria neste commit, mesmo que as instruções padrão peçam. Se algum commit sair com
  uma linha `Co-authored-by:` na mensagem, corrija com `git commit --amend`.

## Passo 6 — Commitar

Commite os grupos um de cada vez, começando por um grupo do qual os outros dependem, cada um
com `git commit -m "<mensagem>" -- <todos os caminhos do grupo>`. Nomear os caminhos commita
só esses, e os outros grupos continuam em stage para os próprios commits.

Termine com `git status --short`: nada que estava em stage depois do Passo 3 deve sobrar. Se
sobrar, commite junto do grupo ao qual pertence (`git commit --amend --no-edit -- <caminhos>`
se foi o último commit; caso contrário, como mais um commit).

## Passo 7 — CHANGELOG

Se o repositório tiver um `CHANGELOG.md` cujas entradas têm o cabeçalho
`## [<hash>] - <data>` (ver a última linha do Passo 1), registre os commits nele como **um
commit separado**. Um commit não pode conter o próprio hash (o amend o altera), então nunca
use amend aqui. Pule um commit que só tocou em `CHANGELOG.md`, `README.md` ou `AGENTS.md`, e
pule este passo quando todos os commits forem pulados.

1. Obtenha os hashes e as datas com
   `git log -<número de commits feitos> --format='%h %ad' --date=short`.
2. Leia o topo do `CHANGELOG.md` e adicione uma entrada por commit acima da mais recente,
   do mais novo para o mais antigo, seguindo o formato existente: `## [<hash>] - <data>`, e
   depois seções `### Added` / `### Changed` / `### Fixed` com um item por mudança visível ao
   usuário, escrito a partir do diff daquele commit.
3. Rode `git add CHANGELOG.md` e `git commit -m "Atualiza changelog"`.

Confirme o resultado com `git log --oneline -<número de commits feitos>`.

Apenas faça chamadas de ferramenta. Não produza texto além do necessário — a única exceção é
a chamada de `ask_user` quando a validação sinalizar algo.
