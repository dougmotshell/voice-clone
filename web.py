#!/usr/bin/env python3
"""Interface web local do clonador de voz. Roda em http://127.0.0.1:7860 — nada sai da máquina."""

import gradio as gr

from vozclone import IDIOMAS, cadastrar_voz, listar_vozes, sintetizar


def acao_cadastrar(nome, audio):
    if not nome or not nome.strip():
        return "Informe um nome para a voz.", gr.update()
    if not audio:
        return "Grave ou envie um áudio de referência.", gr.update()
    try:
        cadastrar_voz(nome.strip(), audio)
    except (FileNotFoundError, ValueError) as e:
        return f"Erro: {e}", gr.update()
    vozes = listar_vozes()
    return f"Voz '{nome.strip()}' cadastrada.", gr.update(choices=vozes, value=nome.strip())


def acao_falar(voz, texto, idioma, velocidade, rapido):
    if not voz:
        return None, "Cadastre e selecione uma voz primeiro."
    if not texto or not texto.strip():
        return None, "Escreva o texto a ser falado."
    try:
        r = sintetizar(texto, voz, idioma, velocidade=velocidade, rapido=rapido)
    except (FileNotFoundError, ValueError) as e:
        return None, f"Erro: {e}"
    return str(r.caminho), (
        f"{r.duracao_audio:.1f}s de áudio em {r.tempo_geracao:.1f}s "
        f"({r.fator_tempo_real:.2f}x tempo real) — {r.caminho.name}"
    )


with gr.Blocks(title="Clonador de Voz Local") as app:
    gr.Markdown(
        "# Clonador de Voz Local\n"
        "XTTS-v2 rodando offline na CPU. Clone uma voz com 6–30s de áudio "
        "e faça-a falar qualquer texto em **pt-BR** ou **en-US**."
    )

    with gr.Tab("1. Cadastrar voz"):
        nome_in = gr.Textbox(label="Nome da voz", placeholder="ex: douglas")
        audio_in = gr.Audio(
            label="Áudio de referência (grave pelo microfone ou envie um arquivo)",
            sources=["microphone", "upload"],
            type="filepath",
        )
        gr.Markdown(
            "Use fala contínua e limpa, sem música nem ruído de fundo. "
            "6 segundos já funcionam; 15–20s dão o melhor timbre."
        )
        btn_cad = gr.Button("Cadastrar voz", variant="primary")
        status_cad = gr.Markdown()

    with gr.Tab("2. Falar"):
        voz_dd = gr.Dropdown(label="Voz", choices=listar_vozes(), value=None)
        texto_in = gr.Textbox(label="Texto", lines=6, placeholder="Escreva o que a voz deve falar...")
        with gr.Row():
            idioma_dd = gr.Dropdown(label="Idioma", choices=list(IDIOMAS), value="pt-br")
            vel_sl = gr.Slider(label="Velocidade", minimum=0.6, maximum=1.4, value=1.0, step=0.05)
        rapido_cb = gr.Checkbox(
            label="Modo rápido (int8) — cerca de 20% mais veloz, leve perda de fidelidade",
            value=False,
        )
        btn_falar = gr.Button("Gerar áudio", variant="primary")
        audio_out = gr.Audio(label="Resultado", type="filepath")
        status_falar = gr.Markdown()

    btn_cad.click(acao_cadastrar, [nome_in, audio_in], [status_cad, voz_dd])
    btn_falar.click(acao_falar, [voz_dd, texto_in, idioma_dd, vel_sl, rapido_cb], [audio_out, status_falar])

if __name__ == "__main__":
    app.launch(server_name="127.0.0.1", server_port=7860, inbrowser=False)
