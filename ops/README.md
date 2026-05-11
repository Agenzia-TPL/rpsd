# RPSD ops scripts

`ops/` contiene wrapper operativi end-to-end per l'ambiente locale disponibile
oggi: `rpsd-config`, `rpsd-ingest`, Keycloak e le dipendenze condivise
necessarie. Non e' ancora il bootstrap completo di ogni futura componente della
piattaforma.

Gli script granulari restano in `scripts/` e continuano a essere la base
riusabile per setup, start, stop e status. `ops/` li orchestra e aggiunge gli
step di inizializzazione operativa che richiedono conoscenza cross-repository.

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

| Area | `scripts/` | `ops/` |
| --- | --- | --- |
| setup `.env` base | esegue `setup.sh` | chiama `scripts/setup.sh` |
| shared services | avvio/stop granulare | orchestra start/stop nel flusso completo |
| servizi applicativi | avvio/rebuild/stop granulare | orchestra config/ingest nel flusso locale |
| Keycloak admin locale | non gestito | crea/aggiorna `rpsd-admin` e gruppo `/rpsd/admin` |
| secret Keycloak | non gestito | sincronizza secret reali in `rpsd-config/.env` |
| Django config | non gestito | esegue migrazioni, FlowProfile standard e superuser locale |
| status/log finali | comandi granulari | riepilogo operativo e log utili |

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

## FlowProfile standard

Il bootstrap applica anche `init_flow_profiles` su `rpsd-config`. Dopo una
inizializzazione locale devono essere presenti i profili flussi dati standard:

- `Standard TPL - Programmato + Real time`;
- `Solo Programmato NeTEx`.

La creazione di nuovi contratti richiede almeno un `FlowProfile` attivo.

## Note sicurezza

Gli script sincronizzano i secret Keycloak in `rpsd-config/.env`, ma non
stampano i valori in output. Il cleanup distruttivo e' disponibile solo con
`bootstrap-stop.sh erase`.
