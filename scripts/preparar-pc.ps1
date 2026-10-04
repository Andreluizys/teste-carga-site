# Prepara o PC Windows para o teste de carga
# Uso: .\scripts\preparar-pc.ps1
$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSScriptRoot

Write-Host "== Verificando k6 ==" -ForegroundColor Cyan
if (-not (Get-Command k6 -ErrorAction SilentlyContinue)) {
    Write-Host "k6 não encontrado. Instalando via winget..."
    winget install --id GrafanaLabs.k6 -e --accept-source-agreements --accept-package-agreements
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('Path', 'User')
}
k6 version

Write-Host "`n== Verificando SSH ==" -ForegroundColor Cyan
if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    Write-Host "OpenSSH não encontrado. Instale em Configurações > Apps > Recursos opcionais > Cliente OpenSSH." -ForegroundColor Yellow
} else {
    Write-Host "SSH disponível."
}

Write-Host "`n== Pastas ==" -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path (Join-Path $raiz 'resultados') | Out-Null
Write-Host "Pasta resultados\ pronta."

$rotas = Join-Path $PSScriptRoot 'rotas.json'
if (-not (Test-Path $rotas)) {
    Copy-Item (Join-Path $PSScriptRoot 'rotas.exemplo.json') $rotas
    Write-Host "Criado scripts\rotas.json a partir do exemplo. Preencha com as rotas reais." -ForegroundColor Yellow
}

Write-Host "`n== Limites de rede do Windows ==" -ForegroundColor Cyan
# Com 1500 usuários o Windows pode ficar sem portas locais; amplia a faixa (precisa de admin).
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if ($admin) {
    netsh int ipv4 set dynamicport tcp start=10000 num=55000 | Out-Null
    Write-Host "Faixa de portas TCP ampliada (10000-65000)."
} else {
    Write-Host "Rode este script como Administrador uma vez para ampliar a faixa de portas TCP." -ForegroundColor Yellow
}

Write-Host "`nPronto." -ForegroundColor Green
