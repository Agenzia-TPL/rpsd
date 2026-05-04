# RPSD ops scripts

`ops/` contiene wrapper operativi end-to-end per l'ambiente locale. Gli script
granulari restano in `scripts/` e continuano a essere la base riusabile per
setup, start, stop e status.

## Comandi

Da root del repo `rpsd`:

```bash
bash ops/bootstrap-start.sh
bash ops/bootstrap-start.sh --only-config

bash ops/bootstrap-stop.sh
bash ops/bootstrap-stop.sh erase

bash ops/bootstrap-rebuild.sh
bash ops/bootstrap-rebuild.sh --only-config
bash ops/bootstrap-rebuild.sh --setup-force --only-config
```

Da workspace root:

```bash
bash rpsd/ops/bootstrap-start.sh --help
bash rpsd/ops/bootstrap-stop.sh --help
bash rpsd/ops/bootstrap-rebuild.sh --help
```

## Differenza tra `ops/` e `scripts/`

- `scripts/`: operazioni granulari sul compose project, ad esempio avviare solo
  shared services o stampare lo status.
- `ops/`: procedure complete per uso locale quotidiano, incluse bootstrap
  Keycloak, sync secret verso `rpsd-config/.env`, migrazioni Django e superuser.

I wrapper root del workspace (`start.sh`, `stop.sh`, `rebuild.sh`) restano per
compatibilita locale. La fonte operativa documentata per nuovi sviluppatori e'
`rpsd/ops`.

## Mappatura wrapper root

- `start.sh --only-config` -> `ops/bootstrap-start.sh --only-config`.
- `start.sh` -> `ops/bootstrap-start.sh`.
- `stop.sh` -> `ops/bootstrap-stop.sh`.
- `stop.sh erase|--erase|-e` -> `ops/bootstrap-stop.sh erase|--erase|-e`.
- `rebuild.sh --only-config` -> `ops/bootstrap-rebuild.sh --only-config`.
- `rebuild.sh --setup-force` -> `ops/bootstrap-rebuild.sh --setup-force`.

## Credenziali bootstrap locali

Keycloak:

```text
username: rpsd-admin
password: rpsd-admin
```

Django:

```text
username: rpsd-config-admin
password: rpsd-config-admin
```

## Note sicurezza

Gli script sincronizzano i secret Keycloak in `rpsd-config/.env`, ma non
stampano i valori in output. Il cleanup distruttivo e' disponibile solo con
`bootstrap-stop.sh erase`.
