#!/usr/bin/env python3
"""
Interface web local do clonador de voz — paridade completa com a CLI.

Cada aba corresponde a um comando de `falar.py`: Vozes a `vozes` e `cadastrar`,
Falar a `falar`, Ambiente a `checar`. O modelo fica residente entre as gerações,
o que torna esta interface bem mais confortável que a CLI para uso repetido: a
carga do XTTS custa ~24 s e acontece uma única vez por processo.

Por padrão escuta apenas em 127.0.0.1 — nada sai da máquina. No contêiner é
preciso escutar em 0.0.0.0 para que a porta seja publicável; o docker-compose.yml
publica só em 127.0.0.1 do host, preservando a mesma garantia.
"""

from __future__ import annotations

import os
from pathlib import Path

import gradio as gr

from vozclone import (
    DIR_SAIDA,
    DIR_VOZES,
    IDIOMAS,
    cadastrar_voz,
    carregar_modelo,
    duracao,
    listar_vozes,
    sintetizar,
    validar_nome,
)

HOST = os.environ.get("VOICE_CLONE_HOST", "127.0.0.1")
PORT = int(os.environ.get("VOICE_CLONE_PORT", "7860"))


# --- Aba 1: vozes ----------------------------------------------------------


def tabela_vozes() -> list[list[str]]:
    """Equivale a `falar.py vozes`, com a duração de cada referência."""
    linhas = []
    for nome in listar_vozes():
        try:
            linhas.append([nome, f"{duracao(DIR_VOZES / f'{nome}.wav'):.1f} s"])
        except Exception as e:  # arquivo corrompido não deve derrubar a listagem
            linhas.append([nome, f"ilegível ({type(e).__name__})"])
    return linhas


def acao_listar():
    linhas = tabela_vozes()
    rotulo = f"{len(linhas)} voz(es) cadastrada(s)." if linhas else "Nenhuma voz cadastrada ainda."
    return linhas, rotulo, gr.update(choices=[l[0] for l in linhas])


def acao_cadastrar(nome, audio):
    if not audio:
        return "Grave ou envie um áudio de referência.", *acao_listar()[:2], gr.update()
    try:
        nome = validar_nome(nome)
        cadastrar_voz(nome, audio)
    except (FileNotFoundError, ValueError) as e:
        return f"**Erro:** {e}", *acao_listar()[:2], gr.update()

    linhas, rotulo, _ = acao_listar()
    return (
        f"Voz **{nome}** cadastrada.",
        linhas,
        rotulo,
        gr.update(choices=[l[0] for l in linhas], value=nome),
    )


# --- Aba 2: falar ----------------------------------------------------------


def acao_falar(voz, texto, arquivo, idioma, velocidade, rapido, nome_saida, progresso=gr.Progress()):
    if not voz:
        return None, None, "Cadastre e selecione uma voz primeiro."

    # O arquivo tem precedência sobre a caixa de texto, como o -f da CLI.
    if arquivo:
        try:
            texto = Path(arquivo).read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as e:
            return None, None, f"**Erro** ao ler o arquivo: {e}"
    if not texto or not texto.strip():
        return None, None, "Escreva o texto ou envie um arquivo .txt."

    saida = None
    if nome_saida and nome_saida.strip():
        try:
            saida = DIR_SAIDA / f"{validar_nome(nome_saida.removesuffix('.wav'))}.wav"
        except ValueError as e:
            return None, None, f"**Erro** no nome do arquivo: {e}"

    progresso(0.1, desc="Carregando o modelo (~24 s na primeira vez)...")
    try:
        carregar_modelo(rapido)
        progresso(0.4, desc="Sintetizando...")
        r = sintetizar(texto, voz, idioma, saida=saida, velocidade=velocidade, rapido=rapido)
    except (FileNotFoundError, ValueError) as e:
        return None, None, f"**Erro:** {e}"

    return (
        str(r.caminho),
        gr.update(value=str(r.caminho), visible=True),
        f"**{r.caminho.name}** — {r.duracao_audio:.1f} s de áudio em "
        f"{r.tempo_geracao:.1f} s ({r.fator_tempo_real:.2f}x tempo real). "
        f"Salvo em `{r.caminho}`.",
    )


def acao_precarregar(rapido, progresso=gr.Progress()):
    progresso(0.2, desc="Carregando o XTTS-v2...")
    carregar_modelo(rapido)
    return "Modelo residente na memória. As próximas gerações não pagam a carga."


# --- Aba 3: ambiente -------------------------------------------------------


