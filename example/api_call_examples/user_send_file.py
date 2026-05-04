#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 AGENZIA TPL BACINO CITTA' METROPOLITANA MILANO, MONZA E BRIANZA, LODI, PAVIA
# SPDX-License-Identifier: EUPL-1.2
"""Example user-authenticated call + file submission.

This script demonstrates the user-based flow:

1. use an existing user access token, or try Keycloak password grant;
2. call existing rpsd-config user APIs;
3. submit a file to rpsd-ingest using the same Bearer token.

The password grant path only works if the Keycloak client has direct access
grants enabled. In the current realm export, rpsd-config has it disabled.
"""

from __future__ import annotations

import base64
import json
import mimetypes
import os
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


def get_user_token() -> str:
    existing_token = env("RPSD_USER_ACCESS_TOKEN")
    if existing_token:
        return existing_token

    token_url = env(
        "RPSD_KEYCLOAK_TOKEN_URL",
        "http://localhost:19300/realms/rpsd/protocol/openid-connect/token",
    )
    username = env("RPSD_USER_USERNAME", required=True)
    password = env("RPSD_USER_PASSWORD", required=True)
    client_id = env("RPSD_OIDC_CLIENT_ID", "rpsd-config")
    client_secret = env("RPSD_OIDC_CLIENT_SECRET", required=True)
    payload = http_json(
        "POST",
        token_url,
        form={
            "grant_type": "password",
            "client_id": client_id,
            "client_secret": client_secret,
            "username": username,
            "password": password,
        },
    )
    token = payload.get("access_token") if isinstance(payload, dict) else None
    if not isinstance(token, str) or not token:
        raise SystemExit(
            "Token response does not contain access_token. "
            "If Keycloak rejects grant_type=password, use RPSD_USER_ACCESS_TOKEN."
        )
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
                "example_auth_flow": "user-bearer-token",
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

    token = get_user_token()
    print("User token ready.")

    contract = http_json(
        "GET",
        f"{config_base}/exchange_agreement/api/v1/contracts/{contract_code}",
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
