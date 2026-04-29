-- ========================================================
-- NSCA 外骨骼系统 - 未使用模块数据清理脚本
-- 根据 https://cloud.iocoder.cn/migrate-module/ 迁移文档生成
-- 当前保留模块：system, infra, pay, member
-- 删除模块：bpm, report, mp, mall, crm, erp, iot, mes, ai, statistics
-- ========================================================

-- --------------------------------------------------------
-- 步骤1：清理菜单 (system_menu)
-- --------------------------------------------------------

-- 1.1 删除 BPM 工作流相关菜单
DELETE FROM system_menu WHERE name LIKE '%流程%' OR name LIKE '%工作流%' OR name LIKE '%BPM%'
   OR permission LIKE 'bpm:%' OR component LIKE '%bpm/%' OR path LIKE '%bpm%';

-- 1.2 删除数据报表相关菜单
DELETE FROM system_menu WHERE name LIKE '%报表%' OR name LIKE '%大屏%' OR name LIKE '%Report%'
   OR permission LIKE 'report:%' OR component LIKE '%report/%' OR path LIKE '%report%';

-- 1.3 删除微信公众号相关菜单
DELETE FROM system_menu WHERE name LIKE '%公众号%' OR name LIKE '%微信%' OR name LIKE '%MP%'
   OR permission LIKE 'mp:%' OR component LIKE '%mp/%' OR path LIKE '%mp%';

-- 1.4 删除 CRM 相关菜单
DELETE FROM system_menu WHERE name LIKE '%CRM%' OR name LIKE '%客户%'
   OR permission LIKE 'crm:%' OR component LIKE '%crm/%' OR path LIKE '%crm%';

-- 1.5 删除 ERP 相关菜单
DELETE FROM system_menu WHERE name LIKE '%ERP%' OR name LIKE '%采购%' OR name LIKE '%销售%'
   OR name LIKE '%库存%' OR name LIKE '%财务%'
   OR permission LIKE 'erp:%' OR component LIKE '%erp/%' OR path LIKE '%erp%';

-- 1.6 删除 IoT 物联网相关菜单
DELETE FROM system_menu WHERE name LIKE '%IoT%' OR name LIKE '%物联网%' OR name LIKE '%设备%'
   OR permission LIKE 'iot:%' OR component LIKE '%iot/%' OR path LIKE '%iot%';

-- 1.7 删除 MES 制造执行系统相关菜单
DELETE FROM system_menu WHERE name LIKE '%MES%' OR name LIKE '%制造%' OR name LIKE '%生产%'
   OR name LIKE '%工单%' OR name LIKE '%物料%'
   OR permission LIKE 'mes:%' OR component LIKE '%mes/%' OR path LIKE '%mes%';

-- 1.8 删除 AI 大模型相关菜单
DELETE FROM system_menu WHERE name LIKE '%AI%' OR name LIKE '%大模型%' OR name LIKE '%智能%'
   OR permission LIKE 'ai:%' OR component LIKE '%ai/%' OR path LIKE '%ai%';

-- 1.9 删除商城相关菜单（product, promotion, trade, statistics）
DELETE FROM system_menu WHERE name LIKE '%商品%' OR name LIKE '%促销%' OR name LIKE '%订单%'
   OR name LIKE '%购物车%' OR name LIKE '%支付%' AND permission LIKE 'product:%'
   OR permission LIKE 'promotion:%' OR permission LIKE 'trade:%'
   OR component LIKE '%product/%' OR component LIKE '%promotion/%'
   OR component LIKE '%trade/%' OR component LIKE '%statistics/%';

-- 1.10 删除统计相关菜单
DELETE FROM system_menu WHERE name LIKE '%统计%' OR name LIKE '%数据%' AND permission LIKE 'statistics:%';

-- 1.11 递归删除孤儿菜单（没有父菜单的子菜单）
-- 重复执行以下语句直到 Affected rows: 0
DELETE FROM system_menu WHERE parent_id NOT IN
  (SELECT id FROM (SELECT id FROM system_menu) AS TEMP) AND parent_id > 0;

-- 1.12 清理角色菜单关联表
DELETE FROM system_role_menu WHERE menu_id NOT IN (SELECT id FROM system_menu);

-- --------------------------------------------------------
-- 步骤2：清理字典 (system_dict_type / system_dict_data)
-- --------------------------------------------------------

-- 2.1 BPM 模块字典
DELETE FROM system_dict_type WHERE type LIKE 'bpm_%';
DELETE FROM system_dict_data WHERE dict_type LIKE 'bpm_%';

-- 2.2 report 模块字典
DELETE FROM system_dict_type WHERE type LIKE 'report_%';
DELETE FROM system_dict_data WHERE dict_type LIKE 'report_%';

-- 2.3 mp 模块字典
DELETE FROM system_dict_type WHERE type LIKE 'mp_%';
DELETE FROM system_dict_data WHERE dict_type LIKE 'mp_%';

-- 2.4 crm 模块字典
DELETE FROM system_dict_type WHERE type LIKE 'crm_%';
DELETE FROM system_dict_data WHERE dict_type LIKE 'crm_%';

-- 2.5 erp 模块字典
DELETE FROM system_dict_type WHERE type LIKE 'erp_%';
DELETE FROM system_dict_data WHERE dict_type LIKE 'erp_%';

-- 2.6 iot 模块字典
DELETE FROM system_dict_type WHERE type LIKE 'iot_%';
DELETE FROM system_dict_data WHERE dict_type LIKE 'iot_%';

-- 2.7 mes 模块字典
DELETE FROM system_dict_type WHERE type LIKE 'mes_%';
DELETE FROM system_dict_data WHERE dict_type LIKE 'mes_%';

-- 2.8 ai 模块字典
DELETE FROM system_dict_type WHERE type LIKE 'ai_%';
DELETE FROM system_dict_data WHERE dict_type LIKE 'ai_%';

-- 2.9 mall 模块字典
DELETE FROM system_dict_type WHERE type LIKE 'product_%';
DELETE FROM system_dict_data WHERE dict_type LIKE 'product_%';
DELETE FROM system_dict_type WHERE type LIKE 'trade_%';
DELETE FROM system_dict_data WHERE dict_type LIKE 'trade_%';
DELETE FROM system_dict_type WHERE type LIKE 'promotion_%';
DELETE FROM system_dict_data WHERE dict_type LIKE 'promotion_%';
DELETE FROM system_dict_type WHERE type LIKE 'brokerage_enabled_condition_%';
DELETE FROM system_dict_data WHERE dict_type LIKE 'brokerage_enabled_condition_%';
DELETE FROM system_dict_type WHERE type LIKE 'statistics_%';
DELETE FROM system_dict_data WHERE dict_type LIKE 'statistics_%';

-- --------------------------------------------------------
-- 注意：pay 和 member 模块的字典需要保留
-- pay_channel_code, pay_notify_status, pay_order_status, pay_refund_status 等
-- member 相关的字典也保留
-- --------------------------------------------------------
