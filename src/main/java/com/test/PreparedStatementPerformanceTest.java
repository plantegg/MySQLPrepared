package com.test;

import java.sql.*;
import java.util.*;

/**
 * MySQL PreparedStatement性能测试
 * 重现生产环境中useServerPrepStmts=true导致的性能问题
 * 
 * 测试场景：5万个大整数参数的IN查询
 * 预期结果：useServerPrepStmts=false比true快200倍以上
 */
public class PreparedStatementPerformanceTest {
    
    // 数据库连接配置 - 从系统属性或环境变量获取
    private static final String DB_HOST = System.getProperty("db.host", System.getenv("DB_HOST"));
    private static final String DB_PORT = System.getProperty("db.port", System.getenv("DB_PORT"));
    private static final String DB_NAME = System.getProperty("db.name", System.getenv("DB_NAME"));
    private static final String DB_USER = System.getProperty("db.user", System.getenv("DB_USER"));
    private static final String DB_PASSWORD = System.getProperty("db.password", System.getenv("DB_PASSWORD"));
    
    // 测试参数
    private static final int PARAM_COUNT = 50000;  // 5万个参数
    private static final int TEST_ROUNDS = 2;      // 执行2次
    
    public static void main(String[] args) throws Exception {
        // 检查必要的连接参数
        if (DB_HOST == null || DB_PORT == null || DB_NAME == null || DB_USER == null || DB_PASSWORD == null) {
            System.err.println("错误: 缺少数据库连接参数");
            System.err.println("请通过系统属性或环境变量提供以下参数:");
            System.err.println("  db.host 或 DB_HOST");
            System.err.println("  db.port 或 DB_PORT");
            System.err.println("  db.name 或 DB_NAME");
            System.err.println("  db.user 或 DB_USER");
            System.err.println("  db.password 或 DB_PASSWORD");
            System.err.println();
            System.err.println("示例运行命令:");
            System.err.println("java -Ddb.host=localhost -Ddb.port=3306 -Ddb.name=test -Ddb.user=root -Ddb.password=password PreparedStatementPerformanceTest");
            System.exit(1);
        }
        
        System.out.println("=== MySQL PreparedStatement性能对比测试 ===");
        System.out.println("连接信息: " + DB_HOST + ":" + DB_PORT + "/" + DB_NAME);
        System.out.println("参数数量: " + PARAM_COUNT);
        System.out.println("测试轮次: " + TEST_ROUNDS);
        System.out.println();
        
        // 测试 useServerPrepStmts=false
        testPreparedStatement(false);
        
        // 测试 useServerPrepStmts=true  
        testPreparedStatement(true);
        
        System.out.println("=== 测试完成 ===");
    }
    
    static void testPreparedStatement(boolean useServerPrepStmts) throws Exception {
        String url = String.format("jdbc:mysql://%s:%s/%s?useServerPrepStmts=%s", 
                                   DB_HOST, DB_PORT, DB_NAME, useServerPrepStmts);
        
        try (Connection conn = DriverManager.getConnection(url, DB_USER, DB_PASSWORD)) {
            // 清空状态
            conn.createStatement().execute("FLUSH STATUS");
            
            // 获取测试前状态
            int beforePrepare = getStatusValue(conn, "Com_stmt_prepare");
            
            // 生成5万个大整数随机ID
            List<Long> ids = generateLargeRandomIds(PARAM_COUNT);
            
            // 构建多行格式的IN查询SQL
            StringBuilder inClause = new StringBuilder();
            for (int i = 0; i < ids.size(); i++) {
                if (i == 0) {
                    inClause.append("?");
                } else {
                    inClause.append("\n                  ,\n                    ?");
                }
            }
            
            String sql = "SELECT id,col1,col2,col3,col4,col5,col6,col7,col8,col9,col10," +
                        "col11,col12,col13,col14,col15,col16,col17,col18,col19,col20 " +
                        "FROM large_table WHERE id IN (" + inClause + ")";
            
            System.out.println("测试配置: useServerPrepStmts=" + useServerPrepStmts);
            System.out.println("SQL长度: " + sql.length() + " 字符");
            
            // 创建PreparedStatement
            PreparedStatement ps = conn.prepareStatement(sql);
            
            // 设置参数
            for (int i = 0; i < ids.size(); i++) {
                ps.setLong(i + 1, ids.get(i));
            }
            
            // 执行测试
            long totalTime = 0;
            int totalRecords = 0;
            
            for (int test = 1; test <= TEST_ROUNDS; test++) {
                System.out.println("执行第" + test + "次查询...");
                
                long startTime = System.currentTimeMillis();
                ResultSet rs = ps.executeQuery();
                
                int count = 0;
                while (rs.next()) count++;
                long endTime = System.currentTimeMillis();
                
                rs.close();
                
                long testTime = endTime - startTime;
                totalTime += testTime;
                totalRecords = count;
                
                System.out.println("第" + test + "次: " + testTime + "ms (返回" + count + "条记录)");
            }
            
            ps.close();
            
            // 获取测试后状态
            int afterPrepare = getStatusValue(conn, "Com_stmt_prepare");
            double avgTime = totalTime / (double)TEST_ROUNDS;
            
            // 输出结果
            System.out.println("\n=== useServerPrepStmts=" + useServerPrepStmts + " 测试结果 ===");
            System.out.println("总执行时间: " + totalTime + "ms");
            System.out.println("平均执行时间: " + String.format("%.1f", avgTime) + "ms");
            System.out.println("返回记录数: " + totalRecords);
            System.out.println("Com_stmt_prepare: " + beforePrepare + " -> " + afterPrepare);
            System.out.println();
            
        } catch (Exception e) {
            System.out.println("useServerPrepStmts=" + useServerPrepStmts + " 执行失败: " + e.getMessage());
            System.out.println();
        }
    }
    
    /**
     * 生成大整数随机ID列表
     * 模拟生产环境中的大整数ID（15位数字）
     */
    static List<Long> generateLargeRandomIds(int count) {
        Set<Long> idSet = new HashSet<>();
        Random random = new Random();
        
        while (idSet.size() < count) {
            // 生成类似176302640511975的大整数
            long bigId = 100000000000000L + (long)(random.nextDouble() * 900000000000000L);
            idSet.add(bigId);
        }
        
        return new ArrayList<>(idSet);
    }
    
    /**
     * 获取MySQL状态值
     */
    static int getStatusValue(Connection conn, String statusName) throws SQLException {
        ResultSet rs = conn.createStatement().executeQuery("SHOW STATUS LIKE '" + statusName + "'");
        if (rs.next()) {
            return Integer.parseInt(rs.getString(2));
        }
        return 0;
    }
}
