# Modo teste no backend (VPS Locaweb)

Objetivo: o site processa os cadastros de teste normalmente (para medir o desempenho real),
mas não envia nada para fora e não mostra nada de teste ao público.

Peça confirmação ao André antes de cada alteração e antes de reiniciar qualquer serviço.

## 1. Backup antes de mexer
```bash
# Na VPS
mkdir -p ~/backups
sudo -u postgres pg_dump -Fc NOME_DO_BANCO > ~/backups/antes-teste-carga-$(date +%F).dump
tar czf ~/backups/codigo-antes-teste-carga-$(date +%F).tgz /caminho/do/site
```

## 2. Mapear o que existe
Descubra e anote (mostre ao André):
- Processos e portas: `pm2 ls`, `systemctl list-units --type=service | grep -Ei 'node|python|gunicorn|uvicorn'`, `ss -tlnp`.
- Proxy na frente: `ls /etc/nginx/sites-enabled/` (rotas `/api` costumam ir para Node ou Python).
- Rotas dos 4 cadastros: `grep -rnE "post\(|@app\.(post|route)|@router\.post|APIRouter" /caminho/do/site --include=*.js --include=*.ts --include=*.py`.
- Listagens públicas (home, cidade, busca, vaga, prestadores).
- Todos os pontos de envio externo:
  - e-mail: `grep -rniE "nodemailer|sendMail|smtplib|send_mail|resend|sendgrid"`
  - WhatsApp: `grep -rniE "graph.facebook.com.*/messages|whatsapp"`
  - Facebook/Instagram: `grep -rniE "graph.facebook.com|/feed|/media_publish"`
  - Scripts agendados: `crontab -l`, `ls /etc/cron.d`, timers do systemd, pm2 cron.
- Tabelas: `sudo -u postgres psql -d NOME_DO_BANCO -c '\dt'`.

## 3. Coluna de marcação
Para cada tabela que recebe cadastro (vagas, prestadores, alertas e candidaturas se forem gravadas):
```sql
ALTER TABLE vagas       ADD COLUMN IF NOT EXISTS teste_carga BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE prestadores ADD COLUMN IF NOT EXISTS teste_carga BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE alertas     ADD COLUMN IF NOT EXISTS teste_carga BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX IF NOT EXISTS idx_vagas_teste_carga ON vagas (teste_carga) WHERE teste_carga;
```
Candidaturas: se o site não grava candidatura (só envia o currículo por e-mail/WhatsApp), crie uma
tabela simples só para o teste, assim a gravação ainda pesa no banco como pesaria um envio real:
```sql
CREATE TABLE IF NOT EXISTS candidaturas (
  id BIGSERIAL PRIMARY KEY,
  vaga_id TEXT,
  nome TEXT, email TEXT, whatsapp TEXT,
  tamanho_curriculo INTEGER,
  teste_carga BOOLEAN NOT NULL DEFAULT false,
  criado_em TIMESTAMPTZ DEFAULT now()
);
```
Se já existir uma tabela de candidaturas com outro nome, use a existente e ajuste `limpar-teste.sql`.

## 4. Token secreto
Gere um token e guarde só no servidor e no PC do André (nunca no código):
```bash
openssl rand -hex 32
```
Adicione `LOAD_TEST_TOKEN=<token>` ao `.env` de cada serviço (Node e Python) ou ao `ecosystem.config.js` do pm2.

