<#
.SYNOPSIS
    Desinstalador do Clonador de Voz Local — Windows 10/11.

.DESCRIPTION
    Equivalente ao scripts/uninstall.sh. O padrão remove o programa e preserva
    os dados. Isso é deliberado: `vozes\` guarda referências de voz, que são
    dado biométrico, e o cache de pesos são 1,8 GB que ninguém quer baixar de
    novo por acidente. Apagar qualquer um dos dois exige pedir explicitamente,
    e confirmar.

    O install.ps1 deixa uma cópia deste script dentro do prefixo, então
    desinstalar não depende de rede nem de ter o repositório em disco.

.EXAMPLE
    & "$env:LOCALAPPDATA\voice-clone\uninstall.ps1"

.EXAMPLE
    & "$env:LOCALAPPDATA\voice-clone\uninstall.ps1" -Simular

.EXAMPLE
    & "$env:LOCALAPPDATA\voice-clone\uninstall.ps1" -Tudo
#>
[CmdletBinding()]
param(
    [string]$Prefixo = $(if ($env:VOICE_CLONE_HOME) { $env:VOICE_CLONE_HOME } else { Join-Path $env:LOCALAPPDATA 'voice-clone' }),

    # Onde estão os atalhos. Vazio: o manifesto da instalação decide.
    [string]$Bin = '',

    # Remove também vozes\ e saida\.
    [switch]$RemoverDados,

    # Remove o cache de pesos do XTTS-v2 (~1,8 GB).
    [switch]$RemoverModelos,

    # As duas opções acima juntas.
    [switch]$Tudo,

    # Lista o que seria removido, sem remover nada.
    [switch]$Simular,

    # Não pergunta nada. Necessário para as opções destrutivas quando não há
    # console interativo.
    [switch]$Sim
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Tudo) { $RemoverDados = $true; $RemoverModelos = $true }

$Lancadores = @('voice-clone', 'voice-clone-web')

function Escrever-Passo($texto) { Write-Host "==> $texto" -ForegroundColor Green }
function Escrever-Aviso($texto) { Write-Host "aviso: $texto" -ForegroundColor Yellow }
function Parar($texto) { Write-Host "erro: $texto" -ForegroundColor Red; exit 1 }

# O manifesto sabe onde os atalhos foram criados; sem ele, cai no padrão.
function Ler-Manifesto {
    $manifesto = Join-Path $Prefixo '.install-manifest'
    if (-not (Test-Path $manifesto)) { return }
    foreach ($linha in Get-Content $manifesto) {
        if ($linha -match '^bin=(.+)$' -and -not $Bin) { $script:Bin = $Matches[1].Trim() }
        if ($linha -match '^lancadores=(.+)$') { $script:Lancadores = $Matches[1].Trim() -split '\s+' }
    }
}

# Onde o coqui-tts guarda os pesos, na mesma ordem que o trainer.io resolve.
function Diretorio-Modelos {
    if ($env:TTS_HOME) { return (Join-Path $env:TTS_HOME 'tts') }
    if ($env:XDG_DATA_HOME) { return (Join-Path $env:XDG_DATA_HOME 'tts') }
    return (Join-Path $env:LOCALAPPDATA 'tts')
}

function Tamanho($caminho) {
    if (-not (Test-Path $caminho)) { return '-' }
    # -Force em toda leitura: sem ele o Get-Item não enxerga item oculto, e
    # .install-manifest e .venv são justamente isso.
    $item = Get-Item $caminho -Force
    $bytes = 0
    if ($item.PSIsContainer) {
        # Diretório vazio: o Measure-Object não emite objeto nenhum, e ler .Sum
        # de $null é erro sob Set-StrictMode. saida/ recém-criado é esse caso.
        $medida = Get-ChildItem $caminho -Recurse -File -Force -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum
        if ($medida) { $bytes = [double]$medida.Sum }
    } else {
        $bytes = [double]$item.Length
    }
    if (-not $bytes) { return '0' }
    foreach ($unidade in @('B', 'K', 'M', 'G')) {
        if ($bytes -lt 1024 -or $unidade -eq 'G') { return ('{0:N1}{1}' -f $bytes, $unidade) }
        $bytes = $bytes / 1024
    }
}

function Remover($alvo) {
    if (-not (Test-Path $alvo)) { return }
    if ($Simular) {
        Write-Host "  removeria  $alvo  ($(Tamanho $alvo))"
        return
    }
    Remove-Item $alvo -Recurse -Force
    Write-Host "  removido   $alvo"
}

# Só remove um atalho que este projeto criou. Um voice-clone.cmd de outra
# origem no mesmo diretório não é nosso para apagar.
function Remover-Atalho($caminho) {
    if (-not (Test-Path $caminho)) { return }
    if (-not (Select-String -Path $caminho -Pattern 'install.ps1 do voice-clone' -Quiet -ErrorAction SilentlyContinue)) {
        Escrever-Aviso "$caminho não foi criado por este instalador — deixei como estava."
        return
    }
    Remover $caminho
}

function Confirmar($pergunta) {
    if ($Sim) { return }
    if ([Console]::IsInputRedirected) {
        Parar "$pergunta`n       A entrada não é um console, então não posso perguntar. Repita com`n       -Sim se é isso mesmo que você quer."
    }
    $resposta = Read-Host "$pergunta [digite sim para confirmar]"
    if ($resposta -notin @('sim', 'SIM', 'Sim')) {
        Write-Host 'Cancelado. Nada foi removido.'
        exit 1
    }
}

# --- execução --------------------------------------------------------------

Ler-Manifesto
if (-not $Bin) { $Bin = Join-Path $env:LOCALAPPDATA 'voice-clone\bin' }

if (-not $Prefixo -or $Prefixo -eq '\' -or $Prefixo -eq $env:USERPROFILE) {
    Parar "Prefixo inválido: '$Prefixo'"
}

$dirModelos = Diretorio-Modelos
$vozes = Join-Path $Prefixo 'vozes'
$saida = Join-Path $Prefixo 'saida'

if (-not (Test-Path $Prefixo)) {
    Escrever-Aviso "Não há instalação em $Prefixo."
    Write-Host 'Se você instalou em outro lugar, informe com -Prefixo.'
    # Os atalhos podem ter sobrado de uma remoção manual do prefixo.
    foreach ($nome in $Lancadores) { Remover-Atalho (Join-Path $Bin "$nome.cmd") }
    exit 0
}

# O prefixo pode ter sobrevivido a uma remoção anterior só por causa dos dados.
# Dizer "instalação encontrada" ali seria mentira.
if (Test-Path (Join-Path $Prefixo 'vozclone.py')) {
    Write-Host "Instalação encontrada em $Prefixo"
} else {
    Write-Host "Em $Prefixo não há programa instalado — só os seus dados."
}
$manifesto = Join-Path $Prefixo '.install-manifest'
if (Test-Path $manifesto) {
    Get-Content $manifesto | Where-Object { $_ -match '^(ref|commit|instalado_em)=' } | ForEach-Object { "  $_" }
}
Write-Host ''
Write-Host 'Vai ser removido:'
Write-Host "  o ambiente Python e o código      $Prefixo  ($(Tamanho $Prefixo))"
foreach ($nome in $Lancadores) {
    $atalho = Join-Path $Bin "$nome.cmd"
    if (Test-Path $atalho) { Write-Host "  o atalho                          $atalho" }
}
Write-Host ''
# Dado biométrico e 1,8 GB de download são governados por opções diferentes,
# então cada linha carrega a sua — uma dica de rodapé só valeria para metade.
if ($RemoverDados) {
    Write-Host 'Também os seus dados:' -ForegroundColor Red
    Write-Host "  vozes cadastradas   $vozes  ($(Tamanho $vozes))"
    Write-Host "  áudios gerados      $saida  ($(Tamanho $saida))"
} else {
    Write-Host 'Preservado:'
    Write-Host "  vozes cadastradas   $vozes  ($(Tamanho $vozes))   -RemoverDados apaga"
    Write-Host "  áudios gerados      $saida  ($(Tamanho $saida))"
}
if (Test-Path $dirModelos) {
    if ($RemoverModelos) {
        Write-Host "  pesos do XTTS-v2    $dirModelos  ($(Tamanho $dirModelos))" -ForegroundColor Red
    } else {
        Write-Host "  pesos do XTTS-v2    $dirModelos  ($(Tamanho $dirModelos))   -RemoverModelos apaga"
    }
}
Write-Host ''

if ($Simular) {
    Escrever-Passo 'Simulação — nada será removido'
} elseif ($RemoverDados) {
    Confirmar "Apagar as vozes cadastradas em $vozes é irreversível. Confirma?"
}

Escrever-Passo 'Removendo'

if (-not $RemoverDados) {
    $temDados = @($vozes, $saida) | Where-Object {
        (Test-Path $_) -and (Get-ChildItem $_ -Force -ErrorAction SilentlyContinue)
    }
    if ($temDados) {
        # Remove só o que o instalador pôs, deixando vozes\ e saida\ de pé.
        foreach ($arquivo in @('compat.py', 'vozclone.py', 'falar.py', 'web.py', 'requirements.txt',
                               'uv.toml', 'LICENSE', '.install-manifest', 'uninstall.ps1',
                               '.venv', '__pycache__')) {
            Remover (Join-Path $Prefixo $arquivo)
        }
    } else {
        Remover $Prefixo
    }
} else {
    Remover $Prefixo
}

if ($RemoverModelos) { Remover $dirModelos }

foreach ($nome in $Lancadores) { Remover-Atalho (Join-Path $Bin "$nome.cmd") }

Write-Host ''
if ($Simular) {
    Write-Host 'Nada foi removido. Tire o -Simular para valer.'
    exit 0
}

Escrever-Passo 'Pronto.'
if (-not $RemoverDados -and (Test-Path $Prefixo)) {
    Write-Host ''
    Write-Host 'Seus dados continuam onde estavam:'
    Write-Host "  $vozes"
    Write-Host "  $saida"
    Write-Host ''
    Write-Host 'Áudio de voz é dado biométrico. Se não vai mais usar, apague de vez:'
    Write-Host "  Remove-Item -Recurse -Force `"$Prefixo`""
}
if (-not $RemoverModelos -and (Test-Path $dirModelos)) {
    Write-Host ''
    Write-Host "Os pesos do XTTS-v2 ($(Tamanho $dirModelos)) ficaram em $dirModelos —"
    Write-Host 'reinstalar reaproveita, e -RemoverModelos apaga.'
}
# O PATH do usuário, se o install.ps1 mexeu nele, fica como está: pode ter sido
# editado depois, e reverter às cegas apagaria o que não é nosso.
if ([Environment]::GetEnvironmentVariable('Path', 'User') -split ';' | Where-Object { $_ -eq $Bin }) {
    Write-Host ''
    Escrever-Aviso "$Bin continua no seu PATH de usuário. Se não usa mais, remova pelas"
    Write-Host '       Variáveis de Ambiente do Windows — não mexo nisso por você.'
}
