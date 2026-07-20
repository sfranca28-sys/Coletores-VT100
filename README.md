# ADVPL VT100 Production Collector

Sistema para coletores de dados via **Telnet (VT100)** desenvolvido em **ADVPL/TL++** para o ERP **TOTVS Protheus**.

O projeto demonstra como desenvolver aplicações de terminal para coletores industriais utilizando a biblioteca VT100 do Protheus, realizando autenticação de operadores, consulta e apontamento de Ordens de Produção diretamente no ERP.

---

## Características

- Login de operadores
- Interface VT100 para coletores
- Navegação por menus
- Consulta de Ordens de Produção
- Início de Produção
- Encerramento de Produção
- Geração automática de apontamentos utilizando MATA681
- Integração com tabelas padrão do Protheus
- Utilização de MSExecAuto
- Tratamento de erros
- Controle de sessão

---

## Fluxo da aplicação

```text
          Login
            │
            ▼
        Menu Principal
      ┌───────────────┐
      │               │
      ▼               ▼
 Apontamento      Consulta OP
      │               │
      ▼               │
 Verifica OP          │
      │               │
      ▼               │
Existe apontamento?
      │
 ┌────┴────┐
 │         │
 ▼         ▼
Inicia   Finaliza
 OP        OP
             │
             ▼
         MATA681
             │
             ▼
          SH6 / Z03
```

---

## Funcionalidades

### Login

Autenticação do operador utilizando a tabela **SZ1**.

Após autenticação:

- muda automaticamente a filial
- abre os arquivos necessários
- prepara o ambiente da sessão

---

### Menu

Após login o operador pode escolher:

```
1 - Apontamento
2 - Consulta
```

---

### Consulta de OP

Permite visualizar:

- Quantidade original
- Quantidade apontada
- Quantidade restante

---

### Início da Produção

Solicita:

- Operador 2 (opcional)
- Recurso
- Ferramenta

Grava os dados na tabela **Z03**.

---

### Finalização da Produção

Solicita:

- Quantidade produzida

Realiza:

- cálculo das etiquetas
- gravação da produção
- geração automática do apontamento via MATA681

---

## Estrutura das funções

| Função | Descrição |
|---------|-----------|
| ACDEMP | Inicialização da aplicação |
| PrepararAmbiente | Configura ambiente RPC |
| LoginOpe | Tela de Login |
| ValidOper | Validação do operador |
| MenuOpc | Menu principal |
| ValidaOP | Decide iniciar ou finalizar OP |
| ConsultaOP | Consulta saldo da OP |
| IniciaOP | Início da produção |
| ApontaOP | Finalização da produção |
| ValidQtd | Validação da quantidade |
| ValidRecurs | Validação do recurso |
| GrvApont | Executa o MATA681 |

---

## Tabelas utilizadas

### Padrão Protheus

- SC2
- SH1
- SH6
- SG2
- SB1

### Customizadas

- SZ1
- Z03

---

## Tecnologias

- ADVPL
- TL++
- VT100
- Telnet
- Protheus
- MSExecAuto
- MATA681
- SQL

---

## Requisitos

- ERP Protheus
- AppServer configurado para Telnet
- Biblioteca APVT100.CH
- Acesso RPC
- Cadastro de Operadores (SZ1)
- Recursos cadastrados (SH1)

---

## Exemplo de utilização

```
LOGIN

↓

MENU

↓

Apontamento

↓

Leitura da OP

↓

Iniciar Produção

↓

Finalizar Produção

↓

Apontamento automático no Protheus
```

---

## Objetivo

Este projeto demonstra como construir aplicações industriais para coletores de dados utilizando apenas recursos nativos do ADVPL e do Protheus, dispensando interfaces gráficas e permitindo integração direta com processos produtivos.

---

## Autor

Silvano França

Especialista em desenvolvimento ADVPL / TL++ para TOTVS Protheus.
