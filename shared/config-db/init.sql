-- SPDX-FileCopyrightText: 2026 AGENZIA TPL BACINO CITTA' METROPOLITANA MILANO, MONZA E BRIANZA, LODI, PAVIA
-- SPDX-License-Identifier: EUPL-1.2
\connect rpsd

-- Enable PostGIS extension on the default database for spatial types.
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_topology;
