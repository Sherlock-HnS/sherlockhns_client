# Sherlock HnS Client

Este addon fornece a interface, o spawnmenu administrativo, as visualizações das ferramentas, a playlist do LMS, os sons e o logo do Sherlock HnS.

## Instalação

Monte o item da Workshop na coleção do servidor ou instale o conteúdo de `addon/` em `garrysmod/addons/sherlockhns_client/`. Use o gamemode `sherlockhns_gamemode`, o Sherlock Custom Chat com o marcador de integração v1, a base Sherlock Parakeets e o addon `sherlock-outfitter`. O botão **Outfits** no menu do cliente abre a interface de seleção de outfits do Outfitter. O gamemode carrega o cliente depois dos plugins. Instalar o addon em Sandbox não registra hooks, armas, painéis ou comandos.

Em `server.cfg`, defina `sherlockhns_client_workshop_id "ID_DO_ITEM"`. Ao entrar, os jogadores recebem os assets pela Workshop e o Lua pelo canal nativo do GMod.

## Publicação

Disponibilize os secrets `STEAM_USER`, `STEAM_PASS` e `STEAM_SHARED_SECRET` ao repositório. Em Actions, rode **Sherlock HnS Client Workshop** com **create_new** para criar o item do cliente. Salve o ID retornado na variável de repositório `WORKSHOP_ID` e use o mesmo valor no servidor. Atualizações da pasta `addon/` em `main` validam o GMA e atualizam o item configurado. PRs apenas validam o pacote.

Para incluir música, use `make music URL=...` e `make music-verify`. A playlist e os arquivos de áudio são versionados juntos.
