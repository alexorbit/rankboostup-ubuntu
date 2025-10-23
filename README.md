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
| `RBU_ENABLE_UNSAFE_SWIFTSHADER` | Mantido em `1` (padrão) força o uso do SwiftShader para permitir WebGL sem GPU física. |

Para encerrar instâncias iniciadas pelo script:

```bash
./scripts/rankboostup-headless.sh stop
```

> **Dica:** Execute o comando `start` uma vez com `RBU_HEADLESS_MODE=none` em um ambiente com interface gráfica (ou tunelado via VNC) para realizar o login. Depois copie o diretório de perfil para os servidores headless.

## Execução headless no macOS

Para executar a mesma automação em máquinas macOS foi adicionado o script `scripts/rankboostup-macos.sh`. Ele instala o Google Chrome e inicia a extensão com os mesmos parâmetros usados no Ubuntu.

### Instalação automática do Google Chrome

```bash
sudo ./scripts/rankboostup-macos.sh install
```

O comando baixa a imagem oficial da Google, monta a unidade temporariamente e copia o aplicativo para `/Applications`. Execute-o apenas na primeira configuração da máquina (ou quando desejar atualizar o Chrome).

### Iniciando o tráfego em modo headless

```bash
./scripts/rankboostup-macos.sh start
```

Por padrão o navegador utiliza o modo headless nativo do Chrome (`--headless=new`) e a URL `https://app.rankboostup.com/dashboard/traffic-exchange/?autostart=1`, garantindo que o botão **Start Exchange Boostup** seja pressionado automaticamente após o carregamento.

Para encerrar instâncias iniciadas pelo script:

```bash
./scripts/rankboostup-macos.sh stop
```

### Variáveis de ambiente úteis (macOS)

| Variável              | Descrição                                                                                 |
|-----------------------|-------------------------------------------------------------------------------------------|
| `RBU_PROFILE_DIR`     | Caminho do perfil que armazena cookies/sessão. Padrão: `~/Library/Application Support/rankboostup-headless`. |
| `RBU_HEADLESS_MODE`   | `chrome` (padrão, headless nativo) ou `none` para abrir o Chrome com janela visível.       |
| `RBU_EXTENSION_DIR`   | Caminho da extensão caso o repositório tenha sido copiado para outro local.              |
| `RBU_START_URL`       | URL aberta ao iniciar. Inclua `autostart=1` (ou `true/yes`) para iniciar a sessão sozinho.|
| `RBU_DEBUG_PORT`      | Porta aberta para depuração remota do Chrome. Permite anexar ferramentas externas se necessário. |
| `RBU_NO_SANDBOX`      | Defina como `1` para anexar `--no-sandbox` ao Chrome (útil em ambientes restritos).       |

> **Dica:** Assim como no Ubuntu, é possível realizar o login manual executando `RBU_HEADLESS_MODE=none ./scripts/rankboostup-macos.sh start` em uma máquina com interface gráfica. Depois copie o diretório de perfil para reutilizar em servidores headless.
 
