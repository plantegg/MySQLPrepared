# MySQL PreparedStatement 性能问题重现项目

## 项目简介

本项目用于重现 MySQL 在使用 `useServerPrepStmts=true` 时处理大量参数（5万个）的 PreparedStatement 查询时的严重性能问题。测试结果显示服务器端预编译比客户端预编译慢 **190-207倍**。

## 项目结构

```
prepared/
├── README.md                                           # 项目说明
├── MySQL_PreparedStatement_Performance_Issue_Reproduction.md  # 详细重现文档
├── pom.xml                                            # Maven配置
├── create_table.sql                                   # 数据库表结构
├── run_test.sh                                        # 一键测试脚本
└── src/main/java/com/test/
    └── PreparedStatementPerformanceTest.java         # 主测试类
```

## 前置条件

在运行测试之前，请确保已准备好以下条件：

### 1. MySQL 数据库

需要一个可访问的 MySQL 数据库实例，并准备以下连接参数：

| 参数 | 说明 | 示例 |
|------|------|------|
| **主机地址** | MySQL 服务器的 IP 地址或域名 | `localhost` 或 `your-mysql-host` |
| **端口** | MySQL 服务器端口 | `3306` |
| **数据库名** | 用于测试的数据库名称（可以是已存在的数据库） | `test` 或 `mysql` |
| **用户名** | 有权限访问该数据库的用户 | `root` 或 `testuser` |
| **密码** | 数据库用户密码 | `mypassword` |

> **注意**: 
> - 脚本会自动创建 `large_table` 表，如果表已存在会先删除
> - 测试数据为空表，不会影响现有数据
> - 建议在**测试环境**中运行，避免影响生产数据

### 2. 环境依赖

确保系统已安装以下软件：

- **Java**: 8 或更高版本
- **Maven**: 3.6 或更高版本
- **MySQL 客户端**: 用于自动建表（仅使用 `run_test.sh` 时需要）

### 3. 网络连接

确保运行测试的机器能够访问 MySQL 数据库服务器。

## 快速开始

### 查看帮助信息

```bash
./run_test.sh --help
```

### 方法1: 使用脚本执行（推荐）✨

脚本会自动完成以下操作：
1. ✅ 检查环境依赖（Java、Maven、MySQL客户端）
2. ✅ 自动创建测试表 `large_table`
3. ✅ 编译项目
4. ✅ 运行性能测试

#### 使用命名参数（推荐）

```bash
# 基本用法（默认执行2次）
./run_test.sh --host localhost --port 3306 --database test --user root --password mypass

# 自定义执行次数（执行10次以获得更稳定的平均值）
./run_test.sh --host localhost --port 3306 --database test --user root --password mypass --rounds 10

# 快速测试（只执行1次）
./run_test.sh --host localhost --port 3306 --database test --user root --password mypass --rounds 1
```

#### 使用位置参数（向后兼容）

```bash
./run_test.sh localhost 3306 test root mypassword
```

### 方法2: 使用 Maven 执行

```bash
# 先手动创建表
mysql -h localhost -P 3306 -u root -p test < create_table.sql

# 编译并运行测试（默认2次）
mvn compile exec:java \
    -Dexec.mainClass="com.test.PreparedStatementPerformanceTest" \
    -Ddb.host=localhost \
    -Ddb.port=3306 \
    -Ddb.name=test \
    -Ddb.user=root \
    -Ddb.password=mypassword

# 自定义执行次数（10次）
mvn compile exec:java \
    -Dexec.mainClass="com.test.PreparedStatementPerformanceTest" \
    -Ddb.host=localhost \
    -Ddb.port=3306 \
    -Ddb.name=test \
    -Ddb.user=root \
    -Ddb.password=mypassword \
    -Dtest.rounds=10
```

### 方法3: 使用环境变量

```bash
export DB_HOST=localhost
export DB_PORT=3306
export DB_NAME=test
export DB_USER=root
export DB_PASSWORD=mypassword
export TEST_ROUNDS=5  # 可选，默认为2

# 先手动创建表
mysql -h $DB_HOST -P $DB_PORT -u $DB_USER -p$DB_PASSWORD $DB_NAME < create_table.sql

# 运行测试
mvn compile exec:java -Dexec.mainClass="com.test.PreparedStatementPerformanceTest"
```

## 命令行参数说明

### run_test.sh 支持的参数

| 参数 | 必需/可选 | 说明 | 默认值 |
|------|----------|------|--------|
| `--host` | 必需 | MySQL 服务器地址 | - |
| `--port` | 必需 | MySQL 服务器端口 | - |
| `--database` | 必需 | 数据库名称 | - |
| `--user` | 必需 | 数据库用户名 | - |
| `--password` | 必需 | 数据库密码 | - |
| `--rounds` | 可选 | SQL 执行的重复次数 | 2 |
| `--help` | 可选 | 显示帮助信息 | - |

### Java 程序支持的系统属性

