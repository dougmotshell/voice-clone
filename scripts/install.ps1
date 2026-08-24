<#
.SYNOPSIS
    Instalador do Clonador de Voz Local — Windows 10/11 x86-64.

.DESCRIPTION
    Equivalente ao scripts/install.sh. Baixa apenas os arquivos de execução
    (não clona o repositório), cria o venv com `uv`, instala o requirements.txt
    — que carrega as fixações de wheel que não são opcionais, ver ADR-0002,
    ADR-0003 e ADR-0010 — gera os dois atalhos .cmd e roda `falar.py checar`.

    Os 1,8 GB de pesos do XTTS-v2 NÃO são baixados aqui: isso acontece na
    primeira síntese. Nenhum áudio sai da máquina em momento nenhum.

.EXAMPLE
    # baixe, leia, execute — a forma preferível
    irm https://raw.githubusercontent.com/dougmotshell/voice-clone/main/scripts/install.ps1 -OutFile install.ps1
    notepad install.ps1
    .\install.ps1

.EXAMPLE
    # direto, sem inspecionar
    irm https://raw.githubusercontent.com/dougmotshell/voice-clone/main/scripts/install.ps1 | iex

.EXAMPLE
    # com opções, pelo pipe: monte a chamada em & { }
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/dougmotshell/voice-clone/main/scripts/install.ps1))) -InstalarUv
#>
[CmdletBinding()]
param(
    # Onde instalar. O padrão fica no LOCALAPPDATA do usuário: não exige
    # administrador e não polui Program Files.
    [string]$Prefixo = $(if ($env:VOICE_CLONE_HOME) { $env:VOICE_CLONE_HOME } else { Join-Path $env:LOCALAPPDATA 'voice-clone' }),

    # Onde criar voice-clone.cmd e voice-clone-web.cmd.
    [string]$Bin = $(if ($env:VOICE_CLONE_BIN) { $env:VOICE_CLONE_BIN } else { Join-Path $env:LOCALAPPDATA 'voice-clone\bin' }),

    [string]$Ref = $(if ($env:VOICE_CLONE_REF) { $env:VOICE_CLONE_REF } else { 'main' }),
    [string]$Repo = $(if ($env:VOICE_CLONE_REPO) { $env:VOICE_CLONE_REPO } else { 'dougmotshell/voice-clone' }),

    # Instala a partir de uma árvore já em disco, sem rede.
    [string]$Local = '',

    # Instala o uv pelo instalador oficial da Astral, se ele não estiver no PATH.
    [switch]$InstalarUv,

    # Acrescenta $Bin ao PATH do usuário. Sem isto, o script apenas informa —
    # mexer no PATH de alguém é decisão dele, não do instalador.
    [switch]$AdicionarAoPath,

    [switch]$SemVerificar
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# TLS 1.2 explícito: o PowerShell 5.1 do Windows 10 ainda negocia TLS 1.0 por
# padrão, e o raw.githubusercontent.com recusa.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Os arquivos que a execução exige. É esta lista — e não um clone — que define
# o que é baixado; docs, ADRs e superfícies de IA ficam de fora.
$Arquivos = @('compat.py', 'vozclone.py', 'falar.py', 'web.py', 'requirements.txt', 'uv.toml', 'LICENSE')
# O desinstalador vai para dentro do prefixo: remover não deve exigir rede.
$ArquivoDesinstalador = 'scripts/uninstall.ps1'

function Escrever-Passo($texto) { Write-Host "==> $texto" -ForegroundColor Green }
function Escrever-Aviso($texto) { Write-Host "aviso: $texto" -ForegroundColor Yellow }
function Parar($texto) { Write-Host "erro: $texto" -ForegroundColor Red; exit 1 }

# Capturados aqui, no escopo do script: dentro de uma função,
# $PSBoundParameters seria o da própria função — sempre vazio.
$RemotoPedido = $PSBoundParameters.ContainsKey('Ref') -or $PSBoundParameters.ContainsKey('Repo')
$CaminhoDesteScript = if (Test-Path variable:PSCommandPath) { $PSCommandPath } else { '' }

function Resolver-Origem {
    if ($Local) { return (Resolve-Path $Local).Path }
    # Pedir -Ref ou -Repo é pedir aquele código, e não o que está no disco ao
    # lado do script. Vindo pelo pipe não há script em disco a considerar.
    if ($RemotoPedido) { return '' }
    if (-not $CaminhoDesteScript) { return '' }
    $raiz = Split-Path -Parent (Split-Path -Parent $CaminhoDesteScript)
    if ((Test-Path (Join-Path $raiz 'vozclone.py')) -and (Test-Path (Join-Path $raiz 'requirements.txt'))) {
        return $raiz
    }
    return ''
}

function Validar-Baixado($caminho) {
    if (-not (Test-Path $caminho) -or (Get-Item $caminho).Length -eq 0) {
        Parar "Download vazio: $(Split-Path -Leaf $caminho)"
    }
    # Pega o caso real: portal cativo ou proxy respondendo HTML com status 200.
    $inicio = Get-Content $caminho -TotalCount 1 -ErrorAction SilentlyContinue
    if ($inicio -and $inicio -match '(?i)<!doctype html|<html') {
        Parar "O download de $(Split-Path -Leaf $caminho) veio como HTML, não como código.`n       Alguma coisa entre você e o GitHub está respondendo no lugar dele."
    }
}

function Obter-Arquivos($origemLocal, $destino) {
    if ($origemLocal) {
        Escrever-Passo "Copiando de $origemLocal"
        foreach ($arquivo in $Arquivos) {
            $caminho = Join-Path $origemLocal $arquivo
            if (-not (Test-Path $caminho)) { Parar "Falta $arquivo em $origemLocal." }
            Copy-Item $caminho (Join-Path $destino (Split-Path -Leaf $arquivo)) -Force
        }
        $desinstalador = Join-Path $origemLocal $ArquivoDesinstalador
        if (Test-Path $desinstalador) { Copy-Item $desinstalador (Join-Path $destino 'uninstall.ps1') -Force }
        return
    }

    $base = "https://raw.githubusercontent.com/$Repo/$Ref"
    Escrever-Passo "Baixando $Repo@$Ref (8 arquivos, sem clonar o repositório)"
    foreach ($arquivo in ($Arquivos + $ArquivoDesinstalador)) {
        $saida = Join-Path $destino (Split-Path -Leaf $arquivo)
        try {
            Invoke-WebRequest -Uri "$base/$arquivo" -OutFile $saida -UseBasicParsing
        } catch {
            Parar "Não consegui baixar $arquivo de $base.`n       Confira a rede, e se o ref '$Ref' existe em $Repo."
        }
        Validar-Baixado $saida
    }
}

function Garantir-Uv {
    if (Get-Command uv -ErrorAction SilentlyContinue) { return }
    if (-not $InstalarUv) {
        Parar @"
O uv não está instalado, e é ele que resolve os wheels certos.

       Instale pelo winget:
         winget install --id=astral-sh.uv -e

       Ou rode este script de novo com -InstalarUv, que busca o instalador
       oficial da Astral e o executa.

       Não troque por pip: o uv.toml deste projeto carrega a estratégia de
       índice que o requirements.txt pressupõe (ADR-0010).
"@
    }
    Escrever-Passo 'Instalando o uv pelo instalador oficial da Astral'
    Invoke-Expression (Invoke-RestMethod -Uri 'https://astral.sh/uv/install.ps1' -UseBasicParsing)
    # O instalador do uv não recarrega o PATH da sessão em curso.
    $candidato = Join-Path $env:USERPROFILE '.local\bin'
    if (Test-Path (Join-Path $candidato 'uv.exe')) { $env:Path = "$candidato;$env:Path" }
    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
        Parar 'Instalei o uv mas ele não apareceu no PATH. Abra um PowerShell novo e rode este script de novo.'
    }
}

