# SPDX-FileCopyrightText: 2026 AGENZIA TPL BACINO CITTA' METROPOLITANA MILANO, MONZA E BRIANZA, LODI, PAVIA
# SPDX-License-Identifier: EUPL-1.2
FROM postgres:17

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       postgresql-17-postgis-3 \
       postgresql-17-postgis-3-scripts \
    && rm -rf /var/lib/apt/lists/*
