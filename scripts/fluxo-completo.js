// Teste de carga — fluxo completo (navegar, buscar, abrir vaga, cadastros)
// Uso: k6 run -e TOKEN=xxx [-e FUMACA=1] [-e ROTAS=rotas.json] fluxo-completo.js
import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Counter, Trend, Rate } from 'k6/metrics';

const ROTAS = JSON.parse(open(__ENV.ROTAS || './rotas.json'));
const PDF = open('../assets/curriculo-teste.pdf', 'b');
const TOKEN = __ENV.TOKEN || '';
const FUMACA = __ENV.FUMACA === '1';

if (!TOKEN) {
  throw new Error('Defina o token do modo teste: -e TOKEN=... (o mesmo LOAD_TEST_TOKEN da VPS)');
}

// ---------- Métricas próprias ----------
const tempoCadastro = new Trend('tempo_cadastro', true);
const tempoPagina = new Trend('tempo_pagina', true);
const falhaCadastro = new Rate('falha_cadastro');
const cadastrosFeitos = new Counter('cadastros_feitos');

// ---------- Cenário ----------
// Rampa até 1500 usuários (~25 min). Sem abortOnFail: vai até o fim para achar o limite real.
export const options = FUMACA
  ? { vus: 1, iterations: 1, thresholds: { checks: ['rate==1'] } }
  : {
      scenarios: {
        rampa: {
          executor: 'ramping-vus',
          startVUs: 0,
          stages: [
            { duration: '2m', target: 100 },
            { duration: '3m', target: 300 },
            { duration: '3m', target: 600 },
            { duration: '3m', target: 1000 },
            { duration: '3m', target: 1250 },
            { duration: '3m', target: 1500 },
            { duration: '5m', target: 1500 }, // segura o pico
            { duration: '3m', target: 0 },
          ],
          gracefulRampDown: '30s',
        },
      },
      // Só para marcar no relatório; não interrompe o teste.
      thresholds: {
        http_req_failed: ['rate<0.01'],
        http_req_duration: ['p(95)<2000'],
        falha_cadastro: ['rate<0.01'],
      },
      summaryTrendStats: ['avg', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
      noConnectionReuse: false,
      userAgent: 'k6-teste-carga-emprega-vale',
    };

// ---------- Utilitários ----------
const HEADERS = { 'X-Load-Test': TOKEN };
const sorteia = (lista) => lista[Math.floor(Math.random() * lista.length)];
const pausa = (min, max) => sleep(min + Math.random() * (max - min));

function preenche(texto, ctx) {
  return String(texto).replace(/\{\{(\w+)\}\}/g, (_, k) => (ctx[k] !== undefined ? ctx[k] : ''));
}

function preencheObj(obj, ctx) {
  const saida = {};
  for (const [k, v] of Object.entries(obj)) {
    if (Array.isArray(v)) saida[k] = v.map((x) => preenche(x, ctx));
    else saida[k] = preenche(v, ctx);
  }
  return saida;
}

function url(caminho, ctx) {
  return ROTAS.baseUrl.replace(/\/$/, '') + preenche(caminho, ctx);
}

function abre(nome, caminho, ctx) {
  const res = http.get(url(caminho, ctx), { headers: HEADERS, tags: { pagina: nome } });
  tempoPagina.add(res.timings.duration, { pagina: nome });
  check(res, { [`${nome}: status 200`]: (r) => r.status === 200 });
  return res;
}

function extraiVagaIds(corpo) {
  const ids = [];
  if (!corpo) return ids;
  const re = new RegExp(ROTAS.listaVagas.regexId, 'g');
  let m;
  while ((m = re.exec(corpo)) !== null && ids.length < 50) ids.push(m[1]);
  return ids;
}

function escolheCadastro() {
  // Pesos em % do total de iterações; o resto só navega.
  const sorteio = Math.random() * 100;
  let acumulado = 0;
  for (const [nome, cfg] of Object.entries(ROTAS.cadastros)) {
    acumulado += cfg.peso;
    if (sorteio < acumulado) return nome;
  }
  return null;
}

function cadastra(nome, ctx) {
  const cfg = ROTAS.cadastros[nome];
  const campos = preencheObj(cfg.campos, ctx);
  let corpo;
  let params = { headers: Object.assign({}, HEADERS), tags: { cadastro: nome } };

  if (cfg.tipo === 'json') {
    corpo = JSON.stringify(campos);
    params.headers['Content-Type'] = 'application/json';
  } else if (cfg.tipo === 'multipart') {
    corpo = Object.assign({}, campos);
    if (cfg.campoArquivo) {
      corpo[cfg.campoArquivo] = http.file(PDF, `curriculo-teste-${ctx.n}.pdf`, 'application/pdf');
    }
  } else {
    corpo = campos; // application/x-www-form-urlencoded
  }

  const res = http.request(cfg.method, url(cfg.path, ctx), corpo, params);
  const ok = cfg.statusOk.includes(res.status);
  tempoCadastro.add(res.timings.duration, { cadastro: nome });
  falhaCadastro.add(!ok, { cadastro: nome });
  if (ok) cadastrosFeitos.add(1, { cadastro: nome });
  check(res, { [`cadastro ${nome}: aceito`]: () => ok });
  if (FUMACA && !ok) {
    console.error(`Cadastro ${nome} falhou: HTTP ${res.status} — ${String(res.body).slice(0, 300)}`);
  }
}

// ---------- Fluxo de cada usuário virtual ----------
export default function () {
  const ctx = {
    n: `${__VU}${__ITER}${Date.now() % 100000}`,
    cidade: sorteia(ROTAS.cidades),
    categoria: sorteia(ROTAS.categorias),
  };

  group('navegacao', () => {
    abre('home', ROTAS.navegacao.home, ctx);
    for (const e of ROTAS.navegacao.estaticos || []) abre('estatico', e, ctx);
    pausa(1, 3);

    abre('cidade', ROTAS.navegacao.cidade, ctx);
    pausa(1, 3);
  });

  let vagaIds = [];
  group('busca', () => {
    const res = abre('busca', ROTAS.navegacao.busca, ctx);
    const lista = http.get(url(ROTAS.listaVagas.path, ctx), { headers: HEADERS, tags: { pagina: 'lista_vagas' } });
    vagaIds = extraiVagaIds(lista.body).concat(extraiVagaIds(res.body));
    pausa(2, 4);
  });

  if (vagaIds.length > 0) {
    ctx.vagaId = sorteia(vagaIds);
    group('vaga', () => {
      abre('vaga', ROTAS.navegacao.vaga, ctx);
      pausa(3, 6);
    });
  }

  if (Math.random() < 0.2) {
    group('prestadores', () => {
      abre('prestadores', ROTAS.navegacao.prestadores, ctx);
      pausa(1, 3);
    });
  }

  // No teste de fumaça, testa todos os cadastros; no teste grande, sorteia por peso.
  const cadastros = FUMACA ? Object.keys(ROTAS.cadastros) : [escolheCadastro()].filter(Boolean);
  for (const nome of cadastros) {
    if (nome === 'candidatura' && !ctx.vagaId) {
      if (FUMACA) console.error('Nenhum ID de vaga encontrado: confira listaVagas.regexId no rotas.json');
      continue;
    }
    group(`cadastro_${nome}`, () => {
      cadastra(nome, ctx);
      pausa(1, 2);
    });
  }
}

export function handleSummary(data) {
  const m = data.metrics;
  const v = (nome, campo) => (m[nome] && m[nome].values[campo] !== undefined ? m[nome].values[campo] : 0);
  const resumo = [
    '===== RESUMO DO TESTE DE CARGA =====',
    `Requisições totais:       ${v('http_reqs', 'count')}`,
    `Requisições por segundo:  ${v('http_reqs', 'rate').toFixed(1)}`,
    `Taxa de erro HTTP:        ${(v('http_req_failed', 'rate') * 100).toFixed(2)}%`,
    `Tempo médio:              ${v('http_req_duration', 'avg').toFixed(0)} ms`,
    `Tempo p95:                ${v('http_req_duration', 'p(95)').toFixed(0)} ms`,
    `Tempo máximo:             ${v('http_req_duration', 'max').toFixed(0)} ms`,
    `Cadastros aceitos:        ${v('cadastros_feitos', 'count')}`,
    `Falha nos cadastros:      ${(v('falha_cadastro', 'rate') * 100).toFixed(2)}%`,
    `Pico de usuários:         ${v('vus_max', 'max')}`,
    '====================================',
    '',
  ].join('\n');
  const pasta = __ENV.SAIDA || '../resultados';
  return {
    stdout: resumo,
    [`${pasta}/resumo.json`]: JSON.stringify(data, null, 2),
    [`${pasta}/resumo.txt`]: resumo,
  };
}