function Instalar-Arquivos($origem) {
    Escrever-Passo "Instalando em $Prefixo"
    foreach ($dir in @($Prefixo, (Join-Path $Prefixo 'vozes'), (Join-Path $Prefixo 'saida'))) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    # Arquivo por arquivo, nunca limpando o prefixo: reinstalar por cima não
    # pode encostar em vozes\ nem em saida\ — é dado biométrico do usuário.
    foreach ($arquivo in $Arquivos) {
        Copy-Item (Join-Path $origem (Split-Path -Leaf $arquivo)) $Prefixo -Force
    }
    $desinstalador = Join-Path $origem 'uninstall.ps1'
    if (Test-Path $desinstalador) { Copy-Item $desinstalador (Join-Path $Prefixo 'uninstall.ps1') -Force }
}

function Preparar-Ambiente {
    Escrever-Passo 'Criando o ambiente Python 3.12 (o uv baixa o interpretador se faltar)'
    & uv venv --python 3.12 (Join-Path $Prefixo '.venv') | Out-Null
    if ($LASTEXITCODE -ne 0) { Parar 'O uv não conseguiu criar o venv.' }

    $python = Join-Path $Prefixo '.venv\Scripts\python.exe'
    if (-not (Test-Path $python)) { Parar "O venv não foi criado em $Prefixo\.venv." }

    # Só agora existe um Python garantido para compilar o que foi baixado. Um
    # arquivo truncado no meio quebraria bem mais tarde, na primeira síntese.
    foreach ($arquivo in @('compat.py', 'vozclone.py', 'falar.py', 'web.py')) {
        & $python -m py_compile (Join-Path $Prefixo $arquivo) 2>$null
        if ($LASTEXITCODE -ne 0) {
            Parar "$arquivo não compila — o download veio corrompido. Rode o instalador de novo."
        }
    }
    Remove-Item (Join-Path $Prefixo '__pycache__') -Recurse -Force -ErrorAction SilentlyContinue

    Escrever-Passo 'Instalando as dependências (~1,7 GB; demora alguns minutos)'
    # Push-Location no prefixo porque é lá que está o uv.toml, e é dele que vem
    # a estratégia de índice que o requirements.txt pressupõe (ADR-0010).
    Push-Location $Prefixo
    try {
        $env:VIRTUAL_ENV = Join-Path $Prefixo '.venv'
        & uv pip install -r requirements.txt
        if ($LASTEXITCODE -ne 0) {
            Parar 'A instalação das dependências falhou. Resolvido o motivo, rode o instalador de novo — ele retoma daqui.'
        }
    } finally {
        Pop-Location
        Remove-Item Env:\VIRTUAL_ENV -ErrorAction SilentlyContinue
    }
}

