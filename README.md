# MySQL PreparedStatement性能问题重现项目

## 项目结构
```
prepared/
├── README.md                                           # 项目说明
├── MySQL_PreparedStatement_Performance_Issue_Reproduction.md  # 详细重现文档
├── pom.xml                                            # Maven配置
├── run_test.sh                                        # 快速执行脚本
└── src/main/java/com/test/
    └── PreparedStatementPerformanceTest.java         # 主测试类
```

## 快速开始

### 方法1: 使用脚本执行
```bash
cd prepared
./run_test.sh <host> <port> <database> <username> <password>

# 示例
./run_test.sh localhost 3306 test root mypassword
```

### 方法2: 使用Maven执行
```bash
cd prepared
mvn compile exec:java \
    -Dexec.mainClass="com.test.PreparedStatementPerformanceTest" \
    -Ddb.host=localhost \
    -Ddb.port=3306 \
    -Ddb.name=test \
    -Ddb.user=root \
    -Ddb.password=mypassword
```

### 方法3: 使用环境变量
```bash
export DB_HOST=localhost
export DB_PORT=3306
export DB_NAME=test
export DB_USER=root
export DB_PASSWORD=mypassword

cd prepared
mvn compile exec:java -Dexec.mainClass="com.test.PreparedStatementPerformanceTest"
```

## 测试结果预期

- **useServerPrepStmts=false**: ~45ms
- **useServerPrepStmts=true**: ~9,200ms
- **性能差异**: 慢200倍以上

## 环境要求

- Java 8+
- Maven 3.6+
- MySQL 5.7+
- 需要一个包含`large_table`表的数据库（可以是空表）

## 注意事项

1. 测试过程中可执行`SHOW PROCESSLIST`观察进程状态
2. 确保MySQL服务正常运行且连接参数正确
3. 建议在测试环境中运行，避免影响生产数据

## 问题重现

此项目完美重现了生产环境中`useServerPrepStmts=true`导致的严重性能问题，验证了使用`useServerPrepStmts=false`的必要性。

## 安全说明

本项目不包含任何硬编码的敏感信息，所有数据库连接参数都通过命令行参数或环境变量传递。
