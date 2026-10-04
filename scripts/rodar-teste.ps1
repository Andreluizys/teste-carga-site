# Roda o teste de carga
# Uso:
#   .\scripts\rodar-teste.ps1 -Fumaca      # 1 usuário, testa todas as rotas e cadastros
#   .\scripts\rodar-teste.ps1              # rampa completa até 1500 usuários
param(
    [switch]$Fumaca,
    [string]$Token = $env:LOAD_TEST_TOKEN
)
$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot

if (-not $Token) {
    $seguro = Read-Host "Token do modo teste (LOAD_TEST_TOKEN da VPS)" -AsSecureString
    $Token = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($seguro))
}

if (-not (Test-Path (Join-Path $PSScriptRoot 'rotas.json'))) {
    throw "scripts\rotas.json não existe. Rode preparar-pc.ps1 e preencha as rotas."
}

$carimbo = Get-Date -Format 'yyyy-MM-dd_HH-mm'
$tipo = if ($Fumaca) { 'fumaca' } else { 'carga' }
$saida = Join-Path $raiz "resultados\$carimbo-$tipo"
New-Item -ItemType Directory -Force -Path $saida | Out-Null

$argumentos = @('run', '-e', "TOKEN=$Token", '-e', "SAIDA=$saida")
if ($Fumaca) {
    $argumentos += @('-e', 'FUMACA=1')
} else {
    # Painel ao vivo em http://localhost:5665 e relatório HTML no final
    $env:K6_WEB_DASHBOARD = 'true'
    $env:K6_WEB_DASHBOARD_OPEN = 'true'
    $env:K6_WEB_DASHBOARD_EXPORT = (Join-Path $saida 'relatorio.html')
    $argumentos += @('--out', "csv=$(Join-Path $saida 'metricas.csv.gz')")
    Write-Host "Teste completo: ~25 minutos, rampa até 1500 usuários. Ctrl+C interrompe." -ForegroundColor Yellow
}
$argumentos += 'fluxo-completo.js'

Push-Location $PSScriptRoot
try {
    & k6 @argumentos
    $codigo = $LASTEXITCODE
} finally {
    Pop-Location
    Remove-Item Env:K6_WEB_DASHBOARD, Env:K6_WEB_DASHBOARD_OPEN, Env:K6_WEB_DASHBOARD_EXPORT -ErrorAction SilentlyContinue
}

Write-Host "`nResultados em: $saida" -ForegroundColor Cyan
if ($Fumaca) {
    if ($codigo -eq 0) { Write-Host "Teste de fumaça OK. Pode rodar o teste completo." -ForegroundColor Green }
    else { Write-Host "Teste de fumaça falhou. Corrija o rotas.json antes do teste completo." -ForegroundColor Red }
}
# Código 99 = limites (thresholds) ultrapassados: esperado quando o site atinge o limite.
if (-not $Fumaca -and $codigo -eq 99) {
    Write-Host "O site passou dos limites de qualidade em algum momento (esperado num teste até o limite)." -ForegroundColor Yellow
}
