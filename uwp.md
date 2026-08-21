# Plano de Implementação: Port UWP (Xbox One)

Este documento descreve a estratégia técnica passo-a-passo para exportar o projeto **Street Fighter EX Plus Alpha Recomp** para a plataforma UWP (Universal Windows Platform), focada em rodar nativamente no Xbox One via Dev Mode.

O plano foi elaborado para garantir que o código permaneça 100% compatível com a versão de PC (Windows/Linux) e que o pacote UWP seja gerado automaticamente pelo GitHub Actions.

---

## Fase 1: Arquitetura Cross-Platform e Sandbox de Arquivos

Aplicativos UWP rodam dentro de uma *Sandbox*. O jogo não tem permissão para ler arquivos arbitrários no sistema ou exibir janelas de diálogo do Windows. Toda a lógica de descoberta de arquivos precisa ser alterada **apenas para UWP**.

### Estratégia de Diretivas
Toda alteração de código voltada para o UWP no repositório base (`psxrecomp`) deverá ser protegida por macros nativas da Microsoft:
```cpp
#if defined(WINAPI_FAMILY) && (WINAPI_FAMILY == WINAPI_FAMILY_APP)
    // Código exclusivo UWP / Xbox
#else
    // Código atual para PC/Linux
#endif
```

### O Fluxo do Sistema de Arquivos (`main.cpp`)
Modificar as funções `resolve_bios_for_runtime` e `resolve_disc_for_runtime` para aplicar o seguinte fluxo no UWP:
1. Usar a função `SDL_GetPrefPath("psxrecomp", "alphaPlus")` para obter o caminho garantido de leitura/escrita do UWP (a pasta oculta `LocalState` do aplicativo).
2. Tentar criar a seguinte estrutura de pastas dentro do caminho obtido:
   - `bios/`
   - `disc/`
   - `memoryCard/`
3. Verificar se os arquivos `SCPH1001.BIN` (na pasta `bios`) e `.cue` (na pasta `disc`) existem.
4. **Exit Silencioso:** Se os arquivos não existirem, o jogo simplesmente dá um `return 0` (fecha). O jogador usará esse primeiro *boot* para gerar as pastas.
5. **Carregamento Automático:** Se existirem, a função retorna o caminho completo deles, ignorando qualquer chamada para o Launcher Frontend ou janelas de escolha.

---

## Fase 2: Configuração Inicial e Gráficos

O UWP no Xbox não suporta OpenGL para Desktop. O jogo deve ser forçado a usar renderização por software, e não depender do frontend gráfico.

1. **Pulo do Launcher:** Garantir que no UWP a variável que pula o launcher seja verdadeira por padrão (equivalente ao `--no-launcher`), forçando o boot direto.
2. **Software Renderer:** Forçar o `g_video_renderer = 0` (Modo Software), que é processado pela CPU e renderizado pelo SDL2 nativamente sobre o DirectX 11.
3. **Controles (Inputs):** Garantir que os slots 1 e 2 do PS1 sejam atrelados ao Gamepad (SDL GameController) por padrão em ambientes UWP, eliminando a dependência do teclado. As configurações ficarão em cópias de `game.toml` e `input.ini` copiadas para o `LocalState` no primeiro boot.

---

## Fase 3: Automação da Build via GitHub Actions

Atualmente, o Windows usa MSYS2 e MinGW, que **não geram pacotes UWP**. O GitHub Actions deverá usar a toolchain oficial da Microsoft (MSVC).

### Configuração do Workflow (`build.yml`)
Adicionar um novo *job* de compilação específico para UWP (ou adaptar o de Windows). O ambiente `windows-latest` do GitHub já possui o Visual Studio 2022 e as cargas de trabalho UWP instaladas.

**Exemplo do script CMake para UWP:**
```yaml
- name: Configure CMake for UWP
  run: |
    cmake -S PlusAlphaProject -B PlusAlphaProject/build-uwp `
          -G "Visual Studio 17 2022" -A x64 `
          -DCMAKE_SYSTEM_NAME=WindowsStore `
          -DCMAKE_SYSTEM_VERSION="10.0"
          
- name: Build UWP Appx
  run: |
    cmake --build PlusAlphaProject/build-uwp --config Release
```

*Nota: Será necessário ajustar o CMakeLists para criar corretamente o manifesto do pacote (`Package.appxmanifest`) exigido pela Microsoft, ou empacotar manualmente o `.exe` e seus assets com a ferramenta `MakeAppx.exe`.*

---

## Fase 4: Experiência do Usuário (Xbox Dev Mode)

Uma vez gerado o `.appx` (ou `.msix`) pelo GitHub Actions, o roteiro do usuário será:
1. **Instalação:** Instalar o `.appx` no Xbox pelo Device Portal (pelo PC).
2. **Primeiro Boot:** Iniciar o jogo pelo menu do Xbox. O jogo será aberto e fechado instantaneamente (criando as pastas `bios` e `disc` na Sandbox).
3. **Transferência de Arquivos:** O jogador abre o recurso de FTP do Xbox Dev Mode (ou a aba File Explorer no Portal), entra na pasta `LocalState/alphaPlus` do aplicativo e copia a BIOS e a ISO (e configura o `game.toml` se quiser).
4. **Gameplay:** Ao abrir o jogo novamente, ele acha os arquivos e inicia a emulação nativa em 60 FPS sem engasgos.
