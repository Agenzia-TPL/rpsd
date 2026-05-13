#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 AGENZIA TPL BACINO CITTA' METROPOLITANA MILANO, MONZA E BRIANZA, LODI, PAVIA
# SPDX-License-Identifier: EUPL-1.2
"""Example M2M client_credentials call + file submission.

This script demonstrates the intended machine-to-machine flow:

1. exchange company client_id/client_secret for a Keycloak access token;
2. call rpsd-config M2M APIs without a Django user;
3. ask rpsd-config if this client can ingest this data category;
4. submit a file to rpsd-ingest using the same Bearer token.

The optional JSON config describes the stable company/contract integration:
client credentials, contract code and service endpoints. The file submitted to
ingest is intentionally a per-call concern and should normally be passed from
CLI with --data-category, --file and --content-type.
"""

from __future__ import annotations

import argparse
import base64
import json
import mimetypes
import os
import time
from dataclasses import dataclass
from pathlib import Path
from urllib import parse, request


ROOT = Path(__file__).resolve().parent
DEFAULT_FILE = ROOT / "sample_dataset.json"
DEFAULT_DATA_CATEGORY = "netex"
DEFAULT_CONTENT_TYPE = "application/json"


@dataclass(frozen=True)
class RuntimeConfig:
    token_url: str
    config_base_url: str
    ingest_url: str
    client_id: str
    client_secret: str
    contract_code: str
    data_category: str
    file_path: Path
    content_type: str


@dataclass(frozen=True)
class AccessToken:
    value: str
    expires_at: float

    def expires_soon(self, *, skew_seconds: int = 30) -> bool:
        return time.time() >= self.expires_at - skew_seconds


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Send a sample file to RPSD ingest using M2M credentials."
    )
    parser.add_argument(
        "--config",
        type=Path,
        help="JSON configuration file with M2M credentials and endpoints.",
    )
    parser.add_argument("--file", type=Path, help="File to submit to rpsd-ingest.")
    parser.add_argument("--client-id", help="M2M Keycloak client_id.")
    parser.add_argument("--client-secret", help="M2M Keycloak client_secret.")
    parser.add_argument("--contract-code", help="Contract code used as metadata.who.")
    parser.add_argument("--data-category", help="Data category used as metadata.what.")
    parser.add_argument("--content-type", help="Content type of the submitted file.")
    return parser.parse_args()


def load_config_file(path: Path | None) -> dict:
    if path is None:
        return {}
    try:
        with path.open(encoding="utf-8") as handle:
            payload = json.load(handle)
    except FileNotFoundError as exc:
        raise SystemExit(f"Config file not found: {path}") from exc
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Config file is not valid JSON: {path}\n{exc}") from exc

    if not isinstance(payload, dict):
        raise SystemExit("Config file must contain a JSON object.")
    return payload


def setting(
    *,
    config: dict,
    key: str,
    env_name: str,
    default: str = "",
    cli_value: str | Path | None = None,
    required: bool = False,
) -> str:
    if cli_value is not None:
        value = str(cli_value).strip()
    else:
        value = os.environ.get(env_name, "").strip()
        if not value:
            raw_value = config.get(key, default)
            value = str(raw_value).strip() if raw_value is not None else ""

    if required and not value:
        raise SystemExit(
            f"Missing required setting: {key} "
            f"(or environment variable {env_name})."
        )
    return value


def build_runtime_config(args: argparse.Namespace) -> RuntimeConfig:
    config = load_config_file(args.config)
    file_path = setting(
        config={},
        key="file_path",
        env_name="RPSD_FILE_PATH",
        default=str(DEFAULT_FILE),
        cli_value=args.file,
    )
    return RuntimeConfig(
        token_url=setting(
            config=config,
            key="token_url",
            env_name="RPSD_KEYCLOAK_TOKEN_URL",
            default="http://localhost:19300/realms/rpsd/protocol/openid-connect/token",
        ),
        config_base_url=setting(
            config=config,
            key="config_base_url",
            env_name="RPSD_CONFIG_BASE_URL",
            default="http://localhost:20100",
        ),
        ingest_url=setting(
            config=config,
            key="ingest_url",
            env_name="RPSD_INGEST_URL",
            default="http://localhost:20000/ingest",
        ),
        client_id=setting(
            config=config,
            key="client_id",
            env_name="RPSD_M2M_CLIENT_ID",
            cli_value=args.client_id,
            required=True,
        ),
        client_secret=setting(
            config=config,
            key="client_secret",
            env_name="RPSD_M2M_CLIENT_SECRET",
            cli_value=args.client_secret,
            required=True,
        ),
        contract_code=setting(
            config=config,
            key="contract_code",
            env_name="RPSD_CONTRACT_CODE",
            default="CTR-001",
            cli_value=args.contract_code,
        ),
        data_category=setting(
            config={},
            key="data_category",
            env_name="RPSD_DATA_CATEGORY",
            default=DEFAULT_DATA_CATEGORY,
            cli_value=args.data_category,
        ),
        file_path=Path(file_path),
        content_type=setting(
            config={},
            key="content_type",
            env_name="RPSD_CONTENT_TYPE",
            default=DEFAULT_CONTENT_TYPE,
            cli_value=args.content_type,
        ),
    )


