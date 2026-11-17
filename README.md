# Ilha

Uma "ilha dinâmica" para o notch do MacBook, feita em Swift. Ela fica em volta da câmera e mostra só o que importa: música, volume e brilho, área de transferência, energia e uso do sistema.

*English: a small Dynamic Island for the MacBook notch (music, volume/brightness HUD, clipboard history, battery/energy and system stats). Open source, MIT.*

## O que faz

- **Música:** capa do álbum e equalizador ao lado do notch. Passe o mouse e a ilha abre com título, artista, barra de progresso, anterior, play/pause, próxima e botões de ±10 s. Pausada, ela mantém a última faixa e as barrinhas ficam paradas.
- **Volume e brilho:** as teclas mostram um indicador na ilha, no lugar do HUD do macOS.
- **Área de transferência:** guarda as últimas 5 cópias (texto e imagem) e apaga cada uma depois de 24 h. **⌥ X** abre um seletor junto do mouse, em qualquer tela. Escolha com **1 a 5**, setas e Return, ou clique: o item já é colado no app em foco. Cópias marcadas como senha pelos gerenciadores de senha não são guardadas.
- **Energia:** bateria em anel, watts do sistema e do adaptador, voltagem, saúde e ciclos, e a bateria de mouse, teclado e fones.
- **Sistema:** CPU, RAM, GPU, SSD e temperatura.
- **Aviso de acessórios:** ao conectar ou desconectar mouse, fones ou iPhone (por cabo), a ilha mostra o ícone ao lado do notch.
- **Proteção do ⌘Q:** em alguns apps é preciso segurar ⌘Q por ~1,2 s para fechar.
- **F7/F8/F9:** quando o macOS solta a sessão de música, a tecla de play é redirecionada para o player em vez de abrir o Apple Music.

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

Esses valores estão no código, no começo de cada arquivo:

| O quê | Onde |
| --- | --- |
| App do YouTube Music (web app do Safari) usado no F8 e nos botões | `Sources/Ilha/YTMusic.swift` (`appURL`) |
| Apps protegidos do ⌘Q e o tempo de espera | `Sources/Ilha/MediaKeys.swift` (`protectedApps`, `holdSeconds`) |
| Atalho da área de transferência (⌥ X) | `Sources/Ilha/MediaKeys.swift` |
| Quantidade de cópias e prazo de 24 h | `Sources/Ilha/ClipboardStore.swift` |

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
