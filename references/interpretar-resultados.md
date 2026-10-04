# Como interpretar os resultados

Fontes:
- `resultados/<data>-carga/relatorio.html` — painel do k6 (gráficos por tempo).
- `resultados/<data>-carga/resumo.txt` e `resumo.json` — números finais.
- `resultados/<data>-carga/metricas.csv.gz` — todas as requisições, para cruzar com o horário.
- `resultados/monitor-vps-<data>.csv` — CPU, RAM e conexões do Postgres na VPS a cada 5 s.

## Métricas principais
- **Usuários virtuais (VUs)**: quantas pessoas simultâneas estavam sendo simuladas.
- **http_req_duration p95**: 95% das requisições foram mais rápidas que esse valor. É a principal.
- **http_req_failed**: % de requisições com erro (status 4xx/5xx ou falha de conexão).
- **tempo_cadastro / falha_cadastro**: desempenho só dos cadastros (os que mais pesam no banco).
- **http_reqs rate**: requisições por segundo. Se parar de crescer enquanto os VUs sobem, o site saturou.

## Faixas de referência
| Situação | p95 | Erros |
|---|---|---|
| Bom | abaixo de 1 s | abaixo de 0,1% |
| Aceitável | 1 a 2 s | abaixo de 1% |
| Degradando | 2 a 5 s | 1 a 5% |
| Quebrado | acima de 5 s ou timeouts | acima de 5% |

Dê ao André três números: **limite confortável** (último patamar "bom/aceitável"),
**início da degradação** e **ponto de quebra**, em usuários simultâneos.

## Achar o gargalo (cruzar horário do k6 com o monitor da VPS)
| O que aparece no monitor | Provável gargalo | Melhorias típicas |
|---|---|---|
| CPU perto de 100%, Node alto | Node em um só processo | pm2 em modo cluster (`-i max`), cache de páginas |
| CPU alto em Python | Python com poucos workers | aumentar workers do gunicorn/uvicorn |
| CPU alto em postgres | consultas lentas | índices em cidade/categoria/data, `EXPLAIN ANALYZE` |
| conexoes_pg batendo num teto fixo | pool/max_connections | ajustar pool no app, PgBouncer |
| RAM cheia e swap subindo | memória da VPS | reduzir workers, aumentar plano, cache |
| CPU baixa mas tempo alto e erros 502/504 | Nginx ou timeouts | `worker_connections`, `keepalive`, timeouts do proxy |
| Erros de conexão logo no começo, VPS tranquila | bloqueio anti-DDoS ou PC/internet do André | confirmar liberação na Locaweb; ver uso de upload do PC |

Atenção ao PC do André: se a CPU do PC passar de ~80% ou o upload da internet saturar, o
limite medido é do PC, não do site. Peça para ele observar o Gerenciador de Tarefas durante o pico
(sem mandar print). Se acontecer, o próximo teste pode rodar do servidor Ubuntu ou dividir a carga.

## Formato do relatório para o André
Português simples, curto:
1. Resultado em uma frase (ex.: "o site aguenta bem até ~600 pessoas ao mesmo tempo e cai perto de 1100").
2. Os três números (confortável, degradação, quebra).
3. O gargalo encontrado, com a evidência (ex.: "CPU do Node em 100% a partir das 14:12, quando havia ~650 usuários").
4. 3 a 5 melhorias em ordem de impacto, cada uma com o que muda e o esforço.
5. Sugestão de repetir o teste depois das melhorias para comparar.
