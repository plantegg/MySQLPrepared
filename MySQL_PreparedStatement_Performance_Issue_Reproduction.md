# MySQL PreparedStatement性能问题重现文档

## 问题描述

在生产环境中发现，当使用`useServerPrepStmts=true`参数时，包含大量参数的PreparedStatement查询性能极差，比`useServerPrepStmts=false`慢100倍以上。

## 环境信息

- **MySQL版本**: 5.7.29
- **JDBC驱动**: mysql-connector-j-8.0.33
- **测试场景**: 5万个大整数参数的IN查询
- **参数格式**: 15位大整数（如176302640511975）

## 性能测试结果

| 配置 | 平均执行时间 | 性能差异 | Com_stmt_prepare |
|------|-------------|----------|------------------|
| useServerPrepStmts=false | 44.5ms | 基准 | 0 |
| useServerPrepStmts=true | 9,244.5ms | 慢207倍 | 1 |

## 问题根因

1. **服务器端参数处理开销**: MySQL在`starting`状态需要处理大量参数替换
2. **内存频繁重分配**: 大整数参数导致字符串频繁扩容和内存拷贝
3. **SQL解析复杂度**: 多行格式的SQL增加了解析开销

## 重现步骤

### 1. 环境准备

```bash
# 创建测试表（可选，测试中使用空表）
CREATE TABLE large_table (
    id BIGINT PRIMARY KEY,
    col1 VARCHAR(50), col2 VARCHAR(50), ..., col20 VARCHAR(50)
);
```

### 2. 运行测试

#### 方法1: 使用脚本
```bash
./run_test.sh <host> <port> <database> <username> <password>

# 示例
./run_test.sh localhost 3306 test root mypassword
```

#### 方法2: 使用Maven
```bash
mvn compile exec:java \
    -Dexec.mainClass="com.test.PreparedStatementPerformanceTest" \
    -Ddb.host=localhost \
    -Ddb.port=3306 \
    -Ddb.name=test \
    -Ddb.user=root \
    -Ddb.password=mypassword
```

#### 方法3: 使用环境变量
```bash
export DB_HOST=localhost
export DB_PORT=3306
export DB_NAME=test
export DB_USER=root
export DB_PASSWORD=mypassword

mvn compile exec:java -Dexec.mainClass="com.test.PreparedStatementPerformanceTest"
```

### 3. 观察MySQL进程状态

在测试运行期间，执行以下命令观察：

```sql
SHOW PROCESSLIST;
```

可以看到`useServerPrepStmts=true`时，查询在`starting`状态停留8-9秒。

## 测试SQL结构

```sql
SELECT id,col1,col2,col3,col4,col5,col6,col7,col8,col9,col10,col11,col12,col13,col14,col15,col16,col17,col18,col19,col20 
FROM large_table 
WHERE id IN (176302640511975
                  ,
                    176302638793645
                  ,
                    176302442631589
                  ,
                    ... (50,000个大整数参数)
                  ,
                    176302242704618)
```

## 解决方案

### 推荐方案
使用`useServerPrepStmts=false`参数：

```java
String url = "jdbc:mysql://host:port/database?useServerPrepStmts=false";
```

### 替代方案
1. **分批查询**: 将大IN查询拆分为多个小查询
2. **临时表方案**: 将参数插入临时表，使用JOIN替代IN
3. **调整MySQL参数**: 增加`max_allowed_packet`等参数

## 性能对比总结

| 参数数量 | false平均时间 | true平均时间 | 性能差异 |
|----------|---------------|--------------|----------|
| 1万 | 7.3ms | 22.6ms | 慢3倍 |
| 2万 | 14.8ms | 77.7ms | 慢5倍 |
| 5万 | 44.5ms | 9,244.5ms | 慢207倍 |
| 10万 | 68.2ms | 65.0ms | 相近 |

## 结论

1. **临界点**: 约在5-10万参数之间存在性能交叉点
2. **生产建议**: 对于大参数量查询，强烈推荐使用`useServerPrepStmts=false`
3. **架构优化**: 避免设计需要超大参数量的查询

## 相关堆栈信息

生产环境观察到的堆栈：
```
#0  __memcpy_ssse3_back () from /lib64/libc.so.6
#1  my_realloc (size=2492024, flags=<optimized out>) at mysys/my_malloc.c:112
#2  String::mem_realloc (alloc_length=2492018) at sql-common/sql_string.cc:128
#3  String::replace (offset=1149438, arg_length=1, to_length=15) at sql-common/sql_string.cc:804
#4  Prepared_statement::insert_params (params_length=531358) at sql/sql_prepare.cc:924
```

这证实了问题出现在服务器端的参数处理阶段。
