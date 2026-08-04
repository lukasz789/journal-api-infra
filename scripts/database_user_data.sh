#!/bin/bash
set -e

# Check configuration provided by deploy.sh.
: "${DB_NAME:?DB_NAME is required}"
: "${DB_USER:?DB_USER is required}"
: "${DB_PASSWORD:?DB_PASSWORD is required}"
: "${API_SUBNET_CIDR:?API_SUBNET_CIDR is required}"

POSTGRES_DATA_DIR="/var/lib/pgsql/data"
POSTGRES_HBA="${POSTGRES_DATA_DIR}/pg_hba.conf"
DNF_MAX_ATTEMPTS=10
DNF_RETRY_DELAY_SECONDS=15

# A newly created NAT Gateway or route can be temporarily unavailable even
# after AWS reports it as ready. Retry package installation so a transient
# repository timeout does not permanently fail this instance's user data.
for ((attempt = 1; attempt <= DNF_MAX_ATTEMPTS; attempt++)); do
    echo "Installing PostgreSQL packages (attempt ${attempt}/${DNF_MAX_ATTEMPTS})..."

    if dnf install -y postgresql15 postgresql15-server; then
        break
    fi

    if ((attempt == DNF_MAX_ATTEMPTS)); then
        echo "PostgreSQL package installation failed after ${DNF_MAX_ATTEMPTS} attempts."
        exit 1
    fi

    echo "Package installation failed. Retrying in ${DNF_RETRY_DELAY_SECONDS} seconds..."
    dnf clean metadata || true
    sleep "$DNF_RETRY_DELAY_SECONDS"
done

# Initialize PostgreSQL.
postgresql-setup --initdb

# Start PostgreSQL now and enable automatic starts after system reboots
systemctl enable --now postgresql

# Create the application user and database.
sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';"
sudo -u postgres createdb --owner="$DB_USER" "$DB_NAME"

# Run the repository schema and grant access to the application user.
sudo -u postgres psql -v ON_ERROR_STOP=1 -d "$DB_NAME" -f /tmp/database_setup.sql
sudo -u postgres psql -d "$DB_NAME" \
    -c "GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE entries TO $DB_USER;"

# Allow PostgreSQL connections from the application subnet.
sudo -u postgres psql -c "ALTER SYSTEM SET listen_addresses = '*';"

PG_HBA_RULE="host    ${DB_NAME}    ${DB_USER}    ${API_SUBNET_CIDR}    scram-sha-256"
echo "$PG_HBA_RULE" >> "$POSTGRES_HBA"

systemctl restart postgresql

echo "Database setup completed."
