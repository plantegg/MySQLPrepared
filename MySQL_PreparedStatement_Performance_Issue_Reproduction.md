# MySQL PreparedStatement 性能问题重现文档

## 问题描述

在生产环境中发现，当使用 `useServerPrepStmts=true` 参数时，包含大量参数的 PreparedStatement 查询性能极差。通过系统测试发现，**SQL 格式和长度对性能有巨大影响**。

## 环境信息

- **MySQL版本**: 5.7.29
- **JDBC驱动**: mysql-connector-j-8.0.33
- **测试场景**: 5万个大整数参数的 IN 查询
- **参数格式**: 15位大整数（如 176302640511975）
- **重现代码**: https://github.com/plantegg/MySQLPrepared

## 核心发现

### 🔥 SQL 格式对性能的巨大影响

我们发现 **SQL 字符串的格式和长度** 是影响服务器端预编译性能的关键因素：

| SQL格式 | SQL长度 | false平均时间 | true平均时间 | 性能差异 |
|---------|---------|---------------|--------------|---------|
| **紧凑格式** (?,?,?) | **100KB** | **35ms** | **645ms** | **慢18倍** ⭐ 最优 |
| 带换行格式 | 2.1MB | 47ms | 9,128ms | 慢194倍 |
| 带换行+空格 (128) | 6.5MB | 52ms | 27,839ms | 慢535倍 |
| 带换行+大量空格 (128) | 8.5MB | 62ms | 44,521ms | 慢712倍 🔥 最差 |

**关键结论**: 
- ✅ **最优化的紧凑格式** 可以将服务器端性能提升 **14倍**（9,128ms → 645ms）
- ⚠️ 即使优化后，客户端预编译（35ms）仍比服务器端（645ms）快 **18倍**

## 重现步骤

### 1. 环境准备

创建测试表：

```bash
mysql -h your-host -P your-port -u your-user -p your-database < create_table.sql
```

`create_table.sql` 内容：

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

### 2. 运行测试

#### 使用脚本（推荐）

```bash
# 最优配置（紧凑格式）
./run_test.sh --host localhost --port 3306 --database test \
  --user root --password mypass --spaces 0

# 测试不同空格配置的影响
./run_test.sh --host localhost --port 3306 --database test \
  --user root --password mypass --spaces 128

# 查看帮助
./run_test.sh --help
```

#### 使用 Maven

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

### 3. 参数说明

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--spaces` | 128 | 参数之间的空格数量，0=最紧凑格式 |
| `--rounds` | 2 | 测试轮次 |

## 详细测试结果

### 测试 1: 紧凑格式 (spaces=0) ⭐ 推荐

**SQL 示例**: `WHERE id IN (?,?,?,?,...)`

```
配置: useServerPrepStmts=false
SQL长度: 100,151 字符 (~100KB)
平均执行时间: 35.0ms
Com_stmt_prepare: 0

配置: useServerPrepStmts=true  
SQL长度: 100,151 字符 (~100KB)
平均执行时间: 645.5ms
Com_stmt_prepare: 1

