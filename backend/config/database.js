require('dotenv').config();
const sql = require('mssql');

// ---------------------------------------------------------
// SQL SERVER CONFIGURATION
// ---------------------------------------------------------

const SQL_SERVER = process.env.SQL_SERVER || 'localhost';
const SQL_DATABASE = process.env.SQL_DATABASE || 'SchoolDW';
const SQL_DRIVER = process.env.SQL_DRIVER || 'ODBC Driver 17 for SQL Server';

const SQL_AUTH = (
    process.env.SQL_AUTH || 'windows'
).toLowerCase();

const SQL_TRUST_SERVER_CERTIFICATE =
    String(process.env.SQL_TRUST_SERVER_CERTIFICATE || 'true')
        .toLowerCase() === 'true';

// Create config object for mssql connection
const config = {
    server: SQL_SERVER,
    database: SQL_DATABASE,
    options: {
        trustServerCertificate: SQL_TRUST_SERVER_CERTIFICATE,
        encrypt: false,
        connectTimeout: 15000
    }
};

// Add authentication based on type
if (SQL_AUTH === 'sql' || SQL_AUTH === 'sqlserver') {
    config.authentication = {
        type: 'default',
        options: {
            userName: process.env.SQL_USER || '',
            password: process.env.SQL_PASSWORD || ''
        }
    };
} else {
    // Windows authentication (default)
    config.authentication = {
        type: 'ntlm',
        options: {}
    };
}

let pool;

const connect = async () => {
    try {
        console.log('');
        console.log('🔗 Connecting to SQL Server...');
        console.log(`   Server: ${SQL_SERVER}`);
        console.log(`   Database: ${SQL_DATABASE}`);
        console.log(`   Driver: ${SQL_DRIVER}`);
        console.log(`   Auth: ${SQL_AUTH}`);
        console.log(`   Trust Certificate: ${SQL_TRUST_SERVER_CERTIFICATE}`);
        
        pool = new sql.ConnectionPool(config);
        await pool.connect();
        console.log('✅ Connected to SQL Server successfully!');
        console.log('');
        return pool;
    } catch (err) {
        console.error('');
        console.error('❌ Database connection error:');
        console.error(`   ${err.message}`);
        console.error('');
        console.error('💡 Troubleshooting:');
        console.error('   1. Check if SQL Server is running');
        console.error(`   2. Verify database exists: ${SQL_DATABASE}`);
        console.error('   3. Check authentication settings in .env:');
        console.error(`      - SQL_AUTH=${SQL_AUTH}`);
        console.error(`      - SQL_SERVER=${SQL_SERVER}`);
        console.error(`      - SQL_DATABASE=${SQL_DATABASE}`);
        if (SQL_AUTH === 'sql') {
            console.error(`      - SQL_USER=${process.env.SQL_USER || 'NOT SET'}`);
            console.error(`      - SQL_PASSWORD=${process.env.SQL_PASSWORD ? '****' : 'NOT SET'}`);
        }
        console.error('   4. Check firewall/network settings');
        console.error('');
        throw err;
    }
};

const getPool = () => {
    if (!pool) {
        throw new Error('Database pool not initialized. Call connect() first.');
    }
    return pool;
};

const disconnect = async () => {
    if (pool) {
        await pool.close();
        console.log('✅ Disconnected from SQL Server');
    }
};

module.exports = {
    connect,
    getPool,
    disconnect,
    sql
};
