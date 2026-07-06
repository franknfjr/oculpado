# Contribuindo com o O Culpado

Valeu pelo interesse em contribuir! Toda ajuda é bem-vinda — de correção de bug a
uma partida nova pra votação.

## Antes de começar

- Leia o [Código de Conduta](CODE_OF_CONDUCT.md).
- Para bugs ou ideias, abra uma [issue](https://github.com/franknfjr/oculpado/issues)
  descrevendo o cenário.

## Ambiente

```bash
git clone git@github.com:franknfjr/oculpado.git
cd oculpado
mix setup
mix phx.server
```

## Fluxo de contribuição

1. Faça um fork e crie uma branch a partir da `main`:
   `git checkout -b minha-contribuicao`
2. Faça suas mudanças mantendo o estilo do projeto.
3. Garanta que compila sem warnings e que os testes passam:

   ```bash
   mix compile --warnings-as-errors
   mix format
   mix test
   ```

4. Abra um Pull Request explicando **o que** mudou e **por quê**.

## Adicionando uma partida

Partidas ficam em `priv/data/*.json`. Depois de adicionar o JSON, baixe as imagens
localmente (o SofaScore bloqueia hotlink em produção):

```bash
mix run -e "Oculpado.Assets.fetch_all()"
```

Faça o commit dos JSONs **e** das imagens geradas em `priv/static/images`.

## Estilo

- Elixir formatado com `mix format`.
- Mensagens de commit curtas e descritivas.
- Sem dados sujos: valide o que entra (é o espírito do `Oculpado.Assets`).
