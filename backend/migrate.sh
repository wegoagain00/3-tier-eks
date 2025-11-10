#!/bin/bash
# Exit on error
set -e

# Export Flask app
export FLASK_APP=${FLASK_APP:-run.py}

echo "Running database migrations..."

# If the migrations directory doesn't exist, this is the first run.
if [ ! -d "migrations" ]; then
    echo "Initializing migrations directory..."
    flask db init
    echo "Generating initial migration..."
    flask db migrate -m "Initial migration"
    echo "Applying initial migration..."
    flask db upgrade
else
    # If the directory exists, we just need to apply any new migrations.
    echo "Migrations directory found. Applying any new migrations..."
    flask db upgrade
fi

echo "Checking if seed data is needed..."
# Use a subshell to avoid exiting the script if psql fails when the table doesn't exist yet
TABLE_EXISTS=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USERNAME" -d "$DB_NAME" -t -c "SELECT to_regclass('public.topics');")

if [ -z "$TABLE_EXISTS" ]; then
    # This case should not be hit if flask db upgrade worked, but as a safeguard
    echo "Topics table does not exist after migration. Something is wrong."
    exit 1
fi

# Only run seed data if topics table is empty
ROW_COUNT=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USERNAME" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM topics")
# The output from psql has leading whitespace, so we need to trim it.
ROW_COUNT=$(echo $ROW_COUNT | xargs)

if [ "$ROW_COUNT" -eq "0" ]; then
    echo "Running seed data..."
    python seed_data.py
else
    echo "Database already contains data ($ROW_COUNT rows in topics table), skipping seed."
fi

echo "Database setup completed successfully!"