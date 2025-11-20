# MySQL PreparedStatement Performance Issue Reproduction Document

## Problem Description

In a production environment, it was found that PreparedStatement queries containing a large number of parameters perform extremely poorly when using the `useServerPrepStmts=true` parameter. System testing revealed that **SQL format and length have a huge impact on performance**.

## Environment Information

- **MySQL Version**: 5.7.29
- **JDBC Driver**: mysql-connector-j-8.0.33
- **Test Scenario**: IN query with 50,000 large integer parameters
- **Parameter Format**: 15-digit large integers (e.g., 176302640511975)
- **Reproduction Code**: https://github.com/plantegg/MySQLPrepared

## Core Findings

### 🔥 Huge Impact of SQL Format on Performance

We found that **the format and length of the SQL string** are key factors affecting server-side prepared statement performance:

| SQL Format | SQL Length | false Avg Time | true Avg Time | Performance Difference |
|------------|------------|----------------|---------------|------------------------|
| **Compact Format** (?,?,?) | **100KB** | **35ms** | **645ms** | **18x Slower** ⭐ Best |
| Newline Format | 2.1MB | 47ms | 9,128ms | 194x Slower |
| Newline + Spaces (128) | 6.5MB | 52ms | 27,839ms | 535x Slower |
| Newline + Many Spaces (128) | 8.5MB | 62ms | 44,521ms | 712x Slower 🔥 Worst |

**Key Conclusions**:
- ✅ **Optimized compact format** can improve server-side performance by **14 times** (9,128ms → 645ms).
- ⚠️ Even after optimization, client-side prepared statements (35ms) are still **18 times** faster than server-side (645ms).

## Reproduction Steps

### 1. Environment Preparation

Create the test table:

```bash
mysql -h your-host -P your-port -u your-user -p your-database < create_table.sql
```

Content of `create_table.sql`:

```sql
DROP TABLE IF EXISTS `large_table`;

CREATE TABLE `large_table` (
  `id` int(11) NOT NULL,
  `col1` varchar(50) COLLATE utf8_unicode_ci DEFAULT NULL,
  `col2` varchar(50) COLLATE utf8_unicode_ci DEFAULT NULL,
  -- ... col3-col19 ...
  `col20` varchar(50) COLLATE utf8_unicode_ci DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
```

### 2. Run Tests

#### Using Script (Recommended)

```bash
# Best configuration (compact format)
./run_test.sh --host localhost --port 3306 --database test \
  --user root --password mypass --spaces 0

# Test the impact of different space configurations
./run_test.sh --host localhost --port 3306 --database test \
  --user root --password mypass --spaces 128

# View help
./run_test.sh --help
```

#### Using Maven

```bash
mvn compile exec:java \
    -Dexec.mainClass="com.test.PreparedStatementPerformanceTest" \
    -Ddb.host=localhost \
    -Ddb.port=3306 \
    -Ddb.name=test \
    -Ddb.user=root \
    -Ddb.password=mypassword \
    -Dparam.spaces=0
```

### 3. Parameter Description

| Parameter | Default Value | Description |
|-----------|---------------|-------------|
| `--spaces` | 128 | Number of spaces between parameters, 0=most compact format |
| `--rounds` | 2 | Test rounds |

## Detailed Test Results

### Test 1: Compact Format (spaces=0) ⭐ Recommended

**SQL Example**: `WHERE id IN (?,?,?,?,...)`

```
Config: useServerPrepStmts=false
SQL Length: 100,151 chars (~100KB)
Avg Execution Time: 35.0ms
Com_stmt_prepare: 0

Config: useServerPrepStmts=true
SQL Length: 100,151 chars (~100KB)
Avg Execution Time: 645.5ms
Com_stmt_prepare: 1

Performance Difference: 18x Slower
```

### Test 2: Newline Format (Old Version)

**SQL Example**:
```sql
WHERE id IN (?
                  ,
                    ?
                  ,
                    ?
```

```
Config: useServerPrepStmts=false
SQL Length: 2,100,111 chars (~2.1MB)
Avg Execution Time: 47.0ms
Com_stmt_prepare: 0

Config: useServerPrepStmts=true
SQL Length: 2,100,111 chars (~2.1MB)
Avg Execution Time: 9,128.5ms
Com_stmt_prepare: 1

Performance Difference: 194x Slower
```

