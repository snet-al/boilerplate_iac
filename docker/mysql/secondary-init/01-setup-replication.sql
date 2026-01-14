-- MySQL Secondary (Slave) Replication Setup
-- Run this after the primary is ready

-- Stop any existing replication
STOP SLAVE;
RESET SLAVE ALL;

-- Configure replication from primary
-- Note: Replace placeholders with actual values or use environment variables
CHANGE MASTER TO
    MASTER_HOST='mysql-primary',
    MASTER_PORT=3306,
    MASTER_USER='replicator',
    MASTER_PASSWORD='REPLICATION_PASSWORD',
    MASTER_AUTO_POSITION=1,
    GET_MASTER_PUBLIC_KEY=1;

-- Start replication
START SLAVE;

-- Show slave status to verify
SHOW SLAVE STATUS\G
