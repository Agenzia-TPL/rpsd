# API call examples

Esempi minimi condivisi per provare i flussi end-to-end della piattaforma RPSD:

1. `m2m_send_file.py`: client aziendale M2M senza utente Django.
2. `user_send_file.py`: autenticazione come utente Django/Keycloak.

Entrambi gli script:

1. ottengono o ricevono un token Keycloak;
2. chiamano `rpsd-config` per leggere contratto e metadata;
3. inviano un file di esempio a `rpsd-ingest` su `/ingest`.

L'upload file e' gestito da `rpsd-ingest`, mentre autorizzazioni, contratto e
metadata arrivano da `rpsd-config`. Per questo gli esempi stanno nel repo
orchestratore `rpsd`.

## Prerequisiti

Servizi locali standard:

```bash
http://localhost:19300  Keycloak
http://localhost:20100  rpsd-config
http://localhost:20000  rpsd-ingest
```

Da root del repo `rpsd`:

```bash
docker compose --profile all up -d
```

File inviato di default:

```bash
example/api_call_examples/sample_dataset.json
```

## Esempio M2M senza utente

Usa le credenziali M2M dell'azienda TPL, visibili dalla UI del dettaglio
contratto o dalla pagina azienda.

```bash
cd /home/davide/dati/60_lavoro/003_agb/30_rapsodia/20_rpsd/rpsd

export RPSD_M2M_CLIENT_ID="azienda-default-prod"
export RPSD_M2M_CLIENT_SECRET="..."
export RPSD_CONTRACT_CODE="mil-1-202605"
export RPSD_DATA_CATEGORY="netex"

python3 example/api_call_examples/m2m_send_file.py
```

Flusso:

```text
client_id/client_secret
  -> Keycloak token endpoint
  -> rpsd-config /exchange_agreement/api/m2m/v1
  -> rpsd-ingest /ingest
```

## Esempio come utente

Metodo consigliato: passare allo script un access token utente gia' ottenuto da
Keycloak/login.

```bash
cd /home/davide/dati/60_lavoro/003_agb/30_rapsodia/20_rpsd/rpsd

export RPSD_USER_ACCESS_TOKEN="..."
export RPSD_CONTRACT_CODE="mil-1-202605"
export RPSD_DATA_CATEGORY="netex"

python3 example/api_call_examples/user_send_file.py
```

Lo script supporta anche username/password con password grant:

```bash
export RPSD_USER_USERNAME="ingest-atm-pavia@example.com"
export RPSD_USER_PASSWORD="..."
export RPSD_OIDC_CLIENT_ID="rpsd-config"
export RPSD_OIDC_CLIENT_SECRET="..."

python3 example/api_call_examples/user_send_file.py
```

Nel realm attuale `rpsd-config` puo' avere `directAccessGrantsEnabled=false`;
in quel caso il password grant non funziona e va usato `RPSD_USER_ACCESS_TOKEN`.

## Variabili utili

```bash
export RPSD_KEYCLOAK_TOKEN_URL="http://localhost:19300/realms/rpsd/protocol/openid-connect/token"
export RPSD_CONFIG_BASE_URL="http://localhost:20100"
export RPSD_INGEST_URL="http://localhost:20000/ingest"
export RPSD_FILE_PATH="example/api_call_examples/sample_dataset.json"
export RPSD_CONTENT_TYPE="application/json"
```