### Test 3: Spaced Format (spaces=128)

**SQL Example**: `WHERE id IN (?,<128 spaces>?,<128 spaces>?,...)`

```
Config: useServerPrepStmts=false
SQL Length: 6,500,023 chars (~6.5MB)
Avg Execution Time: 52.0ms
Com_stmt_prepare: 0

Config: useServerPrepStmts=true
SQL Length: 6,500,023 chars (~6.5MB)
Avg Execution Time: 27,839.5ms
Com_stmt_prepare: 1

Performance Difference: 535x Slower
```

### Test 4: Newline + Many Spaces (Extreme Case)

```
Config: useServerPrepStmts=false
SQL Length: 8,499,983 chars (~8.5MB)
Avg Execution Time: 62.5ms
Com_stmt_prepare: 0

Config: useServerPrepStmts=true
SQL Length: 8,499,983 chars (~8.5MB)
Avg Execution Time: 44,521.5ms
Com_stmt_prepare: 1

Performance Difference: 712x Slower
```

## Performance Analysis

### 1. Linear Relationship Between SQL Length and Performance

Server-side prepared statement performance deteriorates linearly with SQL length:

```
100KB  SQL → 645ms    (Baseline)
2.1MB  SQL → 9,128ms  (14x worse)
6.5MB  SQL → 27,839ms (43x worse)
8.5MB  SQL → 44,521ms (69x worse)
```

### 2. Stability of Client-side Prepared Statements

Client-side prepared statements are almost unaffected by SQL length:

```
100KB  SQL → 35-47ms
8.5MB  SQL → 62ms
Variation: Only 77%
```

### 3. Root Cause

According to `pstack` analysis, when server-side prepared statements handle large SQL:

1. **Massive Memory Reallocation**:
   - 50,000 parameter replacement operations
   - Each replacement requires locating and replacing in the large SQL string
   - Frequent calls to `my_realloc` and `memmove`

2. **String Operation Complexity**:
   - O(SQL Length) × Parameter Count = Extremely high time complexity
   - Single thread 100% CPU usage

3. **Memory Fragmentation**:
   - Frequent large block memory allocation and deallocation
   - Further degrades performance


