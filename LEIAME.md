
# dev-environment
Ambiente de desenvolvimento para codificar com o NeoVim. De dentro do próprio container.

## Visão Geral

> For the english version, check: [README.md](README.md)

Esse é um projeto pessoal para manter as minhas ferramentas de desenvolvimento do dia-a-dia, tanto para uso profissional quanto para projetos interessantes mais voltados para desenvolvimento (geralmente os mantenho em um container separado nesse mesmo repositório).

Eu pretendo reduzir o tamanho de ambos os containers eventualmente, mas por enquanto, tenha em mente que eles são consideravelmente imensos (principalmente o do QMK)

## Showcase

Troca de projetos com tmux + fzf e busca fuzzy de arquivos dentro do container:

![alt text](https://raw.githubusercontent.com/thomazmoura/image-samples/master/dev-environment/tmux_workflow.gif "Gif mostrando alguns dos recursos do meu fluxo de trabalho com o container")

## Objetivos

Minhas principais intenções com esse projeto são:

  * Manter minhas ferramentas de desenvolvimento versionadas e facilmente acessíveis, de modo que eu possa facilmente baixá-las de qualquer lugar.
  * Reduzir a necessidade de instalar (ou rodar) localmente coisas como admin/root (a ideia é que nenhuma configuração que necessite de permissão de root ocorrerá durante o build e os containers rodarão com usuários não privilegiados por padrão).
  * Ser uma referênica central para qualquer pessoa que queira verificar/experimentar alguma ferramenta ou configuração que eu uso (basicamente um projeto de dotfiles que você pode rodar).
  * Ter um pipeline funcional no qual eu possa atualizar minhas configurações e elas serem replicadas em qualquer lugar nas quais eu queria usar esses containers (e possivelmente incluindo algumas verificações como Software Composition Analysis).

## Stack Atual e Ferramentas

### Container Principal

O container que eu uso para a maior parte de trabalho profissional.

* **Docker** - O principal motivo pelo qual este repositório existe é testar a ideia de rodar a maior parte da minha stack em um container (e desenvolver de dentro do container), então eu estou utilizando o Docker para isso.
* **NeoVim** - NeoVim é a minha ferramenta de desenvolvimento principal então ele foi a minha escolha para editor/editor-metido-a-IDE. Eu também uso tanto o coc.nvim quanto alguns pacotes de LTS nativos e vários plugins para alcançar a usabilidade que eu preciso.
* **TMUX** - Eu uso principalmente para ter um painel dedicado para o terminal e para mudar rapidamente entre projetos.
* **PowerShell** - Me chame de herege, mas eu sou fã tanto do Linux quanto do PowerShell, então sim, eu uso prinicipalmente o PowerShell como meu shell principal e esse repositório reflete isso. Mas isso deve ser uma mudança fácil no Dockerfile, caso queira mudar isso em um fork seu.
* **DotNet** - Me chame de herege de novo, mas eu simplesmente amo codificar C# no NeoVim em um painel do tmux no Linux dentro de um container. É uma experiência tão subestimada... Mas enfim, o container principal deve ter pelo menos as versões LTS ainda suportadas do .NET instaladas.
* **Angular** - Eu uso principalmente o Angular para Frontend (sou um desenvolvedor Full Stack), então há alguns plugins focados nele.
* **Azure CLI** - Eu tenho alguns scripts para facilitar minha vida no Azure CLI com o módulo do Azure DevOps, então eu precisei acrescentá-lo aqui para que eu ainda pudesse utilizá-los. Eu pretendo substituí-lo eventualmente por chamadas diretas à API ou algo como o módulo PowerShell VSTeam, porque o az cli é gigantesco.

### Container Secundário (QMK)

Eu decidi criar esse sub-container (que usa o container principal como base) para poder acrescentar os requisitos para compilar o [QMK](https://github.com/qmk/qmk_firmware) (que é um firmware open source para teclados mecânicos) e Rust sem ter que aumentar demais o tamanho do container principal (o QMK precisa de várias dependências).

* **C/C++** - Necessário para compilar o QMK. Eu uso C apenas para personalizações de layouts e features do QMK, portanto o suporte para C/C++ é limitado comparado a outras linguages.
* **Rust** - Já que eu já tive que criar um segundo container para colocar os requisitos do QMK, achei que poderia aproveitar e instalar as dependências do Rust para poder rodá-lo como um contianer de estudo.

###  Scripts de Windows e Linux

Eu faço a maior parte do desenvolvimento dentro do container, mas há situações onde é mais produtivo recorrer a "soluções menos isoladas", como o Visual Studio Code rodando no Windows ou o WSL2 (idealmente, os dois). Então eu acresventei alguns scripts para que eu possa mais facilmente configurar uma máquina nova para usar algumas das mesmas configurações que eu uso nos containers.

