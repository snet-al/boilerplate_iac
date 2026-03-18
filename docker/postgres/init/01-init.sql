-- PostgreSQL Initialization Script
-- Replication role is managed by 00-create-replication-user.sh

-- Create additional schemas if needed
CREATE SCHEMA IF NOT EXISTS app;

-- Grant permissions
GRANT ALL PRIVILEGES ON SCHEMA app TO current_user;
GRANT USAGE ON SCHEMA app TO current_user;

-- Create extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "btree_gin";

-- Enable pg_stat_statements for query monitoring
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

-- Create function for updated_at trigger
CREATE OR REPLACE FUNCTION trigger_set_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
