# API call examples

Esempi minimi condivisi per provare il flusso end-to-end di invio file della
piattaforma RPSD:

1. `m2m_send_file.py`: client aziendale M2M senza utente Django.

Lo script:

1. ottiene un token Keycloak con `client_credentials`;
2. chiama `rpsd-config` per leggere identita M2M e contratto;
3. chiama `rpsd-config` per validare `contract_code` + `data_category`;
4. invia un file di esempio a `rpsd-ingest` su `/ingest`.

L'upload file e' gestito da `rpsd-ingest`, mentre autorizzazioni, contratto e
metadata arrivano da `rpsd-config`. Per questo gli esempi stanno nel repo
orchestratore `rpsd`.

L'invio file user-based e' fuori standard: gli endpoint user di
`rpsd-config` restano disponibili per flussi utente autenticati, ma la
trasmissione file operativa verso ingest deve passare da credenziali aziendali
M2M.

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
  -> rpsd-config /exchange_agreement/api/m2m/v1/contracts/{contract_code}/ingest-authorization
  -> rpsd-ingest /ingest
```

La validazione esplicita `ingest-authorization` mostra la decisione di Config
su JWT, azienda, contratto, grant e categoria dato. In un client reale che
rimane attivo a lungo, il token va richiesto di nuovo quando si avvicina alla
scadenza indicata da `expires_in`; lo script lo fa solo se il token risulta in
scadenza prima dell'invio.

## Variabili utili

```bash
export RPSD_KEYCLOAK_TOKEN_URL="http://localhost:19300/realms/rpsd/protocol/openid-connect/token"
export RPSD_CONFIG_BASE_URL="http://localhost:20100"
export RPSD_INGEST_URL="http://localhost:20000/ingest"
export RPSD_FILE_PATH="example/api_call_examples/sample_dataset.json"
export RPSD_CONTENT_TYPE="application/json"
```
