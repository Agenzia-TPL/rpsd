#!/bin/bash
set -e
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

require_docker

echo -e "${GREEN}=== Starting Shared Services ===${NC}"
echo ""

# Default: start all shared infrastructure.
# Override with arguments: ./start-shared.sh kafka prefect
PROFILES=("${@}")
if [ ${#PROFILES[@]} -eq 0 ]; then
  PROFILES=("shared")
fi

# Build --profile flags
PROFILE_FLAGS=""
for p in "${PROFILES[@]}"; do
  PROFILE_FLAGS="$PROFILE_FLAGS --profile $p"
done

print_info "Profiles: ${PROFILES[*]}"
print_info "Starting services..."

cd "$RPSD_ROOT"
docker compose $PROFILE_FLAGS up -d

echo ""

# -------------------------------------------------------------------------
# Wait for health checks
# -------------------------------------------------------------------------

SHARED_CONTAINERS=(
  rpsd-kafka
  rpsd-rabbitmq
  rpsd-prefect
  rpsd-keycloak
  rpsd-config-db
)

print_info "Waiting for services to become healthy..."
for container in "${SHARED_CONTAINERS[@]}"; do
  # Only check containers that are actually running
  if docker ps --filter "name=^${container}$" --filter "status=running" --format "{{.Names}}" | grep -q "^${container}$"; then
    # Keycloak has a 90s start_period + retries, so allow more time
    local_timeout=90
    if [ "$container" = "rpsd-keycloak" ]; then
      local_timeout=200
    fi
    if wait_healthy "$container" "$local_timeout"; then
      print_success "$container is healthy"
    else
      print_warn "$container did not become healthy within timeout"
    fi
  fi
done

# -------------------------------------------------------------------------
# Post-start hooks
# -------------------------------------------------------------------------

# Ensure Keycloak realms allow plain HTTP (dev mode)
if docker ps --filter "name=^rpsd-keycloak$" --filter "status=running" --format "{{.Names}}" | grep -q "^rpsd-keycloak$"; then
  print_info "Configuring Keycloak realms for HTTP access..."
  KC_ADMIN="${RPSD_KEYCLOAK_ADMIN_USER:-admin}"
  KC_PASS="${RPSD_KEYCLOAK_ADMIN_PASS:-admin}"
  KC_CMD="/opt/keycloak/bin/kcadm.sh"
  # Authenticate to Keycloak admin CLI
  if docker exec rpsd-keycloak "$KC_CMD" config credentials \
      --server http://localhost:8080 --realm master \
      --user "$KC_ADMIN" --password "$KC_PASS" 2>/dev/null; then
    # Disable SSL requirement on all existing realms
    for realm in $(docker exec rpsd-keycloak "$KC_CMD" get realms --fields realm --format csv --noquotes 2>/dev/null); do
      docker exec rpsd-keycloak "$KC_CMD" update "realms/$realm" -s sslRequired=NONE 2>/dev/null
    done
    print_success "Keycloak realms configured for HTTP"
  else
    print_warn "Could not configure Keycloak realms (admin CLI auth failed)"
  fi
fi

# Create Kafka topics if Kafka is running
if docker ps --filter "name=^rpsd-kafka$" --filter "status=running" --format "{{.Names}}" | grep -q "^rpsd-kafka$"; then
  print_info "Creating default Kafka topics..."
  docker exec rpsd-kafka /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server localhost:9092 \
    --create --if-not-exists \
    --topic enriched-events \
    --partitions 3 \
    --replication-factor 1 \
    --config retention.ms=604800000 2>/dev/null && \
    print_success "Topic 'enriched-events' ready" || \
    print_warn "Topic creation skipped (will auto-create on first use)"
fi

# -------------------------------------------------------------------------
# Status and connection info
# -------------------------------------------------------------------------

echo ""
echo -e "${GREEN}=== Shared Services Status ===${NC}"
docker compose $PROFILE_FLAGS ps
echo ""

echo -e "${YELLOW}Connection Information:${NC}"
echo ""
if docker ps --filter "name=^rpsd-kafka$" --format "{{.Names}}" | grep -q "^rpsd-kafka$"; then
  echo -e "  Kafka:            kafka:9092 (from containers)"
  echo -e "  Kafka UI:         http://localhost:${RPSD_KAFKA_UI_PORT:-19010}"
  echo -e "  Schema Registry:  http://localhost:${RPSD_SCHEMA_REGISTRY_PORT:-19020}"
fi
if docker ps --filter "name=^rpsd-rabbitmq$" --format "{{.Names}}" | grep -q "^rpsd-rabbitmq$"; then
  echo -e "  RabbitMQ:         amqp://guest:guest@rabbitmq/ (from containers)"
  echo -e "  RabbitMQ UI:      http://localhost:${RPSD_RABBITMQ_MGMT_PORT:-19110}"
fi
if docker ps --filter "name=^rpsd-prefect$" --format "{{.Names}}" | grep -q "^rpsd-prefect$"; then
  echo -e "  Prefect API:      http://prefect:4200/api (from containers)"
  echo -e "  Prefect UI:       http://localhost:${RPSD_PREFECT_PORT:-19200}"
fi
if docker ps --filter "name=^rpsd-keycloak$" --format "{{.Names}}" | grep -q "^rpsd-keycloak$"; then
  echo -e "  Keycloak:         http://localhost:${RPSD_KEYCLOAK_PORT:-19300}"
fi
if docker ps --filter "name=^rpsd-config-db$" --format "{{.Names}}" | grep -q "^rpsd-config-db$"; then
  echo -e "  config-db:        config-db:5432 (from containers)"
  echo -e "                    localhost:${RPSD_CONFIG_DB_PORT:-20140} (from host)"
fi
echo ""
