#!/bin/bash

# MySQL PreparedStatement性能测试执行脚本

# 显示帮助信息
show_help() {
    cat << EOF
MySQL PreparedStatement 性能测试脚本

用法: $0 [选项]

必需参数:
  --host HOST           MySQL 服务器地址
  --port PORT           MySQL 服务器端口
  --database DATABASE   数据库名称
  --user USER           数据库用户名
  --password PASSWORD   数据库密码

可选参数:
  --rounds ROUNDS       SQL 执行的重复次数（默认: 2）
  --spaces SPACES       每个参数之间的空格数量（默认: 128）
  --help                显示此帮助信息

示例:
  # 使用命名参数
  $0 --host localhost --port 3306 --database test --user root --password mypass

  # 使用命名参数并指定执行10次
  $0 --host localhost --port 3306 --database test --user root --password mypass --rounds 10

  # 自定义空格数量（0个空格，最紧凑格式）
  $0 --host localhost --port 3306 --database test --user root --password mypass --spaces 0

  # 也支持旧的位置参数（为了向后兼容）
  $0 localhost 3306 test root mypass

说明:
  此脚本会自动执行以下步骤：
  1. 检查环境依赖 (Java, Maven, MySQL客户端)
  2. 创建测试表 large_table (如果 create_table.sql 存在)
  3. 编译 Java 项目
  4. 运行性能测试并对比 useServerPrepStmts=true/false 的性能差异

EOF
    exit 0
}

# 初始化变量
DB_HOST=""
DB_PORT=""
DB_NAME=""
DB_USER=""
DB_PASSWORD=""
TEST_ROUNDS="2"  # 默认执行2次
PARAM_SPACES="128"  # 默认每个参数之间128个空格

# 检查是否显示帮助
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    show_help
fi

# 解析命名参数
if [[ "$1" == --* ]]; then
    while [[ $# -gt 0 ]]; do
        case $1 in
            --host)
                DB_HOST="$2"
                shift 2
                ;;
            --port)
                DB_PORT="$2"
                shift 2
                ;;
            --database)
                DB_NAME="$2"
                shift 2
                ;;
            --user)
                DB_USER="$2"
                shift 2
                ;;
            --password)
                DB_PASSWORD="$2"
                shift 2
                ;;
            --rounds)
                TEST_ROUNDS="$2"
                shift 2
                ;;
            --spaces)
                PARAM_SPACES="$2"
                shift 2
                ;;
            *)
                echo "错误: 未知参数 '$1'"
                echo "使用 --help 查看帮助信息"
                exit 1
                ;;
        esac
    done
else
    # 支持旧的位置参数（向后兼容）
    if [ $# -ne 5 ]; then
        echo "错误: 缺少必需参数"
        echo
        echo "用法: $0 <host> <port> <database> <username> <password>"
        echo "或使用: $0 --help 查看详细帮助"
        exit 1
    fi
    
    DB_HOST=$1
    DB_PORT=$2
    DB_NAME=$3
    DB_USER=$4
    DB_PASSWORD=$5
fi

# 验证所有参数都已提供
if [ -z "$DB_HOST" ] || [ -z "$DB_PORT" ] || [ -z "$DB_NAME" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ]; then
    echo "错误: 所有参数都是必需的"
    echo "使用 --help 查看帮助信息"
    exit 1
fi

echo "=== MySQL PreparedStatement性能问题重现测试 ==="
echo "开始时间: $(date)"
echo

# 检查Java环境
if ! command -v java &> /dev/null; then
    echo "错误: 未找到Java环境"
    exit 1
fi

if ! command -v mvn &> /dev/null; then
    echo "错误: 未找到Maven"
    exit 1
fi

# 检查MySQL客户端
if ! command -v mysql &> /dev/null; then
    echo "错误: 未找到MySQL客户端"
    exit 1
fi

echo "数据库连接信息: $DB_HOST:$DB_PORT/$DB_NAME"
echo "用户名: $DB_USER"
echo

# 创建测试表
echo "创建测试表 large_table..."
if [ -f "create_table.sql" ]; then
    mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" < create_table.sql 2>&1 | grep -v "Using a password"
    
    if [ $? -eq 0 ]; then
        echo "✓ 测试表创建成功"
    else
        echo "✗ 测试表创建失败"
        exit 1
    fi
else
    echo "警告: 未找到 create_table.sql，跳过建表步骤"
    echo "      如果表不存在，测试可能会失败"
fi
echo

echo "编译项目..."
mvn compile -q

if [ $? -ne 0 ]; then
    echo "✗ 编译失败"
    exit 1
fi
echo "✓ 编译成功"

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
    -Dtest.rounds="$TEST_ROUNDS" \
    -Dparam.spaces="$PARAM_SPACES" \
    -Ddb.password="$DB_PASSWORD" \
    -q

echo
echo "测试完成时间: $(date)"
echo "=== 测试结束 ==="