```
Thread 1 (Thread 0x7feeb8043640 (LWP 2508284)):
#0  0x00007ff302bb5515 in __memmove_avx512_unaligned_erms () from /lib64/libc.so.6
#1  0x0000000000efffe6 in my_realloc (key=<optimized out>, ptr=0x7fee5e907380, size=7192160, flags=<optimized out>) at /export/home/pb2/build/sb_0-37309218-1576676711.18/mysql-5.7.29/mysys/my_malloc.c:112
#2  0x0000000000d9a921 in String::mem_realloc (this=0x7feeb80424b0, alloc_length=7192155, force_on_heap=force_on_heap@entry=false) at /export/home/pb2/build/sb_0-37309218-1576676711.18/mysql-5.7.29/sql-common/sql_string.cc:128
#3  0x0000000000d9b9d4 in String::replace (this=this@entry=0x7feeb80424b0, offset=7119079, arg_length=arg_length@entry=1, to=0x7fee5c3f5810 "286381588518215", to_length=15) at /export/home/pb2/build/sb_0-37309218-1576676711.18/mysql-5.7.29/sql-common/sql_string.cc:804
#4  0x0000000000d9ba81 in String::replace (this=this@entry=0x7feeb80424b0, offset=<optimized out>, arg_length=arg_length@entry=1, to=...) at /export/home/pb2/build/sb_0-37309218-1576676711.18/mysql-5.7.29/sql-common/sql_string.cc:783
#5  0x0000000000d026e2 in Prepared_statement::insert_params (this=this@entry=0x7fee5c171fe0, null_array=null_array@entry=0x7fee5c45240a "", read_pos=0x7fee5c4ccc05 "\336\274y\206", <incomplete sequence \303>, read_pos@entry=0x7fee5c46c315 "\016r\342\320\355\242\002", data_end=0x7fee5c4cdd95 "", query=query@entry=0x7feeb80424b0) at /export/home/pb2/build/sb_0-37309218-1576676711.18/mysql-5.7.29/sql/sql_prepare.cc:924
#6  0x0000000000d03db6 in Prepared_statement::set_parameters (this=this@entry=0x7fee5c171fe0, expanded_query=expanded_query@entry=0x7feeb80424b0, packet=0x7fee5c46c315 "\016r\342\320\355\242\002", packet_end=<optimized out>) at /export/home/pb2/build/sb_0-37309218-1576676711.18/mysql-5.7.29/sql/sql_prepare.cc:3496
#7  0x0000000000d0772f in Prepared_statement::execute_loop (this=0x7fee5c171fe0, expanded_query=0x7feeb80424b0, open_cursor=<optimized out>, packet=<optimized out>, packet_end=<optimized out>) at /export/home/pb2/build/sb_0-37309218-1576676711.18/mysql-5.7.29/sql/sql_prepare.cc:3559
#8  0x0000000000d07aa4 in mysqld_stmt_execute (thd=thd@entry=0x7fee5c000b60, stmt_id=<optimized out>, flags=0, params=0x7fee5c45240a "", params_length=506251) at /export/home/pb2/build/sb_0-37309218-1576676711.18/mysql-5.7.29/sql/sql_prepare.cc:2582
#9  0x0000000000cdf6f5 in dispatch_command (thd=thd@entry=0x7fee5c000b60, com_data=com_data@entry=0x7feeb8042d40, command=COM_STMT_EXECUTE) at /export/home/pb2/build/sb_0-37309218-1576676711.18/mysql-5.7.29/sql/sql_parse.cc:1428
#10 0x0000000000ce00c7 in do_command (thd=thd@entry=0x7fee5c000b60) at /export/home/pb2/build/sb_0-37309218-1576676711.18/mysql-5.7.29/sql/sql_parse.cc:1032
#11 0x0000000000d9cc08 in handle_connection (arg=arg@entry=0x1eb0a010) at /export/home/pb2/build/sb_0-37309218-1576676711.18/mysql-5.7.29/sql/conn_handler/connection_handler_per_thread.cc:313
#12 0x00000000013fc4a4 in pfs_spawn_thread (arg=0x1ea71270) at /export/home/pb2/build/sb_0-37309218-1576676711.18/mysql-5.7.29/storage/perfschema/pfs.cc:2197
#13 0x00007ff30305b3fb in start_thread () from /lib64/libpthread.so.0
#14 0x00007ff302b0de83 in clone () from /lib64/libc.so.6
```

### Monitoring Data

```
# top monitoring
PID     USER   %CPU  TIME+     COMMAND
2554029 mysql  99.3  4:40.64   mysqld  // Single thread 100%

# show processlist observation
Id  User  Command  Time  State     Info
382 test  Execute  8     starting  NULL  // SQL is still being assembled
```

## Solutions

### ✅ Solution 1: Use Client-side Prepared Statements + Compact Format (Strongly Recommended)

```java
// JDBC Connection String
String url = "jdbc:mysql://host:port/database?useServerPrepStmts=false";

// Run Test
./run_test.sh --host localhost --port 3306 --database test \
  --user root --password mypass --spaces 0
```

**Pros**:
- ✅ Optimal performance: only 35ms
- ✅ Unaffected by SQL length
- ✅ Unaffected by parameter count
- ✅ Stable and reliable

**Cons**:
- ⚠️ Cannot enjoy server-side query plan caching (but not significant for IN queries)

### 🔄 Solution 2: Optimize SQL Format (If Server-side Prepared Statements Must Be Used)

If you must use `useServerPrepStmts=true` for some reason, be sure to optimize the SQL format:

```java
// Use most compact format: ?,?,?,?
// Avoid: ?\n  ,\n  ?

String url = "jdbc:mysql://host:port/database?useServerPrepStmts=true";
// Use --spaces 0 at runtime
```

**Performance**: 645ms (14x improvement compared to unoptimized 9,128ms)

### 🔧 Solution 3: Batch Query

