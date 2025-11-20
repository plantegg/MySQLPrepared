# MySQL PreparedStatement Performance Issue Reproduction Project

## Project Introduction

This project is used to reproduce a severe performance issue in MySQL when using `useServerPrepStmts=true` to handle PreparedStatement queries with a large number of parameters (50,000). Test results show that server-side prepared statements are **190-207 times** slower than client-side prepared statements.

## Project Structure

```
prepared/
├── README.md                                           # Project documentation
├── MySQL_PreparedStatement_Performance_Issue_Reproduction.md  # Detailed reproduction documentation
├── pom.xml                                            # Maven configuration
├── create_table.sql                                   # Database table schema
├── run_test.sh                                        # One-click test script
└── src/main/java/com/test/
    └── PreparedStatementPerformanceTest.java         # Main test class
```

## Prerequisites

Before running the tests, please ensure the following conditions are met:

### 1. MySQL Database

You need an accessible MySQL database instance and prepare the following connection parameters:

| Parameter | Description | Example |
|-----------|-------------|---------|
| **Host** | IP address or domain name of the MySQL server | `localhost` or `your-mysql-host` |
| **Port** | MySQL server port | `3306` |
| **Database** | Database name used for testing (can be an existing database) | `test` or `mysql` |
| **Username** | User with access permissions to the database | `root` or `testuser` |
| **Password** | Database user password | `mypassword` |

> **Note**:
> - The script will automatically create the `large_table` table. If the table already exists, it will be deleted first.
> - The test data is an empty table and will not affect existing data.
> - It is recommended to run in a **test environment** to avoid affecting production data.

### 2. Environment Dependencies

Ensure the following software is installed on your system:

- **Java**: 8 or higher
- **Maven**: 3.6 or higher
- **MySQL Client**: Used for automatic table creation (required only when using `run_test.sh`)

### 3. Network Connection

Ensure the machine running the test can access the MySQL database server.

## Quick Start

### View Help Information

```bash
./run_test.sh --help
```

### Method 1: Using the Script (Recommended) ✨

The script automatically performs the following operations:
1. ✅ Checks environment dependencies (Java, Maven, MySQL Client)
2. ✅ Automatically creates the test table `large_table`
3. ✅ Compiles the project
4. ✅ Runs the performance test

#### Using Named Parameters (Recommended)

```bash
# Basic usage (default runs 2 times)
./run_test.sh --host localhost --port 3306 --database test --user root --password mypass

# Custom execution times (run 10 times to get a more stable average)
./run_test.sh --host localhost --port 3306 --database test --user root --password mypass --rounds 10

# Quick test (run only 1 time)
./run_test.sh --host localhost --port 3306 --database test --user root --password mypass --rounds 1
```

#### Using Positional Parameters (Backward Compatible)

```bash
./run_test.sh localhost 3306 test root mypassword
```

### Method 2: Using Maven

```bash
# Manually create the table first
mysql -h localhost -P 3306 -u root -p test < create_table.sql

# Compile and run the test (default 2 times)
mvn compile exec:java \
    -Dexec.mainClass="com.test.PreparedStatementPerformanceTest" \
    -Ddb.host=localhost \
    -Ddb.port=3306 \
    -Ddb.name=test \
    -Ddb.user=root \
    -Ddb.password=mypassword

# Custom execution times (10 times)
mvn compile exec:java \
    -Dexec.mainClass="com.test.PreparedStatementPerformanceTest" \
    -Ddb.host=localhost \
    -Ddb.port=3306 \
    -Ddb.name=test \
    -Ddb.user=root \
    -Ddb.password=mypassword \
    -Dtest.rounds=10
```

### Method 3: Using Environment Variables

```bash
export DB_HOST=localhost
export DB_PORT=3306
export DB_NAME=test
export DB_USER=root
export DB_PASSWORD=mypassword
export TEST_ROUNDS=5  # Optional, default is 2

# Manually create the table first
mysql -h $DB_HOST -P $DB_PORT -u $DB_USER -p$DB_PASSWORD $DB_NAME < create_table.sql

# Run the test
mvn compile exec:java -Dexec.mainClass="com.test.PreparedStatementPerformanceTest"
```

## Command Line Argument Description

### Arguments Supported by run_test.sh

| Argument | Required/Optional | Description | Default Value |
|----------|-------------------|-------------|---------------|
| `--host` | Required | MySQL server address | - |
| `--port` | Required | MySQL server port | - |
| `--database` | Required | Database name | - |
| `--user` | Required | Database username | - |
| `--password` | Required | Database password | - |
| `--rounds` | Optional | Number of SQL execution repetitions | 2 |
| `--help` | Optional | Show help information | - |

### System Properties Supported by Java Program

| System Property | Environment Variable | Description | Default Value |
|-----------------|----------------------|-------------|---------------|
| `db.host` | `DB_HOST` | MySQL server address | - |
| `db.port` | `DB_PORT` | MySQL server port | - |
| `db.name` | `DB_NAME` | Database name | - |
| `db.user` | `DB_USER` | Database username | - |
| `db.password` | `DB_PASSWORD` | Database password | - |
| `test.rounds` | `TEST_ROUNDS` | Number of SQL execution repetitions | 2 |