def acao_checar():
    """Equivale a `falar.py checar`."""
    import compat

    linhas = [["ok" if ok else "FALHA", item, detalhe] for ok, item, detalhe in compat.verificar()]
    falhas = sum(1 for l in linhas if l[0] == "FALHA")
    resumo = (
        f"**{falhas} verificação(ões) falharam** — ver `docs/MANUAL.md`."
        if falhas
        else "**Ambiente consistente.**"
    )
    return linhas, resumo


# --- Montagem --------------------------------------------------------------

with gr.Blocks(title="Clonador de Voz Local") as app:
    gr.Markdown(
        "# Clonador de Voz Local\n"
        "XTTS-v2 rodando offline na CPU. Clone uma voz com 6–30 s de áudio e "
        "faça-a falar qualquer texto em **pt-BR** ou **en-US**. "
        "Nenhum áudio sai desta máquina."
    )

    with gr.Tab("1. Vozes"):
        with gr.Row():
            with gr.Column():
                gr.Markdown("### Cadastrar")
                nome_in = gr.Textbox(label="Nome da voz", placeholder="ex: douglas")
                audio_in = gr.Audio(
                    label="Áudio de referência (microfone ou arquivo)",
                    sources=["microphone", "upload"],
                    type="filepath",
                )
                gr.Markdown(
                    "Fala contínua e limpa, sem música nem ruído de fundo. "
                    "6 s já funcionam; 15–20 s dão o melhor timbre. Áudio acima "
                    "de 30 s é cortado."
                )
                btn_cad = gr.Button("Cadastrar voz", variant="primary")
                status_cad = gr.Markdown()
            with gr.Column():
                gr.Markdown("### Cadastradas")
                rotulo_vozes = gr.Markdown()
                tabela = gr.Dataframe(
                    headers=["Voz", "Duração da referência"],
                    datatype=["str", "str"],
                    interactive=False,
                    label=None,
                )
                btn_listar = gr.Button("Atualizar lista")

    with gr.Tab("2. Falar"):
        voz_dd = gr.Dropdown(label="Voz", choices=listar_vozes(), value=None)
        texto_in = gr.Textbox(label="Texto", lines=6, placeholder="Escreva o que a voz deve falar...")
        arquivo_in = gr.File(
            label="…ou envie um .txt (tem precedência sobre o texto acima)",
            file_types=[".txt"],
            type="filepath",
        )
        with gr.Row():
            idioma_dd = gr.Dropdown(label="Idioma", choices=list(IDIOMAS), value="pt-br")
            vel_sl = gr.Slider(label="Velocidade", minimum=0.6, maximum=1.4, value=1.0, step=0.05)
            saida_in = gr.Textbox(
                label="Nome do arquivo de saída (opcional)", placeholder="narracao"
            )
        rapido_cb = gr.Checkbox(
            label="Modo rápido (int8) — cerca de 20% mais veloz, leve perda de fidelidade",
            value=False,
        )
        with gr.Row():
            btn_falar = gr.Button("Gerar áudio", variant="primary", scale=3)
            btn_pre = gr.Button("Pré-carregar modelo", scale=1)
        audio_out = gr.Audio(label="Resultado", type="filepath")
        btn_baixar = gr.DownloadButton("Baixar .wav", visible=False)
        status_falar = gr.Markdown()

    with gr.Tab("3. Ambiente"):
        gr.Markdown(
            "Equivale a `falar.py checar`: confere as correções de "
            "compatibilidade e o ambiente de execução — ver `compat.py`."
        )
        btn_checar = gr.Button("Verificar ambiente", variant="primary")
        resumo_check = gr.Markdown()
        tabela_check = gr.Dataframe(
            headers=["Estado", "Item", "Detalhe"],
            datatype=["str", "str", "str"],
            interactive=False,
        )

    # Fiação
    btn_cad.click(acao_cadastrar, [nome_in, audio_in], [status_cad, tabela, rotulo_vozes, voz_dd])
    btn_listar.click(acao_listar, None, [tabela, rotulo_vozes, voz_dd])
    btn_falar.click(
        acao_falar,
        [voz_dd, texto_in, arquivo_in, idioma_dd, vel_sl, rapido_cb, saida_in],
        [audio_out, btn_baixar, status_falar],
    )
    btn_pre.click(acao_precarregar, [rapido_cb], [status_falar])
    btn_checar.click(acao_checar, None, [tabela_check, resumo_check])
    app.load(acao_listar, None, [tabela, rotulo_vozes, voz_dd])

if __name__ == "__main__":
    app.launch(server_name=HOST, server_port=PORT, inbrowser=False)