```java
// Split 50,000 parameters into 50 batches, 1,000 per batch
int batchSize = 1000;
for (int i = 0; i < ids.size(); i += batchSize) {
    List<Long> batch = ids.subList(i, Math.min(i + batchSize, ids.size()));
    // Execute query
}
```

### 🗃️ Solution 4: Temporary Table Solution

```sql
CREATE TEMPORARY TABLE temp_ids (id BIGINT);
INSERT INTO temp_ids VALUES (?), (?), ...;
SELECT * FROM large_table WHERE id IN (SELECT id FROM temp_ids);
DROP TEMPORARY TABLE temp_ids;
```

## Best Practices

### ✅ Recommended Configuration

| Scenario | useServerPrepStmts | spaces | Expected Performance |
|----------|--------------------|--------|----------------------|
| **Production** | false | 0 | 35ms ⭐ Optimal |
| Standard Test | false | 0 | 35-50ms |
| Must use Server-side Prep | true | 0 | 645ms |

### ❌ Configurations to Avoid

| Scenario | useServerPrepStmts | SQL Format | Performance |
|----------|--------------------|------------|-------------|
| ❌ With Formatting | true | With newlines/indentation | 9,128ms 194x Slower |
| ❌ Many Spaces | true | spaces > 0 | 27,839ms 535x Slower |
| ❌ Extreme Case | true | Many newlines+spaces | 44,521ms 712x Slower |

### 🎯 Implementation Suggestions

1. **Development Phase**:
   - Set `useServerPrepStmts=false`
   - Use `--spaces 0` for testing

2. **Test Phase**:
   - Compare performance of different configurations
   - Use `SHOW PROCESSLIST` for monitoring

3. **Production Environment**:
   - Enforce client-side prepared statements
   - Avoid large parameter IN queries
   - If necessary, consider batch or temporary table solutions

## Complete Comparison Table

| Configuration | SQL Format | SQL Length | false Avg | true Avg | Performance Difference |
|---------------|------------|------------|-----------|----------|------------------------|
| **Optimal** | ?,?,? | 100KB | 35ms | 645ms | 18x Slower ⭐ |
| With Newlines | ?\n,\n? | 2.1MB | 47ms | 9,128ms | 194x Slower |
| +Spaces 128 | ?,<128>? | 6.5MB | 52ms | 27,839ms | 535x Slower |
| Newlines+Spaces 128 | ?\n,\n<128>? | 8.5MB | 62ms | 44,521ms | 712x Slower 🔥 |

## Performance Improvement Summary

Through SQL format optimization:

| Metric | Before Optimization | After Optimization | Improvement |
|--------|---------------------|--------------------|-------------|
| SQL Length | 2.1MB | 100KB | **Reduced by 95%** |
| Server-side Performance | 9,128ms | 645ms | **14x Improvement** |
| Performance Difference Ratio | 194x | 18x | **10x Improvement** |

**Final Recommendation**: Using client-side prepared statements (35ms) is the best solution!

## Conclusion

1. **SQL Length is the Achilles' Heel of Server-side Prepared Statements**
   - Length increase → Performance deteriorates linearly
   - From 100KB (645ms) to 8.5MB (44,521ms), performance drops **69 times**

2. **SQL Format Optimization is Crucial**
   - Removing newlines and extra spaces can improve performance by **14 times**
   - Use `--spaces 0` to get the most compact format

3. **Client-side Prepared Statements are Almost Unaffected**
   - 100KB SQL: 35ms
   - 8.5MB SQL: 62ms
   - Performance is stable and reliable

4. **Strong Recommendation for Production**
   - ✅ Use `useServerPrepStmts=false`
   - ✅ Use the most compact SQL format (`--spaces 0`)
   - ✅ Avoid large parameter IN queries, or use batch/temporary table solutions

5. **Performance Difference**
   - Optimal config (35ms) vs Worst config (44,521ms) = **1,272x Difference**!
   - This is not an optimization issue, but an architectural choice issue

## Test Code Repository

- GitHub: https://github.com/plantegg/MySQLPrepared
- Contains complete test code, scripts, and documentation
- Supports `--spaces` parameter for flexible testing of different SQL formats
