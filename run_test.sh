#!/bin/bash

# MySQL PreparedStatement性能测试执行脚本

echo "=== MySQL PreparedStatement性能问题重现测试 ==="
echo "开始时间: $(date)"
echo

# 检查参数
if [ $# -ne 5 ]; then
    echo "用法: $0 <host> <port> <database> <username> <password>"
    echo "示例: $0 localhost 3306 test root mypassword"
    exit 1
fi

DB_HOST=$1
DB_PORT=$2
DB_NAME=$3
DB_USER=$4
DB_PASSWORD=$5

# 检查Java环境
if ! command -v java &> /dev/null; then
    echo "错误: 未找到Java环境"
    exit 1
fi

if ! command -v mvn &> /dev/null; then
    echo "错误: 未找到Maven"
    exit 1
fi

echo "数据库连接信息: $DB_HOST:$DB_PORT/$DB_NAME"
echo "用户名: $DB_USER"
echo

echo "编译项目..."
mvn compile -q

if [ $? -ne 0 ]; then
    echo "编译失败"
    exit 1
fi

echo "开始执行性能测试..."
echo "注意: 测试过程中可以在另一个终端执行 'SHOW PROCESSLIST;' 观察MySQL进程状态"
echo

# 执行测试，传递数据库连接参数
timeout 600s mvn exec:java \
    -Dexec.mainClass="com.test.PreparedStatementPerformanceTest" \
    -Ddb.host="$DB_HOST" \
    -Ddb.port="$DB_PORT" \
    -Ddb.name="$DB_NAME" \
    -Ddb.user="$DB_USER" \
    -Ddb.password="$DB_PASSWORD" \
    -q

echo
echo "测试完成时间: $(date)"
echo "=== 测试结束 ==="