def http_json(
    method: str,
    url: str,
    *,
    token: str | None = None,
    data: dict | None = None,
    form: dict | None = None,
) -> dict | list:
    headers = {"Accept": "application/json"}
    body = None
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if form is not None:
        body = parse.urlencode(form).encode("utf-8")
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    elif data is not None:
        body = json.dumps(data).encode("utf-8")
        headers["Content-Type"] = "application/json"

    req = request.Request(url, data=body, headers=headers, method=method)
    try:
        with request.urlopen(req, timeout=30) as response:
            raw = response.read().decode("utf-8")
            return json.loads(raw) if raw else {}
    except Exception as exc:
        raise SystemExit(f"HTTP call failed: {method} {url}\n{exc}") from exc


def get_client_credentials_token(config: RuntimeConfig) -> AccessToken:
    payload = http_json(
        "POST",
        config.token_url,
        form={
            "grant_type": "client_credentials",
            "client_id": config.client_id,
            "client_secret": config.client_secret,
        },
    )
    token = payload.get("access_token") if isinstance(payload, dict) else None
    if not isinstance(token, str) or not token:
        raise SystemExit("Token response does not contain access_token.")
    expires_in = payload.get("expires_in", 300)
    try:
        expires_in_seconds = int(expires_in)
    except (TypeError, ValueError):
        expires_in_seconds = 300
    return AccessToken(value=token, expires_at=time.time() + expires_in_seconds)


def authorize_ingest(
    token: str,
    *,
    config_base: str,
    contract_code: str,
    data_category: str,
) -> dict:
    query = parse.urlencode({"data_category": data_category})
    response = http_json(
        "GET",
        (
            f"{config_base}/exchange_agreement/api/m2m/v1/contracts/"
            f"{parse.quote(contract_code, safe='')}/ingest-authorization?{query}"
        ),
        token=token,
    )
    return response if isinstance(response, dict) else {"response": response}


def submit_file_to_ingest(
    token: str,
    *,
    config: RuntimeConfig,
    contract_code: str,
    data_category: str,
) -> dict:
    content = config.file_path.read_bytes()
    content_type = (
        config.content_type
        or mimetypes.guess_type(config.file_path.name)[0]
        or "application/octet-stream"
    )
    payload = {
        "metadata": {
            "who": contract_code,
            "what": data_category,
            "content_type": content_type,
            "custom_metadata": {
                "example_auth_flow": "m2m-client-credentials",
                "filename": config.file_path.name,
            },
        },
        "content": base64.b64encode(content).decode("ascii"),
    }
    response = http_json("POST", config.ingest_url, token=token, data=payload)
    return response if isinstance(response, dict) else {"response": response}


def main() -> int:
    config = build_runtime_config(parse_args())

    access_token = get_client_credentials_token(config)
    print("M2M token obtained.")

    me = http_json(
        "GET",
        f"{config.config_base_url}/exchange_agreement/api/m2m/v1/me",
        token=access_token.value,
    )
    print("M2M identity:")
    print(json.dumps(me, indent=2, ensure_ascii=False))

    contract = http_json(
        "GET",
        (
            f"{config.config_base_url}/exchange_agreement/api/m2m/v1/contracts/"
            f"{parse.quote(config.contract_code, safe='')}"
        ),
        token=access_token.value,
    )
    print("Authorized contract:")
    print(json.dumps(contract, indent=2, ensure_ascii=False))

    authorization = authorize_ingest(
        access_token.value,
        config_base=config.config_base_url,
        contract_code=config.contract_code,
        data_category=config.data_category,
    )
    print("Ingest authorization:")
    print(json.dumps(authorization, indent=2, ensure_ascii=False))

    if access_token.expires_soon():
        access_token = get_client_credentials_token(config)
        print("M2M token refreshed before ingest submission.")

    result = submit_file_to_ingest(
        access_token.value,
        config=config,
        contract_code=config.contract_code,
        data_category=config.data_category,
    )
    print("Ingest response:")
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
