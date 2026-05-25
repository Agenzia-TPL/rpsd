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

### Configurazione integrazione

Metodo consigliato per un'integrazione aziendale: lo script resta generico e
credenziali, contratto ed endpoint stanno in un file di configurazione esterno.
Questo file descrive la relazione stabile azienda-contratto, non il singolo
file da inviare.

Esempio:

```json
{
  "client_id": "atm-milano-default-prod",
  "client_secret": "REPLACE_WITH_CLIENT_SECRET",
  "contract_code": "001002",
  "token_url": "http://localhost:19300/realms/rpsd/protocol/openid-connect/token",
  "config_base_url": "http://localhost:20100",
  "ingest_url": "http://localhost:20000/ingest"
}
```

Il file JSON puo' contenere il `client_secret`: va quindi trattato come
materiale sensibile, non va committato con valori reali e va condiviso solo con
i referenti autorizzati dell'azienda.

Nel repo e' disponibile un template:

```bash
example/api_call_examples/m2m_config.sample.json
```

### Parametri del singolo invio

Il tipo dato e il file inviato sono parametri della singola chiamata. Vanno
passati da CLI, con default locali nello script per smoke test rapidi:

```text
--data-category netex
--file example/api_call_examples/sample_dataset.json
--content-type application/json
```

`data_category` usa il nome canonico del file senza estensione, cioe il `what`
registrato nei profili flusso di Config. Esempi validi:

```text
netex
siri-pt
siri-et
siri-st
siri-sm
siri-vm
siri-ct
siri-cm
siri-gm
siri-fm
siri-sx
```

Non usare varianti con underscore come `siri_pt`: i nomi SIRI usano il
trattino per restare allineati ai file `siri-pt.xml` e `siri-pt.xsd`.

Esecuzione:

```bash
cd /home/davide/dati/60_lavoro/003_agb/30_rapsodia/20_rpsd/rpsd

python3 example/api_call_examples/m2m_send_file.py \
  --config example/api_call_examples/m2m_config.sample.json \
  --data-category netex \
  --file example/api_call_examples/sample_dataset.json \
  --content-type application/json
```

Per inviare un file diverso:

```bash
python3 example/api_call_examples/m2m_send_file.py \
  --config example/api_call_examples/m2m_config.sample.json \
  --data-category siri-pt \
  --file /percorso/al/siri-pt.xml \
  --content-type application/xml
```

### Uso con variabili d'ambiente

Le variabili d'ambiente restano utili per test locali o automazioni CI.

```bash
cd /home/davide/dati/60_lavoro/003_agb/30_rapsodia/20_rpsd/rpsd

export RPSD_M2M_CLIENT_ID="azienda-default-prod"
export RPSD_M2M_CLIENT_SECRET="..."
export RPSD_CONTRACT_CODE="mil-1-202605"
export RPSD_DATA_CATEGORY="netex"
export RPSD_FILE_PATH="example/api_call_examples/sample_dataset.json"
export RPSD_CONTENT_TYPE="application/json"

python3 example/api_call_examples/m2m_send_file.py
```

Precedenza dei valori:

```text
argomenti CLI > variabili d'ambiente > file JSON di integrazione > default locali
```

Nota: `data_category`, `file_path` e `content_type` non sono proprieta stabili
del contratto. Il file JSON di integrazione non dovrebbe contenerli; se
presenti in vecchie copie locali vengono ignorati dallo script.

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
