---
title: "O aviso nativo de Bluetooth é uma janela do MenuBarAgent e se esconde movendo só ela, no instante em que nasce"
author: Lorhan
date: 2026-11-18
branch: main
id: l-36236ef9
scope: repo
status: active
src: agent
touches:
  - Sources/Ilha/AccessoryMonitor.swift
  - Sources/Ilha/AppDelegate.swift
  - Sources/Ilha/ClipboardStore.swift
  - Sources/Ilha/EnergyModel.swift
  - Sources/Ilha/Monitors.swift
  - Sources/Ilha/NativePopupGuard.swift
  - Sources/Ilha/SystemMonitor.swift
---

## Decided
O aviso de conectado/desconectado do macOS é uma janela do MenuBarAgent (367x154). A Ilha a esconde pedindo ao macOS aviso de janela criada (AXObserver) e movendo só ela para fora da tela. Sem timers parados: tudo reage a avisos do macOS (IOKit, IOPS, CoreWLAN).

## Tried and ruled out
- Varredura com timer a cada 0,15 s: gasta CPU e o aviso ainda piscava.
- Mover todas as janelas do MenuBarAgent: ele também desenha a barra de menu, que ficou piscando bugada.

## Watch out
Mover só a janela de tamanho exato 367x154. Os nomes dos processos vêm localizados em português ("Central de Controle").

In the code:
- Sources/Ilha/NativePopupGuard.swift (watch, windowCreated, burst)
- Sources/Ilha/StatusIcon.swift (ícone Wi-Fi/bateria, eventos IOPS e CoreWLAN)