## 5. Middleware — Node (Express)
```js
// modo-teste.js
const crypto = require('crypto');

function modoTeste(req, res, next) {
  const esperado = process.env.LOAD_TEST_TOKEN || '';
  const recebido = req.get('X-Load-Test') || '';
  req.modoTeste =
    esperado.length > 0 &&
    recebido.length === esperado.length &&
    crypto.timingSafeEqual(Buffer.from(recebido), Buffer.from(esperado));
  next();
}
module.exports = { modoTeste };
```
```js
// app.js — registrar ANTES das rotas
const { modoTeste } = require('./modo-teste');
app.use(modoTeste);
```
Nas rotas de cadastro:
```js
// ao gravar
await db.query('INSERT INTO vagas (..., teste_carga) VALUES (..., $N)', [..., req.modoTeste]);

// no lugar de cada envio externo
if (!req.modoTeste) {
  await enviarEmail(...);          // ou WhatsApp, Graph API etc.
}

// candidatura no modo teste: grava na tabela e responde sucesso, sem enviar
if (req.modoTeste) {
  await db.query(
    'INSERT INTO candidaturas (vaga_id, nome, email, whatsapp, tamanho_curriculo, teste_carga) VALUES ($1,$2,$3,$4,$5,true)',
    [req.params.id, req.body.nome, req.body.email, req.body.whatsapp, req.file ? req.file.size : 0]
  );
  return res.status(201).json({ ok: true });
}
```
Arquivos enviados no modo teste (currículo PDF): processe o upload normalmente (é parte do custo
real) mas apague o arquivo logo depois, ou use `multer.memoryStorage()` só no modo teste.

## 6. Middleware — Python
FastAPI:
```python
import hmac, os
from fastapi import Request

TOKEN = os.getenv("LOAD_TEST_TOKEN", "")

@app.middleware("http")
async def modo_teste(request: Request, call_next):
    recebido = request.headers.get("X-Load-Test", "")
    request.state.modo_teste = bool(TOKEN) and hmac.compare_digest(recebido, TOKEN)
    return await call_next(request)

# nas rotas: if not request.state.modo_teste: enviar(...)
```
Flask:
```python
import hmac, os
from flask import g, request

TOKEN = os.getenv("LOAD_TEST_TOKEN", "")

@app.before_request
def modo_teste():
    g.modo_teste = bool(TOKEN) and hmac.compare_digest(request.headers.get("X-Load-Test", ""), TOKEN)

# nas rotas: if not g.modo_teste: enviar(...)
```

## 7. Esconder registros de teste do público
Em TODA consulta pública (home, cidade, busca, feed, vaga, prestadores, sitemap, contagens) acrescente
`AND teste_carga = false`. Exemplo:
```sql
SELECT ... FROM vagas WHERE cidade = $1 AND teste_carga = false ORDER BY ...
```
Abrir uma vaga de teste pelo ID deve dar 404 para quem não está no modo teste.

## 8. Automações agendadas (muito importante)
Os scripts que leem o banco e publicam ou notificam precisam ignorar registros de teste:
- script de posts do Instagram por cidade;
- post automático no Facebook a cada vaga nova;
- alerta de WhatsApp para inscritos quando entra vaga nova (não pode avisar inscritos reais sobre vagas de teste, nem avisar os inscritos de teste).
Acrescente `teste_carga = false` nas consultas deles. Se algum disparo acontece no próprio momento
do cadastro (gatilho/evento), proteja com `if (!req.modoTeste)`.

## 9. Validar com 1 requisição de cada
```bash
TOKEN=<token>
curl -i -X POST https://empregavalemais.com.br/api/alertas \
  -H "X-Load-Test: $TOKEN" -H 'Content-Type: application/json' \
  -d '{"whatsapp":"12999000001","cidade":"taubate"}'
```
Depois confira:
- o registro está no banco com `teste_carga = true`;
- não apareceu na listagem pública;
- não saiu e-mail, WhatsApp nem post (logs do serviço e caixa de saída);
- sem o header, o comportamento do site continua igual ao de antes.

## Limpeza (depois do teste)
```bash
scp scripts/limpar-teste.sql vps-locaweb:/tmp/
ssh vps-locaweb "sudo -u postgres psql -d NOME_DO_BANCO -f /tmp/limpar-teste.sql"
```
Mostre a contagem "ANTES" ao André e peça confirmação. Depois, pergunte se ele quer manter o modo
teste no código (para testes futuros) ou removê-lo. Se mantiver, o token pode ser trocado a cada teste.
