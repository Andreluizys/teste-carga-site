---
name: teste-carga-site
description: Teste de carga (load test) do site Emprega Vale+ (empregavalemais.com.br) ou de outro site do André, simulando mais de 1000 usuários simultâneos com k6 rodando no PC Windows. Cobre o fluxo completo (navegar, buscar por cidade, abrir vaga, candidatura, alerta de WhatsApp, cadastro de vaga e de prestador) com "modo teste" no backend para não disparar e-mail/WhatsApp nem publicar nada. Use esta skill sempre que o André falar em teste de carga, teste de estresse, "ver se o site aguenta", "quantos acessos o site suporta", simular acessos, k6, gargalo, site lento ou caindo com muita gente, mesmo que ele não use a palavra "carga".
---

# Teste de carga do site (k6 + modo teste)

Objetivo: descobrir o limite real do site subindo os acessos aos poucos até 1000+ usuários
simultâneos, sem enviar nada de verdade para recrutadores, empresas ou inscritos.

Decisões já tomadas com o André (não pergunte de novo, a menos que ele mude):
- Site: Emprega Vale+ (empregavalemais.com.br), na VPS Locaweb, backend Node e Python, banco PostgreSQL na própria VPS.
- O código do site está SÓ na VPS (acesso via SSH com chave).
- O teste roda no PC Windows do André, pelo Claude Code.
- Fluxo completo: navegação, busca/filtro por cidade, página da vaga, candidatura, inscrição no alerta de WhatsApp, cadastro de vaga (empresa), cadastro de prestador de serviço.
- Disparos reais são bloqueados por um "modo teste" no backend.
- Registros de teste são marcados e apagados no final.
- Roda em horário comercial e vai até o fim (sem parada automática) para achar o limite real.
- Os acessos sobem aos poucos (rampa) até 1500 usuários virtuais.

Regra do André: antes de cada decisão que não esteja acima (alterar código na VPS, reiniciar
serviço, rodar o teste, apagar dados), faça perguntas claras e espere a resposta. Não mande
prints da tela. Entregue sempre arquivos completos.

## Etapas

Siga na ordem. Não pule a etapa 2: sem modo teste, mil candidaturas falsas iriam para empresas reais.

### 1. Preparar o PC Windows
Rode `scripts/preparar-pc.ps1` no PowerShell. Ele instala o k6 via winget (se faltar), confere a
versão e cria a pasta `resultados/`. Confirme que `ssh vps-locaweb` (ou o alias que o André usa)
conecta sem senha. Se não conectar, pergunte qual é o host/usuário antes de continuar.

### 2. Implementar o modo teste no backend (na VPS)
Leia `references/modo-teste-backend.md` e siga o passo a passo. Resumo:
1. Backup do banco (`pg_dump`) e do código antes de mexer.
2. Mapear pelo SSH todas as rotas dos 4 cadastros e da listagem/busca, e onde ficam os envios (e-mail, WhatsApp API, Meta Graph API, script de posts do Instagram).
3. Criar a coluna `teste_carga` nas tabelas que recebem cadastro.
4. Middleware que reconhece o header `X-Load-Test` com o token secreto (variável `LOAD_TEST_TOKEN` no servidor).
5. Com o modo teste ativo: grava com `teste_carga = true`, não envia e-mail/WhatsApp, não dispara post nas redes, e as listagens públicas escondem registros de teste.
6. Testar com 1 requisição manual de cada cadastro (curl) e conferir no banco que nada foi enviado.
Mostre ao André o diff de cada arquivo antes de salvar e peça confirmação para reiniciar o serviço.

### 3. Preencher a configuração das rotas
Copie `scripts/rotas.exemplo.json` para `scripts/rotas.json` e preencha com as rotas reais
descobertas na etapa 2 (caminhos, nomes dos campos, regex para pegar IDs de vagas, lista de cidades).
Rode um teste de fumaça com 1 usuário:
```powershell
.\scripts\rodar-teste.ps1 -Fumaca
```
Todas as checagens precisam passar antes do teste grande. Se alguma falhar, corrija o `rotas.json`.

### 4. Avisar a Locaweb
Lembre o André de abrir chamado na Locaweb informando data, horário e o IP do PC dele, para a
proteção anti-DDoS não bloquear o teste. Pergunte se já avisou antes de seguir.

### 5. Rodar o teste
Em dois terminais:
```powershell
# Terminal 1 — monitora CPU, memória e conexões do Postgres na VPS
.\scripts\monitorar-vps.ps1 -Servidor vps-locaweb

# Terminal 2 — teste de carga (rampa até 1500 usuários, ~25 min)
.\scripts\rodar-teste.ps1
```
O k6 abre um painel ao vivo em http://localhost:5665 e salva o relatório HTML em `resultados/`.
Como o teste roda em horário comercial e vai até o fim, avise o André que o site pode ficar
lento ou fora do ar para usuários reais durante o pico. Ele pode interromper com Ctrl+C a qualquer momento.

### 6. Limpar os dados de teste
Rode `scripts/limpar-teste.sql` na VPS (comandos em `references/modo-teste-backend.md`, seção
Limpeza). Mostre a contagem de registros antes de apagar e peça confirmação.

### 7. Relatório para o André
Leia `references/interpretar-resultados.md` e entregue um resumo em português simples:
- Até quantos usuários simultâneos o site respondeu bem (p95 abaixo de 2s e erros abaixo de 1%).
- Em que ponto começou a degradar e em que ponto quebrou.
- Qual foi o gargalo (CPU, memória, conexões do Postgres, Node, Python) cruzando com o log do monitor.
- 3 a 5 melhorias concretas, em ordem de impacto.

## Arquivos
- `scripts/preparar-pc.ps1` — instala k6 e prepara pastas no Windows.
- `scripts/rotas.exemplo.json` — modelo de configuração das rotas do site.
- `scripts/fluxo-completo.js` — script k6 com o fluxo completo e a rampa até 1500 usuários.
- `scripts/rodar-teste.ps1` — roda o teste (normal ou fumaça) e salva relatórios.
- `scripts/monitorar-vps.ps1` — registra CPU, RAM e conexões do Postgres da VPS durante o teste.
- `scripts/limpar-teste.sql` — apaga registros marcados como teste.
- `assets/curriculo-teste.pdf` — PDF mínimo usado nas candidaturas.
- `references/modo-teste-backend.md` — como implementar o modo teste (Node e Python) e a limpeza.
- `references/interpretar-resultados.md` — como ler as métricas e achar o gargalo.

## Usar em outro site
Para outro site do André, refaça as etapas 2 e 3 para aquele site (as rotas e os envios mudam).
Confirme antes que o site é dele ou que há autorização do dono, e que a hospedagem permite teste de carga.
