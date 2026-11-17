# Ilha

Uma "ilha dinâmica" para o notch do MacBook, feita em Swift. Ela fica em volta da câmera e mostra só o que importa: música, volume e brilho, área de transferência, energia e uso do sistema.

*English: a small Dynamic Island for the MacBook notch (music, volume/brightness HUD, clipboard history, battery/energy and system stats). Open source, MIT.*

## O que faz

A ilha fica em volta da câmera. Fechada, mostra só o essencial; ao passar o mouse, ela abre com quatro abas e um botão de ajustes.

**Música** (aba da nota musical)
- Fechada: capa do álbum à esquerda e equalizador à direita do notch. O equalizador anima enquanto toca e fica parado, com as cinco barras iguais, quando pausa.
- Aberta: capa, título, artista, barra de progresso, anterior, play/pause, próxima e botões de ±10 s.
- Arrastar ou clicar na barra pula para aquele ponto, com precisão de uns 5 s.
- Pausada, a ilha mantém a última faixa na tela, mesmo depois de o macOS soltar a sessão de música.

**Volume e brilho**
- As teclas de volume, mudo e brilho passam a mostrar um indicador na ilha, no lugar do HUD do macOS, com o ícone de alto-falante ou sol e uma barrinha.

**Área de transferência** (aba da prancheta)
- Guarda as últimas cópias (padrão: 5), de texto e de imagem, e apaga cada uma depois de um prazo (padrão: 24 h).
- O atalho (padrão **⌥ X**) abre um seletor **junto do mouse**, na tela onde ele estiver. Escolha com as teclas **1 a 9**, as setas e Return, ou clicando. O item escolhido é copiado e **colado no app em foco**.
- Cópias que os gerenciadores de senha marcam como senha não são guardadas.

**Energia** (aba do raio)
- Bateria em anel, com o estado (na bateria, na tomada ou carregando) e o tempo restante.
- Consumo do sistema em watts, o que o adaptador está entregando ("6 de 35 W") com a voltagem, saúde da bateria e ciclos.
- Bateria de mouse, teclado e fones conectados, cada um com seu anel.

**Sistema** (aba do chip)
- CPU, RAM, GPU e SSD, com anel colorido pela carga, e a temperatura do processador e da bateria.

**Avisos na própria ilha**
- Ao conectar ou desconectar mouse, teclado, fones ou iPhone (por cabo), aparece o ícone do aparelho e a bateria dele ao lado do notch. O aviso também sai quando a bateria do aparelho chega a 20%.
- Ao ligar ou desligar o carregador, a ilha mostra a bateria do Mac por alguns segundos.
- Experimental: a Ilha tenta esconder o aviso nativo de "Conectado" do Bluetooth.

**Proteção do ⌘Q**
- Nos apps que você escolher nos Ajustes (por padrão Claude, Terminal, Safari, Grok Bot e Cursor), o ⌘Q só fecha o app se você segurar por 1,2 s. Uma barrinha na ilha mostra o progresso.

**Teclas de mídia**
- Quando o macOS já soltou a sessão de música, o F8 deixa de abrir o Apple Music: a Ilha aperta o play do player configurado, sem trazê-lo pra frente. O F7 e o F9 não fazem nada nessa situação.

**Ajustes**
- Clique na engrenagem da ilha aberta (ou abra o app de novo) para mudar: o atalho da área de transferência (clique em Gravar e aperte as teclas), quantas cópias guardar e por quanto tempo, a proteção do ⌘Q (liga/desliga, o tempo e **quais apps** ficam protegidos: adicione ou remova da lista) e abrir ao ligar o Mac.

## Requisitos

- Mac com Apple Silicon e notch, macOS 14 ou mais novo (desenvolvido e testado no macOS 27.3 beta).
- Command Line Tools (`xcode-select --install`). Não precisa do Xcode completo.

## Instalar

```sh
git clone https://github.com/lorhanbp/ilha.git
cd ilha
./scripts/make-cert.sh     # uma vez: cria o certificado local "Ilha Dev"
./build.sh --install       # compila, copia para /Applications e abre
```

O certificado é opcional, mas sem ele o macOS esquece a permissão a cada build. Se o `make-cert.sh` falhar, o `build.sh` assina de forma temporária.

Quando instalada em `/Applications`, a Ilha se registra para abrir no login (Ajustes → Geral → Itens de Início).

## Permissão

A Ilha captura teclas e controla outros apps pela Acessibilidade. No macOS 27 isso fica em **Privacidade e Segurança → System & App Protection Override**: adicione `Ilha.app` com o **+**. O macOS mostra um indicador azul na barra enquanto um app usa essa permissão.

## Ajustes que você provavelmente vai querer

O atalho, a quantidade de cópias, o prazo e a proteção do ⌘Q estão na janela de Ajustes. Estes continuam no código:

| O quê | Onde |
| --- | --- |
| App do YouTube Music (web app do Safari) usado no F8 e nos botões | `Sources/Ilha/YTMusic.swift` (`appURL`) |

Para o YouTube Music: abra `music.youtube.com` no Safari e use **Arquivo → Adicionar ao Dock**, com o nome "YT Music".

## Como funciona e limites

A Ilha usa APIs **privadas** do macOS (MediaRemote para a música, DisplayServices para o brilho e IOHID para as temperaturas). Podem quebrar em qualquer atualização.

- No macOS 15.4+ o MediaRemote só responde para binários da Apple. A Ilha carrega uma pequena biblioteca (`native/adapter.m`) dentro do `/usr/bin/perl`, que é assinado pela Apple. A técnica é a mesma do projeto [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter).
- O YouTube Music no Safari **não aceita** pular para um ponto pelo macOS. A barra de progresso e os botões de ±10 s funcionam mandando as teclas J e L do player. Para isso a janela do web app é escondida no canto de baixo à esquerda da tela. Clique na capa da ilha aberta para trazê-la de volta.
- O macOS solta a sessão de música alguns segundos depois da pausa, então a ilha guarda a última faixa por conta própria.

## Feito com ajuda de IA

Este projeto foi desenvolvido com o Claude Code (Anthropic). O código foi revisado e testado no Mac do autor, e pode ter arestas em outros modelos.

## Licença

[MIT](LICENSE)