function Criar-Atalhos {
    Escrever-Passo "Criando os atalhos em $Bin"
    New-Item -ItemType Directory -Force -Path $Bin | Out-Null
    $python = Join-Path $Prefixo '.venv\Scripts\python.exe'
    foreach ($par in @(@('voice-clone', 'falar.py'), @('voice-clone-web', 'web.py'))) {
        $conteudo = @"
@echo off
rem Gerado por install.ps1 do voice-clone. Remova com $Prefixo\uninstall.ps1.
"$python" "$(Join-Path $Prefixo $par[1])" %*
"@
        Set-Content -Path (Join-Path $Bin "$($par[0]).cmd") -Value $conteudo -Encoding ASCII
    }
}

function Escrever-Manifesto($origemLocal) {
    $commit = '(não resolvido)'
    if (-not $origemLocal) {
        try {
            $resposta = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/commits/$Ref" -UseBasicParsing
            if ($resposta.sha) { $commit = $resposta.sha }
        } catch { }
    }
    $linhas = @(
        '# Gerado por install.ps1 — o uninstall.ps1 lê este arquivo. Não edite.'
        "repo=$Repo"
        "ref=$Ref"
        "commit=$commit"
        "origem=$(if ($origemLocal) { $origemLocal } else { "$Repo@$Ref" })"
        "instalado_em=$([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))"
        "prefixo=$Prefixo"
        "bin=$Bin"
        'lancadores=voice-clone voice-clone-web'
    )
    Set-Content -Path (Join-Path $Prefixo '.install-manifest') -Value $linhas -Encoding UTF8
}

