// MongoDB Replica Set Initialization Script
// This runs when MongoDB starts for the first time

// Create application user
db = db.getSiblingDB('admin');

// Check if replica set is already initialized
try {
    rs.status();
    print("Replica set already initialized");
} catch (e) {
    print("Initializing replica set...");
    rs.initiate({
        _id: "rs0",
        members: [
            { _id: 0, host: "mongo:27017", priority: 1 }
        ]
    });
}

// Wait for replica set to be ready
sleep(5000);

// Create application database and user
db = db.getSiblingDB(process.env.MONGO_INITDB_DATABASE || 'app_db');

db.createUser({
    user: process.env.MONGO_APP_USERNAME || 'app_user',
    pwd: process.env.MONGO_APP_PASSWORD || 'password',
    roles: [
        { role: "readWrite", db: process.env.MONGO_INITDB_DATABASE || 'app_db' }
    ]
});

print("MongoDB initialization complete");
