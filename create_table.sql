-- MySQL PreparedStatement 性能测试所需的表结构
-- 用于重现 useServerPrepStmts=true 参数导致的性能问题

-- 如果表已存在则先删除
DROP TABLE IF EXISTS `large_table`;

-- 创建测试表
CREATE TABLE `large_table` (
  `id` int(11) NOT NULL,
  `col1` varchar(50) COLLATE utf8_unicode_ci DEFAULT NULL,
  `col2` varchar(50) COLLATE utf8_unicode_ci DEFAULT NULL,
  `col3` varchar(50) COLLATE utf8_unicode_ci DEFAULT NULL,
  `col4` varchar(50) COLLATE utf8_unicode_ci DEFAULT NULL,
  `col5` varchar(50) COLLATE utf8_unicode_ci DEFAULT NULL,
  `col6` varchar(50) COLLATE utf8_unicode_ci DEFAULT NULL,
  `col7` varchar(50) COLLATE utf8_unicode_ci DEFAULT NULL,
  `col8` varchar(50) COLLATE utf8_unicode_ci DEFAULT NULL,
  `col9` varchar(50) COLLATE utf8_unicode_ci DEFAULT NULL,
  `col10` varchar(50) COLLATE utf8_unicode_ci DEFAULT NULL,
  `col11` varchar(50) COLLATE utf8_unicode_ci DEFAULT NULL,
  `col12` varchar(50) COLLATE utf8_unicode_ci DEFAULT NULL,
  `col13` varchar(50) COLLATE utf8_unicode_ci DEFAULT NULL,
  `col14` varchar(50) COLLATE utf8_unicode_ci DEFAULT NULL,
  `col15` varchar(50) COLLATE utf8_unicode_ci DEFAULT NULL,
  `col16` varchar(50) COLLATE utf8_unicode_ci DEFAULT NULL,
  `col17` varchar(50) COLLATE utf8_unicode_ci DEFAULT NULL,
  `col18` varchar(50) COLLATE utf8_unicode_ci DEFAULT NULL,
  `col19` varchar(50) COLLATE utf8_unicode_ci DEFAULT NULL,
  `col20` varchar(50) COLLATE utf8_unicode_ci DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

-- 显示表结构
SHOW CREATE TABLE `large_table`;

-- 说明：
-- 1. 该表用于测试包含大量参数（50,000个）的 PreparedStatement IN 查询性能
-- 2. 测试中可以使用空表，无需插入数据
-- 3. id 字段用于 IN 查询，支持 15位大整数（如 176302640511975）
-- 4. col1-col20 字段用于模拟多列查询场景