性能差异: 慢 18 倍
```

### 测试 2: 带换行格式 (旧版本)

**SQL 示例**: 
```sql
WHERE id IN (?
                  ,
                    ?
                  ,
                    ?
```

```
配置: useServerPrepStmts=false
SQL长度: 2,100,111 字符 (~2.1MB)
平均执行时间: 47.0ms
Com_stmt_prepare: 0

配置: useServerPrepStmts=true
SQL长度: 2,100,111 字符 (~2.1MB)
平均执行时间: 9,128.5ms
Com_stmt_prepare: 1

性能差异: 慢 194 倍
```

### 测试 3: 带空格格式 (spaces=128)

**SQL 示例**: `WHERE id IN (?,<128 spaces>?,<128 spaces>?,...)`

```
配置: useServerPrepStmts=false
SQL长度: 6,500,023 字符 (~6.5MB)
平均执行时间: 52.0ms
Com_stmt_prepare: 0

配置: useServerPrepStmts=true
SQL长度: 6,500,023 字符 (~6.5MB)
平均执行时间: 27,839.5ms
Com_stmt_prepare: 1

性能差异: 慢 535 倍
```

### 测试 4: 带换行+大量空格 (极端情况)

```
配置: useServerPrepStmts=false
SQL长度: 8,499,983 字符 (~8.5MB)
平均执行时间: 62.5ms
Com_stmt_prepare: 0

配置: useServerPrepStmts=true
SQL长度: 8,499,983 字符 (~8.5MB)
平均执行时间: 44,521.5ms
Com_stmt_prepare: 1

性能差异: 慢 712 倍
```

## 性能分析

### 1. SQL 长度与性能的线性关系

服务器端预编译性能随 SQL 长度线性恶化：

```
100KB  SQL → 645ms    (基准)
2.1MB  SQL → 9,128ms  (14倍恶化)
6.5MB  SQL → 27,839ms (43倍恶化)
8.5MB  SQL → 44,521ms (69倍恶化)
```

### 2. 客户端预编译的稳定性

客户端预编译几乎不受 SQL 长度影响：

```
100KB  SQL → 35-47ms
8.5MB  SQL → 62ms
变化幅度: 仅 77%
```

### 3. 问题根因

根据 `pstack` 分析，服务器端预编译在处理大 SQL 时：

1. **大量内存重分配**: 
   - 50,000 次参数替换操作
   - 每次替换需要在大 SQL 字符串中定位和替换
   - `my_realloc` 和 `memmove` 频繁调用

2. **字符串操作复杂度**: 
   - O(SQL长度) × 参数数量 = 极高时间复杂度
   - 单线程 100% CPU 占用

3. **内存碎片化**:
   - 频繁的大块内存分配和释放
   - 进一步降低性能


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

### 监控数据

```
# top 监控
PID     USER   %CPU  TIME+     COMMAND
2554029 mysql  99.3  4:40.64   mysqld  // 单线程 100%

# show processlist 观察
Id  User  Command  Time  State     Info
382 test  Execute  8     starting  NULL  // SQL 还在组装中
```

## 解决方案

### ✅ 方案 1: 使用客户端预编译 + 紧凑格式（强烈推荐）

```java
// JDBC 连接串
String url = "jdbc:mysql://host:port/database?useServerPrepStmts=false";

// 运行测试
./run_test.sh --host localhost --port 3306 --database test \
  --user root --password mypass --spaces 0
```

**优点**:
- ✅ 性能最优：仅需 35ms
- ✅ 不受 SQL 长度影响
- ✅ 不受参数数量影响
- ✅ 稳定可靠

**缺点**:
- ⚠️ 无法享受服务器端查询计划缓存（但对 IN 查询意义不大）

### 🔄 方案 2: 优化 SQL 格式（如果必须使用服务器端预编译）

如果由于某些原因必须使用 `useServerPrepStmts=true`，则务必优化 SQL 格式：

```java
// 使用最紧凑格式: ?,?,?,?
// 避免: ?\n  ,\n  ?

String url = "jdbc:mysql://host:port/database?useServerPrepStmts=true";
// 运行时使用 --spaces 0
```

**性能**: 645ms（相比未优化的 9,128ms 提升 14 倍）

### 🔧 方案 3: 分批查询

```java
// 将 50,000 个参数拆分为 50 批，每批 1,000 个
int batchSize = 1000;
for (int i = 0; i < ids.size(); i += batchSize) {
    List<Long> batch = ids.subList(i, Math.min(i + batchSize, ids.size()));
    // 执行查询
}
```

### 🗃️ 方案 4: 临时表方案

```sql
CREATE TEMPORARY TABLE temp_ids (id BIGINT);
INSERT INTO temp_ids VALUES (?), (?), ...;
SELECT * FROM large_table WHERE id IN (SELECT id FROM temp_ids);
DROP TEMPORARY TABLE temp_ids;
```

## 最佳实践

### ✅ 推荐配置

| 场景 | useServerPrepStmts | spaces | 预期性能 |
|------|-------------------|--------|---------|
| **生产环境** | false | 0 | 35ms ⭐ 最优 |
| 标准测试 | false | 0 | 35-50ms |
| 必须服务器端预编译 | true | 0 | 645ms |

### ❌ 避免配置

| 场景 | useServerPrepStmts | SQL格式 | 性能 |
|------|-------------------|---------|------|
| ❌ 带格式化 | true | 带换行/缩进 | 9,128ms 慢194倍 |
| ❌ 大量空格 | true | spaces > 0 | 27,839ms 慢535倍 |
| ❌ 极端情况 | true | 大量换行+空格 | 44,521ms 慢712倍 |

### 🎯 实施建议

1. **开发阶段**:
   - 设置 `useServerPrepStmts=false`
   - 使用 `--spaces 0` 测试

2. **测试阶段**:
   - 对比不同配置的性能
   - 使用 `SHOW PROCESSLIST` 监控

3. **生产环境**:
   - 强制使用客户端预编译
   - 避免大参数量 IN 查询
   - 如必须使用，考虑分批或临时表方案

## 完整对比表

| 配置 | SQL格式 | SQL长度 | false平均 | true平均 | 性能差异 |
|------|---------|---------|----------|----------|---------|
| **最优** | ?,?,? | 100KB | 35ms | 645ms | 慢18倍 ⭐ |
| 带换行 | ?\n,\n? | 2.1MB | 47ms | 9,128ms | 慢194倍 |
| +空格128 | ?,<128>? | 6.5MB | 52ms | 27,839ms | 慢535倍 |
| 带换行+空格128 | ?\n,\n<128>? | 8.5MB | 62ms | 44,521ms | 慢712倍 🔥 |

## 性能改善总结

通过 SQL 格式优化：

| 指标 | 优化前 | 优化后 | 改善幅度 |
|------|--------|--------|---------|
| SQL 长度 | 2.1MB | 100KB | **缩小 95%** |
| 服务器端性能 | 9,128ms | 645ms | **提升 14 倍** |
| 性能差异倍数 | 194倍 | 18倍 | **改善 10 倍** |

**但最终建议**: 使用客户端预编译（35ms）才是最佳方案！

## 结论

1. **SQL 长度是服务器端预编译的致命弱点**
   - 长度增加 → 性能线性恶化
   - 从 100KB（645ms）到 8.5MB（44,521ms），性能下降 **69 倍**

2. **SQL 格式优化很重要**
   - 移除换行和多余空格可提升性能 **14 倍**
   - 使用 `--spaces 0` 获得最紧凑格式

3. **客户端预编译几乎不受影响**
   - 100KB SQL: 35ms
   - 8.5MB SQL: 62ms  
   - 性能稳定可靠

4. **生产环境强烈建议**
   - ✅ 使用 `useServerPrepStmts=false`
   - ✅ 使用最紧凑的 SQL 格式（`--spaces 0`）
   - ✅ 避免大参数量 IN 查询，或使用分批/临时表方案

5. **性能差异**
   - 最优配置（35ms）vs 最差配置（44,521ms）= **1,272 倍差异**！
   - 这不是优化问题，而是架构选择问题

## 测试代码仓库

- GitHub: https://github.com/plantegg/MySQLPrepared
- 包含完整的测试代码、脚本和文档
- 支持 `--spaces` 参数灵活测试不同 SQL 格式