function Ajustar-Path {
    $pathUsuario = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($pathUsuario -and ($pathUsuario -split ';' | Where-Object { $_ -eq $Bin })) { return }

    if ($AdicionarAoPath) {
        $novo = if ($pathUsuario) { "$pathUsuario;$Bin" } else { $Bin }
        [Environment]::SetEnvironmentVariable('Path', $novo, 'User')
        Escrever-Passo "$Bin adicionado ao seu PATH — abra um terminal novo para valer."
        return
    }
    Write-Host ''
    Escrever-Aviso "$Bin não está no seu PATH — os atalhos não vão ser encontrados."
    Write-Host '       Rode o instalador com -AdicionarAoPath, ou faça à mão:'
    Write-Host ''
    Write-Host "         [Environment]::SetEnvironmentVariable('Path', `"`$([Environment]::GetEnvironmentVariable('Path','User'));$Bin`", 'User')"
    Write-Host ''
    Write-Host "       Até lá, chame pelo caminho completo: $Bin\voice-clone.cmd"
}

function Verificar-Ambiente {
    if ($SemVerificar) { return $true }
    Escrever-Passo 'Verificando o ambiente (equivale a falar.py checar)'
    Push-Location $Prefixo
    try {
        # Out-Host: sem isto a saída do `checar` seria capturada como valor de
        # retorno da função, e o usuário não veria linha nenhuma.
        & (Join-Path $Prefixo '.venv\Scripts\python.exe') falar.py checar | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Escrever-Aviso "A verificação apontou falhas. A saída acima diz o que fazer, e a`n       seção 8 do manual detalha cada caso:`n       https://github.com/$Repo/blob/$Ref/docs/MANUAL.md"
            return $false
        }
    } finally {
        Pop-Location
    }
    return $true
}

function Mostrar-Resumo {
    Write-Host ''
    Write-Host "Instalado em $Prefixo"
    Write-Host ''
    Write-Host '  voice-clone cadastrar minhavoz C:\audio.wav   cadastra uma voz (6-30s de fala limpa)'
    Write-Host '  voice-clone falar minhavoz "Olá, mundo."      gera áudio'
    Write-Host '  voice-clone vozes                            lista as vozes cadastradas'
    Write-Host '  voice-clone checar                           confere o ambiente'
    Write-Host '  voice-clone-web                              interface web em http://127.0.0.1:7860'
    Write-Host ''
    Write-Host "  Vozes cadastradas: $Prefixo\vozes"
    Write-Host "  Áudios gerados:    $Prefixo\saida"
    Write-Host "  Desinstalar:       $Prefixo\uninstall.ps1"
    Write-Host ''
    Write-Host 'A primeira síntese baixa 1,8 GB de pesos do XTTS-v2, uma única vez.'
    Write-Host 'Depois disso nada mais sai da máquina.'
    Write-Host ''
    Write-Host 'Clonar a voz de outra pessoa exige o consentimento explícito dela, e o'
    Write-Host 'modelo é licenciado apenas para uso não comercial (CPML).'
}

# --- execução --------------------------------------------------------------

if (-not $Prefixo -or $Prefixo -eq '\' -or $Prefixo -eq '/') { Parar "Prefixo inválido: '$Prefixo'" }

$origemLocal = Resolver-Origem
Garantir-Uv

$temporario = Join-Path ([System.IO.Path]::GetTempPath()) "voice-clone-install-$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Force -Path $temporario | Out-Null
try {
    Obter-Arquivos $origemLocal $temporario
    Instalar-Arquivos $temporario
} finally {
    Remove-Item $temporario -Recurse -Force -ErrorAction SilentlyContinue
}

Preparar-Ambiente
Criar-Atalhos
Escrever-Manifesto $origemLocal

$ok = Verificar-Ambiente
Mostrar-Resumo
Ajustar-Path
if (-not $ok) { exit 1 }
