# teste-carga-site

Skill do Claude Code para fazer **teste de carga** em sites. Ela simula mais de 1000 usuários simultâneos com o [k6](https://k6.io), rodando no seu PC Windows, e descobre até onde o site aguenta e qual é o gargalo.

Foi feita para o [Emprega Vale+](https://empregavalemais.com.br), mas serve para outros sites que sejam seus.

## O que ela faz

- Simula o fluxo completo de um visitante: página inicial, filtro por cidade, busca, página da vaga e prestadores de serviço.
- Testa os cadastros: candidatura com PDF, alerta de vagas por WhatsApp, cadastro de vaga e cadastro de prestador.
- Sobe os acessos aos poucos até **1500 usuários simultâneos** (cerca de 25 minutos).
- Usa um **modo teste** no backend: os cadastros do teste ficam marcados, não enviam e-mail nem WhatsApp, não viram post nas redes e não aparecem no site.
- Monitora CPU, memória e conexões do PostgreSQL da VPS durante o teste.
- Apaga os dados de teste no final e gera um relatório com o limite do site e as melhorias sugeridas.

## Instalação

### Claude Code (PC)
Clone o repositório dentro da pasta de skills do Claude Code:

```powershell
git clone https://github.com/Andreluizys/teste-carga-site "$env:USERPROFILE\.claude\skills\teste-carga-site"
```

### Claude.ai
Baixe o repositório como ZIP (botão **Code > Download ZIP**) e envie na área de Skills das configurações do Claude.

## Como usar

No Claude Code, peça:

> Faz o teste de carga do Emprega Vale+

Ou chame direto:

```
/teste-carga-site
```

A skill conduz tudo em etapas e pede confirmação antes de mexer no servidor, rodar o teste ou apagar dados.

## Requisitos

- Windows com PowerShell
- k6 (o script `scripts/preparar-pc.ps1` instala via winget)
- Acesso SSH com chave à VPS onde o site roda
- Site hospedado em VPS com Node e/ou Python e PostgreSQL

## Estrutura

```
SKILL.md                          instruções da skill
scripts/
  preparar-pc.ps1                 instala k6 e prepara pastas
  rotas.exemplo.json              modelo das rotas do site
  fluxo-completo.js               script k6 (fluxo + rampa até 1500 usuários)
  rodar-teste.ps1                 roda o teste (normal ou fumaça)
  monitorar-vps.ps1               monitora a VPS durante o teste
  limpar-teste.sql                apaga os registros de teste
references/
  modo-teste-backend.md           como criar o modo teste (Node e Python)
  interpretar-resultados.md       como ler os resultados e achar o gargalo
assets/
  curriculo-teste.pdf             PDF usado nas candidaturas de teste
```

## Avisos

- Só faça teste de carga em site seu ou com autorização do dono.
- Avise a hospedagem antes (dia, horário e IP), para a proteção anti-DDoS não bloquear o teste.
- Durante o pico, o site pode ficar lento ou fora do ar para usuários reais.
- O token do modo teste nunca vai para o repositório: ele fica só no servidor e no seu PC.

## Licença

MIT