| 系统属性 | 环境变量 | 说明 | 默认值 |
|---------|---------|------|--------|
| `db.host` | `DB_HOST` | MySQL 服务器地址 | - |
| `db.port` | `DB_PORT` | MySQL 服务器端口 | - |
| `db.name` | `DB_NAME` | 数据库名称 | - |
| `db.user` | `DB_USER` | 数据库用户名 | - |
| `db.password` | `DB_PASSWORD` | 数据库密码 | - |
| `test.rounds` | `TEST_ROUNDS` | SQL 执行的重复次数 | 2 |

## 测试结果预期

### 典型性能数据

| 配置 | 平均执行时间 | 性能差异 | Com_stmt_prepare |
|------|-------------|----------|------------------|
| `useServerPrepStmts=false` | ~48ms | 基准 | 0 |
| `useServerPrepStmts=true` | ~9,158ms | **慢190倍** | 1 |

### 测试输出示例

```
=== useServerPrepStmts=false 测试结果 ===
总执行时间: 96ms
平均执行时间: 48.0ms
返回记录数: 0
Com_stmt_prepare: 0 → 0

=== useServerPrepStmts=true 测试结果 ===
总执行时间: 18316ms
平均执行时间: 9158.0ms
返回记录数: 0
Com_stmt_prepare: 0 → 1
```

## 环境要求

- **Java**: 8 或更高版本
- **Maven**: 3.6 或更高版本
- **MySQL**: 5.7 或更高版本
- **MySQL客户端**: 用于自动建表（使用 `run_test.sh` 时需要）
- **操作系统**: Linux、macOS 或 Windows（需要 bash）

## 数据库表结构

测试需要 `large_table` 表，包含以下字段：
- `id` (int, PRIMARY KEY) - 用于 IN 查询
- `col1` ~ `col20` (varchar) - 20个辅助列用于模拟多列查询

如果使用 `run_test.sh`，表会自动创建。如果手动运行，请先执行：

```bash
mysql -h <host> -P <port> -u <user> -p <database> < create_table.sql
```

## 测试参数配置

### 默认测试配置

- **参数数量**: 50,000 个大整数
- **SQL格式**: 多行格式（包含换行符，约 2.1MB）
- **测试轮次**: 2 次（可通过 `--rounds` 调整）
- **参数类型**: 15位大整数（如 176302640511975）

### --rounds 参数使用建议

| 场景 | 推荐值 | 说明 |
|------|-------|------|
| 快速验证环境 | `--rounds 1` | 验证配置是否正确 |
| 标准测试 | `--rounds 2` | 默认值，平衡速度和准确性 |
| 精确测试 | `--rounds 10` | 获得更稳定的平均性能数据 |
| 压力测试 | `--rounds 100` | 观察长时间运行的性能表现 |

## 监控和观察

### 观察 MySQL 进程状态

在测试运行期间，可以在另一个终端执行：

```sql
SHOW PROCESSLIST;
```

当 `useServerPrepStmts=true` 时，可以看到查询在 `starting` 状态停留 8-9 秒。

### 性能分析

测试过程中 MySQL 会执行大量的：
- 字符串替换操作（`String::replace`）
- 内存重分配（`my_realloc`）
- 内存拷贝（`memmove`）

这些操作在处理 2.1MB 的 SQL 字符串和 50,000 个参数时会导致严重的性能问题。

## 注意事项

1. ⚠️ **测试环境**: 建议在测试环境中运行，避免影响生产数据
2. 📊 **观察进程**: 测试过程中可执行 `SHOW PROCESSLIST` 观察进程状态
3. ✅ **空表测试**: 测试可以在空表上运行，不需要实际数据
4. 🔒 **安全性**: 命令行中的密码会有警告，生产环境建议使用配置文件或环境变量
5. ⏱️ **超时设置**: 脚本设置了 600 秒超时，防止测试无限挂起

## 问题重现和解决方案

### 问题原因

1. **服务器端参数处理开销**: MySQL 在 `starting` 状态需要处理大量参数替换
2. **内存频繁重分配**: 大整数参数导致字符串频繁扩容和内存拷贝
3. **SQL 解析复杂度**: 多行格式的 SQL 增加了解析开销

### 推荐解决方案

#### ✅ 方案1: 使用客户端预编译（推荐）

```java
String url = "jdbc:mysql://host:port/database?useServerPrepStmts=false";
```

**优点**: 性能优异，即使 5 万参数也能在 50ms 内完成

#### 🔄 方案2: 分批查询

将大 IN 查询拆分为多个小查询（如每批 1000 个参数）

#### 📋 方案3: 临时表方案

将参数插入临时表，使用 JOIN 替代 IN 查询

## 项目验证

此项目成功重现了生产环境中 `useServerPrepStmts=true` 导致的严重性能问题，验证了在处理大参数量查询时使用 `useServerPrepStmts=false` 的必要性。

## 详细文档

更多技术细节、性能分析和堆栈跟踪，请参考：
[MySQL_PreparedStatement_Performance_Issue_Reproduction.md](./MySQL_PreparedStatement_Performance_Issue_Reproduction.md)

## 安全说明

本项目不包含任何硬编码的敏感信息，所有数据库连接参数都通过以下方式安全传递：
- 命令行参数
- 系统属性
- 环境变量

## 贡献

欢迎提交 Issue 和 Pull Request！

## License

MIT License
