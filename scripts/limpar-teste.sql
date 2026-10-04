-- Limpeza dos registros criados pelo teste de carga
-- AJUSTE os nomes das tabelas para os nomes reais do banco (descobertos na etapa 2).
-- Rodar na VPS:  sudo -u postgres psql -d NOME_DO_BANCO -f limpar-teste.sql

\echo '== Registros de teste ANTES da limpeza =='
SELECT 'vagas'       AS tabela, count(*) FROM vagas       WHERE teste_carga = true
UNION ALL
SELECT 'prestadores',            count(*) FROM prestadores WHERE teste_carga = true
UNION ALL
SELECT 'alertas',                count(*) FROM alertas     WHERE teste_carga = true
UNION ALL
SELECT 'candidaturas',           count(*) FROM candidaturas WHERE teste_carga = true;

BEGIN;

-- Candidaturas primeiro (podem ter chave estrangeira para vagas)
DELETE FROM candidaturas WHERE teste_carga = true;
DELETE FROM vagas        WHERE teste_carga = true;
DELETE FROM prestadores  WHERE teste_carga = true;
DELETE FROM alertas      WHERE teste_carga = true;

\echo '== Registros de teste DEPOIS da limpeza (tudo deve ser 0) =='
SELECT 'vagas'       AS tabela, count(*) FROM vagas       WHERE teste_carga = true
UNION ALL
SELECT 'prestadores',            count(*) FROM prestadores WHERE teste_carga = true
UNION ALL
SELECT 'alertas',                count(*) FROM alertas     WHERE teste_carga = true
UNION ALL
SELECT 'candidaturas',           count(*) FROM candidaturas WHERE teste_carga = true;

COMMIT;

-- Recupera espaço e atualiza estatísticas depois de apagar muitos registros
VACUUM ANALYZE vagas;
VACUUM ANALYZE prestadores;
VACUUM ANALYZE alertas;
VACUUM ANALYZE candidaturas;
