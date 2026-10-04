# Monitora a VPS durante o teste (CPU, RAM, carga, conexões do Postgres, processos Node/Python)
# Uso: .\scripts\monitorar-vps.ps1 -Servidor vps-locaweb [-Intervalo 5]
# Pare com Ctrl+C quando o teste terminar.
param(
    [Parameter(Mandatory = $true)][string]$Servidor,
    [int]$Intervalo = 5
)
$raiz = Split-Path -Parent $PSScriptRoot
$carimbo = Get-Date -Format 'yyyy-MM-dd_HH-mm'
$arquivo = Join-Path $raiz "resultados\monitor-vps-$carimbo.csv"
New-Item -ItemType Directory -Force -Path (Split-Path $arquivo) | Out-Null

$remoto = @"
echo 'hora,cpu_uso_pct,ram_usada_mb,ram_total_mb,swap_usada_mb,load_1min,conexoes_pg,cpu_node_pct,cpu_python_pct,cpu_postgres_pct'
while true; do
  cpu=`$(top -bn1 | awk -F',' '/Cpu\(s\)/ {for(i=1;i<=NF;i++) if(`$i ~ /id/){gsub(/[^0-9.]/,"",`$i); printf "%.1f", 100-`$i}}')
  read ru rt <<< `$(free -m | awk '/Mem:/ {print `$3, `$2}')
  su=`$(free -m | awk '/Swap:/ {print `$3}')
  ld=`$(cut -d' ' -f1 /proc/loadavg)
  pg=`$( (sudo -n -u postgres psql -tAc 'select count(*) from pg_stat_activity' 2>/dev/null || echo NA) | tr -d ' ')
  cn=`$(ps -C node -o %cpu= 2>/dev/null | awk '{s+=`$1} END {printf "%.1f", s}')
  cp=`$(ps -eo comm,%cpu | awk '/^python/ {s+=`$2} END {printf "%.1f", s}')
  cg=`$(ps -C postgres -o %cpu= 2>/dev/null | awk '{s+=`$1} END {printf "%.1f", s}')
  echo "`$(date +%H:%M:%S),`$cpu,`$ru,`$rt,`$su,`$ld,`$pg,`$cn,`$cp,`$cg"
  sleep $Intervalo
done
"@ -replace "`r", ""

Write-Host "Monitorando $Servidor a cada $Intervalo s. Salvando em $arquivo" -ForegroundColor Cyan
Write-Host "Ctrl+C para parar." -ForegroundColor Yellow
$remoto | ssh -o ServerAliveInterval=30 $Servidor "bash -s" | Tee-Object -FilePath $arquivo
