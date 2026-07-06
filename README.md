# O Culpado

Nem sempre existe **um** culpado por uma eliminação — futebol é coletivo, e derrota é
soma de erros, azar e mérito do adversário. Mas… **e se você pudesse escolher?**

O Culpado pega os jogos em que uma seleção foi eliminada (ou perdeu) e mostra só
**quem entrou em campo pelo time que perdeu**. Você aponta quantos quiser como
culpados e a votação atualiza **em tempo real** pra todo mundo que está na página.
É opinião de torcedor virando ranking ao vivo — sem mimimi, só o dedo na cara de quem
você acha que fez feio.

**App:** https://oculpado.fly.dev

**Código:** https://github.com/franknfjr/oculpado

## Como funciona

- Cada partida vem de um JSON em `priv/data` (dados do SofaScore: escalação, minutos,
  nota, gols, foto).
- Os candidatos a "culpado" são os jogadores do **time perdedor** que de fato jogaram.
- Votos são contabilizados ao vivo via Phoenix LiveView + PubSub.
- **Imagens (escudos e fotos) são hospedadas localmente** (`priv/static/images`). O
  SofaScore bloqueia hotlink por IP/Referer — no Fly as imagens não renderizariam —,
  então o módulo `Oculpado.Assets` baixa tudo uma vez e o próprio app serve os arquivos.

## Stack

- [Phoenix](https://www.phoenixframework.org/) + LiveView
- SQLite (Ecto) para persistir os votos
- Deploy em [Fly.io](https://fly.io)

## Rodando localmente

```bash
mix setup            # instala deps, cria o banco e compila os assets
mix phx.server       # sobe o servidor (ou: iex -S mix phx.server)
```

Acesse [`localhost:4000`](http://localhost:4000).

## Adicionando uma nova partida

1. Coloque o JSON da partida em `priv/data/` (formato completo `home`/`away` ou só
   `loser_team`).
2. Baixe as imagens de times e jogadores referenciados (roda **local**, onde o
   SofaScore não bloqueia):

   ```bash
   mix run -e "Oculpado.Assets.fetch_all()"
   ```

   Isso salva `priv/static/images/{teams,players}/{id}.{png|webp}`, validando os
   *magic bytes* de cada arquivo. É idempotente — pula o que já existe (use
   `Oculpado.Assets.fetch_all(force: true)` para rebaixar tudo).
3. Faça o commit dos JSONs + imagens e o deploy:

   ```bash
   fly deploy
   ```

## Deploy

```bash
fly deploy
```

As imagens em `priv/static/images` vão junto no build (`COPY priv priv` no Dockerfile)
e são servidas pelo próprio app — nada depende do SofaScore em produção.

## Comunidade

- [Código de Conduta](CODE_OF_CONDUCT.md)
- [Como contribuir](CONTRIBUTING.md)
- [Política de Segurança](SECURITY.md)

## Licença

Distribuído sob a licença [MIT](LICENSE).
