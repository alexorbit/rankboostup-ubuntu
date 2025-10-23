# rankboostup-ubuntu

## Execução headless no Ubuntu

Este repositório contém a versão descompactada da extensão do RankBoostup. Para facilitar a instalação e a execução em servidores Ubuntu sem interface gráfica foi adicionado o script `scripts/rankboostup-headless.sh`.

### Instalação automática das dependências

```bash
sudo ./scripts/rankboostup-headless.sh install
```

O comando acima instala o Google Chrome (ou Chromium), Xvfb e demais pacotes necessários. Execute-o apenas uma vez por servidor.

### Iniciando o tráfego de forma headless

```bash
./scripts/rankboostup-headless.sh start
```

Por padrão o navegador será iniciado dentro de um display virtual (`xvfb-run`), carregando a extensão e abrindo `https://app.rankboostup.com/dashboard/traffic-exchange/?autostart=1`. Esse endereço ativa automaticamente o botão **Start Exchange Boostup** assim que a página terminar de carregar.

Outras variáveis de ambiente úteis:

| Variável              | Descrição                                                                                 |
|-----------------------|-------------------------------------------------------------------------------------------|
| `RBU_PROFILE_DIR`     | Caminho do perfil que armazena cookies/sessão. Permite reutilizar logins anteriores.      |
| `RBU_HEADLESS_MODE`   | `xvfb` (padrão), `chrome` (modo headless nativo) ou `none` (abre janela visível).        |
| `RBU_EXTENSION_DIR`   | Caminho da extensão caso o repositório tenha sido copiado para outro local.              |
| `RBU_START_URL`       | URL aberta ao iniciar. Inclua `autostart=1` (ou `true/yes`) para iniciar a sessão sozinho.|

Para encerrar instâncias iniciadas pelo script:

```bash
./scripts/rankboostup-headless.sh stop
```

> **Dica:** Execute o comando `start` uma vez com `RBU_HEADLESS_MODE=none` em um ambiente com interface gráfica (ou tunelado via VNC) para realizar o login. Depois copie o diretório de perfil para os servidores headless.
 
