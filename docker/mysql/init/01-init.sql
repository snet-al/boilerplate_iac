-- MySQL Initialization Script
-- Creates replication user and sets up permissions

-- Create replication user for master-slave setup
CREATE USER IF NOT EXISTS 'replicator'@'%' IDENTIFIED BY 'REPLICATION_PASSWORD';
GRANT REPLICATION SLAVE ON *.* TO 'replicator'@'%';

-- Create application user with full access to app database
-- (Main app user is created automatically via MYSQL_USER env var)

-- Enable binary logging for replication
-- (Configured via command line arguments in docker-compose)

-- Create indexes and initial schema can go here
-- Example:
-- CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

FLUSH PRIVILEGES;
