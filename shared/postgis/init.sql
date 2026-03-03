\connect rpsd

-- Enable PostGIS extension on the default database for spatial types.
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_topology;
