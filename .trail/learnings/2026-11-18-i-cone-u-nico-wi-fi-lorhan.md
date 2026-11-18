---
title: "Ícone único Wi-Fi + bateria + sinal na barra de menu feito pela própria Ilha, com os ícones do sistema escondidos pelo usuário"
author: Lorhan
date: 2026-11-18
branch: main
id: l-984432bb
scope: repo
status: active
src: agent
touches:
  - Sources/Ilha/AppDelegate.swift
  - build.sh
---

## Decided
O ícone estilo iPhone novo (arco = bateria, wifi no meio, bolinhas = sinal) é um item próprio da Ilha na barra de menu. Os ícones nativos de Wi-Fi e bateria são escondidos pelo usuário em Ajustes → Central de Controle.

## Tried and ruled out
- Trocar o ícone nativo do macOS: só com SIP desligado, risco alto.
- Deixar os dois ícones visíveis: o usuário recusou, ficaria duplicado.
- Esconder os ícones do sistema via defaults: a mudança de acessibilidade por defaults já bugou a tela neste Mac, então fica pela interface.

## Watch out
O ícone de barra de menu é template (só preto com alpha), pequeno e monocromático. Eu não consegui validar o visual por screenshot, o terminal não tem permissão de gravação de tela.

In the code:
- Sources/Ilha/StatusIcon.swift (NSStatusItem, CoreWLAN rssiValue, EnergyModel.percent)
- Ligado em AppDelegate.applicationDidFinishLaunching
- ./build.sh --install
