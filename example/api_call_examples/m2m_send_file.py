#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 AGENZIA TPL BACINO CITTA' METROPOLITANA MILANO, MONZA E BRIANZA, LODI, PAVIA
# SPDX-License-Identifier: EUPL-1.2
"""Example M2M client_credentials call + file submission.

This script demonstrates the intended machine-to-machine flow:

1. exchange company client_id/client_secret for a Keycloak access token;
2. call rpsd-config M2M APIs without a Django user;
3. submit a file to rpsd-ingest using the same Bearer token.
"""

from __future__ import annotations

import base64
import json
import mimetypes
import os
import sys
from pathlib import Path
from urllib import parse, request


ROOT = Path(__file__).resolve().parent
DEFAULT_FILE = ROOT / "sample_dataset.json"


def env(name: str, default: str = "", *, required: bool = False) -> str:
    value = os.environ.get(name, default).strip()
    if required and not value:
        raise SystemExit(f"Missing required environment variable: {name}")
    return value


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


def get_client_credentials_token() -> str:
    token_url = env(
        "RPSD_KEYCLOAK_TOKEN_URL",
        "http://localhost:19300/realms/rpsd/protocol/openid-connect/token",
    )
    client_id = env("RPSD_M2M_CLIENT_ID", required=True)
    client_secret = env("RPSD_M2M_CLIENT_SECRET", required=True)
    payload = http_json(
        "POST",
        token_url,
        form={
            "grant_type": "client_credentials",
            "client_id": client_id,
            "client_secret": client_secret,
        },
    )
    token = payload.get("access_token") if isinstance(payload, dict) else None
    if not isinstance(token, str) or not token:
        raise SystemExit("Token response does not contain access_token.")
    return token


def submit_file_to_ingest(
    token: str,
    *,
    contract_code: str,
    data_category: str,
) -> dict:
    file_path = Path(env("RPSD_FILE_PATH", str(DEFAULT_FILE)))
    content = file_path.read_bytes()
    content_type = (
        env("RPSD_CONTENT_TYPE")
        or mimetypes.guess_type(file_path.name)[0]
        or "application/octet-stream"
    )
    ingest_url = env("RPSD_INGEST_URL", "http://localhost:20000/ingest")
    payload = {
        "metadata": {
            "who": contract_code,
            "what": data_category,
            "content_type": content_type,
            "custom_metadata": {
                "example_auth_flow": "m2m-client-credentials",
                "filename": file_path.name,
            },
        },
        "content": base64.b64encode(content).decode("ascii"),
    }
    response = http_json("POST", ingest_url, token=token, data=payload)
    return response if isinstance(response, dict) else {"response": response}


def main() -> int:
    config_base = env("RPSD_CONFIG_BASE_URL", "http://localhost:20100")
    contract_code = env("RPSD_CONTRACT_CODE", "CTR-001")
    data_category = env("RPSD_DATA_CATEGORY", "netex")

    token = get_client_credentials_token()
    print("M2M token obtained.")

    me = http_json(
        "GET",
        f"{config_base}/exchange_agreement/api/m2m/v1/me",
        token=token,
    )
    print("M2M identity:")
    print(json.dumps(me, indent=2, ensure_ascii=False))

    contract = http_json(
        "GET",
        f"{config_base}/exchange_agreement/api/m2m/v1/contracts/{contract_code}",
        token=token,
    )
    print("Authorized contract:")
    print(json.dumps(contract, indent=2, ensure_ascii=False))

    result = submit_file_to_ingest(
        token,
        contract_code=contract_code,
        data_category=data_category,
    )
    print("Ingest response:")
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