## Expected Test Results

### Typical Performance Data

| Configuration | Average Execution Time | Performance Difference | Com_stmt_prepare |
|---------------|------------------------|------------------------|------------------|
| `useServerPrepStmts=false` | ~48ms | Baseline | 0 |
| `useServerPrepStmts=true` | ~9,158ms | **190x Slower** | 1 |

### Test Output Example

```
=== useServerPrepStmts=false Test Results ===
Total Execution Time: 96ms
Average Execution Time: 48.0ms
Returned Records: 0
Com_stmt_prepare: 0 → 0

=== useServerPrepStmts=true Test Results ===
Total Execution Time: 18316ms
Average Execution Time: 9158.0ms
Returned Records: 0
Com_stmt_prepare: 0 → 1
```

## Environment Requirements

- **Java**: 8 or higher
- **Maven**: 3.6 or higher
- **MySQL**: 5.7 or higher
- **MySQL Client**: Used for automatic table creation (required when using `run_test.sh`)
- **Operating System**: Linux, macOS, or Windows (requires bash)

## Database Table Structure

The test requires the `large_table` table, which contains the following fields:
- `id` (int, PRIMARY KEY) - Used for IN queries
- `col1` ~ `col20` (varchar) - 20 auxiliary columns used to simulate multi-column queries

If using `run_test.sh`, the table is created automatically. If running manually, please execute first:

```bash
mysql -h <host> -P <port> -u <user> -p <database> < create_table.sql
```

## Test Parameter Configuration

### Default Test Configuration

- **Parameter Count**: 50,000 large integers
- **SQL Format**: Multi-line format (includes newlines, approx. 2.1MB)
- **Test Rounds**: 2 times (adjustable via `--rounds`)
- **Parameter Type**: 15-digit large integers (e.g., 176302640511975)

### --rounds Parameter Usage Recommendations

| Scenario | Recommended Value | Description |
|----------|-------------------|-------------|
| Quick Environment Verification | `--rounds 1` | Verify configuration correctness |
| Standard Test | `--rounds 2` | Default value, balances speed and accuracy |
| Precise Test | `--rounds 10` | Obtain more stable average performance data |
| Stress Test | `--rounds 100` | Observe performance over long runs |

## Monitoring and Observation

### Observing MySQL Process Status

During the test run, you can execute the following in another terminal:

```sql
SHOW PROCESSLIST;
```

When `useServerPrepStmts=true`, you can see the query staying in the `starting` state for 8-9 seconds.

### Performance Analysis

During the test, MySQL performs a large number of:
- String replacement operations (`String::replace`)
- Memory reallocation (`my_realloc`)
- Memory copying (`memmove`)

These operations cause severe performance issues when processing a 2.1MB SQL string and 50,000 parameters.

## Notes

1. ⚠️ **Test Environment**: It is recommended to run in a test environment to avoid affecting production data.
2. 📊 **Observe Processes**: Execute `SHOW PROCESSLIST` during the test to observe process status.
3. ✅ **Empty Table Test**: The test can run on an empty table; actual data is not required.
4. 🔒 **Security**: Passwords in the command line will trigger a warning; for production environments, it is recommended to use configuration files or environment variables.
5. ⏱️ **Timeout Setting**: The script has a 600-second timeout to prevent the test from hanging indefinitely.

## Problem Reproduction and Solution

### Problem Cause

1. **Server-side Parameter Processing Overhead**: MySQL needs to handle massive parameter replacements in the `starting` state.
2. **Frequent Memory Reallocation**: Large integer parameters cause frequent string expansion and memory copying.
3. **SQL Parsing Complexity**: Multi-line format SQL increases parsing overhead.

### Recommended Solutions

#### ✅ Solution 1: Use Client-side Prepared Statements (Recommended)

```java
String url = "jdbc:mysql://host:port/database?useServerPrepStmts=false";
```

**Pros**: Excellent performance, completing in under 50ms even with 50,000 parameters.

#### 🔄 Solution 2: Batch Query

Split the large IN query into multiple small queries (e.g., 1000 parameters per batch).

#### 📋 Solution 3: Temporary Table Solution

Insert parameters into a temporary table and use JOIN instead of IN query.

## Project Verification

This project successfully reproduced the severe performance issue caused by `useServerPrepStmts=true` in a production environment, verifying the necessity of using `useServerPrepStmts=false` when handling large parameter queries.

## Detailed Documentation

For more technical details, performance analysis, and stack traces, please refer to:
[MySQL_PreparedStatement_Performance_Issue_Reproduction.md](./MySQL_PreparedStatement_Performance_Issue_Reproduction.md)

## Security Note

This project does not contain any hardcoded sensitive information. All database connection parameters are securely passed via:
- Command line arguments
- System properties
- Environment variables

## Contribution

Issues and Pull Requests are welcome!

## License

MIT License
