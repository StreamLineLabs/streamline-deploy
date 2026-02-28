# Tutorial 3: CDC from PostgreSQL

Capture database changes in real-time from PostgreSQL to Streamline.

## Prerequisites
This tutorial requires PostgreSQL with logical replication enabled.

## Step 1: Configure PostgreSQL

```sql
-- In postgresql.conf:
-- wal_level = logical
-- max_replication_slots = 4

CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);
```

## Step 2: Start CDC Pipeline

```bash
streamline --features postgres-cdc \
  --cdc-source postgres \
  --cdc-postgres-url "postgresql://user:pass@localhost:5432/mydb" \
  --cdc-postgres-tables "public.users" \
  --cdc-postgres-slot "streamline_cdc"
```

## Step 3: Make Changes and Watch

```sql
INSERT INTO users (name, email) VALUES ('Alice', 'alice@example.com');
UPDATE users SET name = 'Alice Smith' WHERE id = 1;
DELETE FROM users WHERE id = 1;
```

```bash
streamline-cli consume cdc.public.users --from-beginning
```

Each database change appears as a structured event with before/after values.
