SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ============================================================
-- NSCA 外骨骼系统 —— 支付 (pay) + 会员 (member) 模块增量表结构
-- 基于 yudao-cloud 芋道快速开发平台
-- ============================================================

-- ----------------------------
-- 支付应用表
-- ----------------------------
DROP TABLE IF EXISTS `pay_app`;
CREATE TABLE `pay_app` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '应用编号',
  `app_key` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '应用标识',
  `name` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '应用名',
  `status` tinyint NOT NULL DEFAULT 0 COMMENT '状态',
  `remark` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '备注',
  `order_notify_url` varchar(512) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '支付结果回调地址',
  `refund_notify_url` varchar(512) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '退款结果回调地址',
  `transfer_notify_url` varchar(512) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '转账结果回调地址',
  `creator` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '创建者',
  `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updater` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '更新者',
  `update_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `deleted` bit(1) NOT NULL DEFAULT b'0' COMMENT '是否删除',
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE INDEX `uk_app_key`(`app_key` ASC) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT = '支付应用表';

-- ----------------------------
-- 支付渠道表
-- ----------------------------
DROP TABLE IF EXISTS `pay_channel`;
CREATE TABLE `pay_channel` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '渠道编号',
  `code` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '渠道编码',
  `status` tinyint NOT NULL DEFAULT 0 COMMENT '状态',
  `fee_rate` double NOT NULL DEFAULT 0 COMMENT '渠道费率，单位：百分比',
  `remark` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '备注',
  `app_id` bigint NOT NULL DEFAULT 0 COMMENT '应用编号',
  `config` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL COMMENT '支付渠道配置（JSON）',
  `creator` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '创建者',
  `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updater` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '更新者',
  `update_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `deleted` bit(1) NOT NULL DEFAULT b'0' COMMENT '是否删除',
  `tenant_id` bigint NOT NULL DEFAULT 0 COMMENT '租户编号',
  PRIMARY KEY (`id`) USING BTREE,
  INDEX `idx_app_id`(`app_id` ASC) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT = '支付渠道表';

-- ----------------------------
-- 支付订单表
-- ----------------------------
DROP TABLE IF EXISTS `pay_order`;
CREATE TABLE `pay_order` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '订单编号',
  `app_id` bigint NOT NULL DEFAULT 0 COMMENT '应用编号',
  `channel_id` bigint NOT NULL DEFAULT 0 COMMENT '渠道编号',
  `channel_code` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '渠道编码',
  `user_id` bigint NOT NULL DEFAULT 0 COMMENT '用户编号',
  `user_type` tinyint NOT NULL DEFAULT 0 COMMENT '用户类型',
  `merchant_order_id` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '商户订单编号',
  `subject` varchar(256) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '商品标题',
  `body` varchar(512) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '商品描述',
  `notify_url` varchar(512) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '异步通知地址',
  `price` int NOT NULL DEFAULT 0 COMMENT '支付金额，单位：分',
  `channel_fee_rate` double NOT NULL DEFAULT 0 COMMENT '渠道手续费，单位：百分比',
  `channel_fee_price` int NOT NULL DEFAULT 0 COMMENT '渠道手续金额，单位：分',
  `status` tinyint NOT NULL DEFAULT 0 COMMENT '支付状态',
  `user_ip` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '用户 IP',
  `expire_time` datetime NULL DEFAULT NULL COMMENT '订单失效时间',
  `success_time` datetime NULL DEFAULT NULL COMMENT '订单支付成功时间',
  `extension_id` bigint NOT NULL DEFAULT 0 COMMENT '支付成功的订单拓展单编号',
  `no` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '支付成功的外部订单号',
  `refund_price` int NOT NULL DEFAULT 0 COMMENT '退款总金额，单位：分',
  `channel_user_id` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '渠道用户编号',
  `channel_order_no` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '渠道订单号',
  `creator` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '创建者',
  `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updater` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '更新者',
  `update_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `deleted` bit(1) NOT NULL DEFAULT b'0' COMMENT '是否删除',
  PRIMARY KEY (`id`) USING BTREE,
  INDEX `idx_app_id`(`app_id` ASC) USING BTREE,
  INDEX `idx_merchant_order_id`(`merchant_order_id` ASC) USING BTREE,
  INDEX `idx_no`(`no` ASC) USING BTREE,
  INDEX `idx_user_id`(`user_id` ASC) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT = '支付订单表';

-- ----------------------------
-- 支付订单拓展表
-- ----------------------------
DROP TABLE IF EXISTS `pay_order_extension`;
CREATE TABLE `pay_order_extension` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '订单拓展编号',
  `no` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '外部订单号',
  `order_id` bigint NOT NULL DEFAULT 0 COMMENT '支付订单编号',
  `channel_id` bigint NOT NULL DEFAULT 0 COMMENT '渠道编号',
  `channel_code` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '渠道编码',
  `user_ip` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '用户 IP',
  `status` tinyint NOT NULL DEFAULT 0 COMMENT '支付状态',
  `channel_extras` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL COMMENT '支付渠道额外参数（JSON）',
  `channel_error_code` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '调用渠道错误码',
  `channel_error_msg` varchar(512) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '调用渠道错误信息',
  `channel_notify_data` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL COMMENT '支付渠道通知内容',
  `creator` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '创建者',
  `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updater` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '更新者',
  `update_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `deleted` bit(1) NOT NULL DEFAULT b'0' COMMENT '是否删除',
  PRIMARY KEY (`id`) USING BTREE,
  INDEX `idx_order_id`(`order_id` ASC) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT = '支付订单拓展表';

-- ----------------------------
-- 支付退款单表
-- ----------------------------
DROP TABLE IF EXISTS `pay_refund`;
CREATE TABLE `pay_refund` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '退款单编号',
  `no` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '外部退款号',
  `app_id` bigint NOT NULL DEFAULT 0 COMMENT '应用编号',
  `channel_id` bigint NOT NULL DEFAULT 0 COMMENT '渠道编号',
  `channel_code` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '渠道编码',
  `order_id` bigint NOT NULL DEFAULT 0 COMMENT '订单编号',
  `order_no` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '支付订单编号',
  `user_id` bigint NOT NULL DEFAULT 0 COMMENT '用户编号',
  `user_type` tinyint NOT NULL DEFAULT 0 COMMENT '用户类型',
  `merchant_order_id` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '商户订单编号',
  `merchant_refund_id` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '商户退款订单号',
  `notify_url` varchar(512) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '异步通知地址',
  `status` tinyint NOT NULL DEFAULT 0 COMMENT '退款状态',
  `pay_price` int NOT NULL DEFAULT 0 COMMENT '支付金额，单位：分',
  `refund_price` int NOT NULL DEFAULT 0 COMMENT '退款金额，单位：分',
  `reason` varchar(256) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '退款原因',
  `user_ip` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '用户 IP',
  `channel_order_no` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '渠道订单号',
  `channel_refund_no` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '渠道退款单号',
  `success_time` datetime NULL DEFAULT NULL COMMENT '退款成功时间',
  `channel_error_code` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '调用渠道错误码',
  `channel_error_msg` varchar(512) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '调用渠道错误提示',
  `channel_notify_data` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL COMMENT '支付渠道通知内容',
  `creator` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '创建者',
  `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updater` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '更新者',
  `update_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `deleted` bit(1) NOT NULL DEFAULT b'0' COMMENT '是否删除',
  PRIMARY KEY (`id`) USING BTREE,
  INDEX `idx_order_id`(`order_id` ASC) USING BTREE,
  INDEX `idx_no`(`no` ASC) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT = '支付退款单表';

-- ----------------------------
-- 转账单表
-- ----------------------------
DROP TABLE IF EXISTS `pay_transfer`;
CREATE TABLE `pay_transfer` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '转账单编号',
  `no` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '转账单号',
  `app_id` bigint NOT NULL DEFAULT 0 COMMENT '应用编号',
  `channel_id` bigint NOT NULL DEFAULT 0 COMMENT '转账渠道编号',
  `channel_code` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '转账渠道编码',
  `user_id` bigint NOT NULL DEFAULT 0 COMMENT '用户编号',
  `user_type` tinyint NOT NULL DEFAULT 0 COMMENT '用户类型',
  `merchant_transfer_id` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '商户转账单编号',
  `subject` varchar(256) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '转账标题',
  `price` int NOT NULL DEFAULT 0 COMMENT '转账金额，单位：分',
  `user_account` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '收款人账号',
  `user_name` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '收款人姓名',
  `status` tinyint NOT NULL DEFAULT 0 COMMENT '转账状态',
  `success_time` datetime NULL DEFAULT NULL COMMENT '转账成功时间',
  `notify_url` varchar(512) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '异步通知地址',
  `user_ip` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '用户 IP',
  `channel_extras` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL COMMENT '渠道额外参数（JSON）',
  `channel_transfer_no` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '渠道转账单号',
  `channel_error_code` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '调用渠道错误码',
  `channel_error_msg` varchar(512) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '调用渠道错误提示',
  `channel_notify_data` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL COMMENT '渠道通知内容',
  `channel_package_info` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL COMMENT '渠道 package 信息',
  `creator` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '创建者',
  `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updater` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '更新者',
  `update_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `deleted` bit(1) NOT NULL DEFAULT b'0' COMMENT '是否删除',
  PRIMARY KEY (`id`) USING BTREE,
  INDEX `idx_app_id`(`app_id` ASC) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT = '转账单表';

-- ----------------------------
-- 会员钱包表
-- ----------------------------
DROP TABLE IF EXISTS `pay_wallet`;
CREATE TABLE `pay_wallet` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '钱包编号',
  `user_id` bigint NOT NULL DEFAULT 0 COMMENT '用户编号',
  `user_type` tinyint NOT NULL DEFAULT 0 COMMENT '用户类型',
  `balance` int NOT NULL DEFAULT 0 COMMENT '余额，单位：分',
  `freeze_price` int NOT NULL DEFAULT 0 COMMENT '冻结金额，单位：分',
  `total_expense` int NOT NULL DEFAULT 0 COMMENT '累计支出，单位：分',
  `total_recharge` int NOT NULL DEFAULT 0 COMMENT '累计充值，单位：分',
  `creator` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '创建者',
  `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updater` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '更新者',
  `update_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `deleted` bit(1) NOT NULL DEFAULT b'0' COMMENT '是否删除',
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE INDEX `uk_user_id_type`(`user_id` ASC, `user_type` ASC) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT = '会员钱包表';

-- ----------------------------
-- 会员钱包流水表
-- ----------------------------
DROP TABLE IF EXISTS `pay_wallet_transaction`;
CREATE TABLE `pay_wallet_transaction` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '流水编号',
  `no` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '流水号',
  `wallet_id` bigint NOT NULL DEFAULT 0 COMMENT '钱包编号',
  `biz_type` tinyint NOT NULL DEFAULT 0 COMMENT '关联业务分类',
  `biz_id` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '关联业务编号',
  `title` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '流水说明',
  `price` int NOT NULL DEFAULT 0 COMMENT '交易金额，单位：分（正值增加，负值减少）',
  `balance` int NOT NULL DEFAULT 0 COMMENT '交易后余额，单位：分',
  `creator` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '创建者',
  `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updater` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '更新者',
  `update_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `deleted` bit(1) NOT NULL DEFAULT b'0' COMMENT '是否删除',
  PRIMARY KEY (`id`) USING BTREE,
  INDEX `idx_wallet_id`(`wallet_id` ASC) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT = '会员钱包流水表';

-- ----------------------------
-- 会员钱包充值表
-- ----------------------------
DROP TABLE IF EXISTS `pay_wallet_recharge`;
CREATE TABLE `pay_wallet_recharge` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '充值编号',
  `wallet_id` bigint NOT NULL DEFAULT 0 COMMENT '钱包编号',
  `total_price` int NOT NULL DEFAULT 0 COMMENT '用户实际到账余额，单位：分',
  `pay_price` int NOT NULL DEFAULT 0 COMMENT '实际支付金额，单位：分',
  `bonus_price` int NOT NULL DEFAULT 0 COMMENT '钱包赠送金额，单位：分',
  `package_id` bigint NOT NULL DEFAULT 0 COMMENT '充值套餐编号',
  `pay_status` bit(1) NOT NULL DEFAULT b'0' COMMENT '是否已支付',
  `pay_order_id` bigint NOT NULL DEFAULT 0 COMMENT '支付订单编号',
  `pay_channel_code` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '支付成功的支付渠道',
  `pay_time` datetime NULL DEFAULT NULL COMMENT '订单支付时间',
  `pay_refund_id` bigint NOT NULL DEFAULT 0 COMMENT '支付退款单编号',
  `refund_total_price` int NOT NULL DEFAULT 0 COMMENT '退款金额（包含赠送金额），单位：分',
  `refund_pay_price` int NOT NULL DEFAULT 0 COMMENT '退款支付金额，单位：分',
  `refund_bonus_price` int NOT NULL DEFAULT 0 COMMENT '退款钱包赠送金额，单位：分',
  `refund_time` datetime NULL DEFAULT NULL COMMENT '退款时间',
  `refund_status` tinyint NOT NULL DEFAULT 0 COMMENT '退款状态',
  `creator` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '创建者',
  `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updater` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '更新者',
  `update_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `deleted` bit(1) NOT NULL DEFAULT b'0' COMMENT '是否删除',
  PRIMARY KEY (`id`) USING BTREE,
  INDEX `idx_wallet_id`(`wallet_id` ASC) USING BTREE,
  INDEX `idx_pay_order_id`(`pay_order_id` ASC) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT = '会员钱包充值表';

-- ----------------------------
-- 会员钱包充值套餐表
-- ----------------------------
DROP TABLE IF EXISTS `pay_wallet_recharge_package`;
CREATE TABLE `pay_wallet_recharge_package` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '套餐编号',
  `name` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '套餐名',
  `pay_price` int NOT NULL DEFAULT 0 COMMENT '支付金额，单位：分',
  `bonus_price` int NOT NULL DEFAULT 0 COMMENT '赠送金额，单位：分',
  `status` tinyint NOT NULL DEFAULT 0 COMMENT '状态',
  `creator` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '创建者',
  `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updater` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '更新者',
  `update_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `deleted` bit(1) NOT NULL DEFAULT b'0' COMMENT '是否删除',
  PRIMARY KEY (`id`) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT = '会员钱包充值套餐表';

-- ----------------------------
-- 支付通知任务表
-- ----------------------------
DROP TABLE IF EXISTS `pay_notify_task`;
CREATE TABLE `pay_notify_task` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '通知编号',
  `app_id` bigint NOT NULL DEFAULT 0 COMMENT '应用编号',
  `type` tinyint NOT NULL DEFAULT 0 COMMENT '通知类型',
  `data_id` bigint NOT NULL DEFAULT 0 COMMENT '数据编号',
  `merchant_order_id` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '商户订单编号',
  `merchant_refund_id` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '商户退款编号',
  `merchant_transfer_id` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '商户转账编号',
  `status` tinyint NOT NULL DEFAULT 0 COMMENT '通知状态',
  `next_notify_time` datetime NULL DEFAULT NULL COMMENT '下一次通知时间',
  `last_execute_time` datetime NULL DEFAULT NULL COMMENT '最后一次执行时间',
  `notify_times` int NOT NULL DEFAULT 0 COMMENT '当前通知次数',
  `max_notify_times` int NOT NULL DEFAULT 0 COMMENT '最大可通知次数',
  `notify_url` varchar(512) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '通知地址',
  `creator` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '创建者',
  `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updater` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '更新者',
  `update_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `deleted` bit(1) NOT NULL DEFAULT b'0' COMMENT '是否删除',
  `tenant_id` bigint NOT NULL DEFAULT 0 COMMENT '租户编号',
  PRIMARY KEY (`id`) USING BTREE,
  INDEX `idx_app_id`(`app_id` ASC) USING BTREE,
  INDEX `idx_status_next_time`(`status` ASC, `next_notify_time` ASC) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT = '支付通知任务表';

-- ----------------------------
-- 支付通知日志表
-- ----------------------------
DROP TABLE IF EXISTS `pay_notify_log`;
CREATE TABLE `pay_notify_log` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '日志编号',
  `task_id` bigint NOT NULL DEFAULT 0 COMMENT '通知任务编号',
  `notify_times` int NOT NULL DEFAULT 0 COMMENT '第几次被通知',
  `response` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL COMMENT 'HTTP 响应结果',
  `status` tinyint NOT NULL DEFAULT 0 COMMENT '支付通知状态',
  `creator` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '创建者',
  `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updater` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '更新者',
  `update_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `deleted` bit(1) NOT NULL DEFAULT b'0' COMMENT '是否删除',
  PRIMARY KEY (`id`) USING BTREE,
  INDEX `idx_task_id`(`task_id` ASC) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT = '支付通知日志表';

-- ============================================================
-- 会员中心 (member) 表结构
-- ============================================================

-- ----------------------------
-- 会员用户表
-- ----------------------------
DROP TABLE IF EXISTS `member_user`;
CREATE TABLE `member_user` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '用户ID',
  `mobile` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '手机号',
  `password` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '加密后的密码',
  `status` tinyint NOT NULL DEFAULT 0 COMMENT '帐号状态',
  `register_ip` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '注册 IP',
  `register_terminal` tinyint NOT NULL DEFAULT 0 COMMENT '注册终端',
  `login_ip` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '最后登录IP',
  `login_date` datetime NULL DEFAULT NULL COMMENT '最后登录时间',
  `nickname` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '用户昵称',
  `avatar` varchar(512) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '用户头像',
  `name` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '真实名字',
  `sex` tinyint NULL DEFAULT 0 COMMENT '性别',
  `birthday` datetime NULL DEFAULT NULL COMMENT '出生日期',
  `area_id` int NULL DEFAULT 0 COMMENT '所在地编号',
  `mark` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '用户备注',
  `point` int NOT NULL DEFAULT 0 COMMENT '积分',
  `tag_ids` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '会员标签列表',
  `level_id` bigint NOT NULL DEFAULT 0 COMMENT '会员级别编号',
  `experience` int NOT NULL DEFAULT 0 COMMENT '会员经验',
  `group_id` bigint NOT NULL DEFAULT 0 COMMENT '用户分组编号',
  `creator` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '创建者',
  `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updater` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '更新者',
  `update_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `deleted` bit(1) NOT NULL DEFAULT b'0' COMMENT '是否删除',
  `tenant_id` bigint NOT NULL DEFAULT 0 COMMENT '租户编号',
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE INDEX `uk_mobile`(`mobile` ASC) USING BTREE,
  INDEX `idx_level_id`(`level_id` ASC) USING BTREE,
  INDEX `idx_group_id`(`group_id` ASC) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT = '会员用户表';

-- ----------------------------
-- 会员等级表
-- ----------------------------
DROP TABLE IF EXISTS `member_level`;
CREATE TABLE `member_level` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '编号',
  `name` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '等级名称',
  `level` int NOT NULL DEFAULT 0 COMMENT '等级',
  `experience` int NOT NULL DEFAULT 0 COMMENT '升级经验',
  `discount_percent` int NOT NULL DEFAULT 0 COMMENT '享受折扣',
  `icon` varchar(512) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '等级图标',
  `background_url` varchar(512) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '等级背景图',
  `status` tinyint NOT NULL DEFAULT 0 COMMENT '状态',
  `creator` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '创建者',
  `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updater` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '更新者',
  `update_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `deleted` bit(1) NOT NULL DEFAULT b'0' COMMENT '是否删除',
  PRIMARY KEY (`id`) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT = '会员等级表';

-- ----------------------------
-- 会员等级记录表
-- ----------------------------
DROP TABLE IF EXISTS `member_level_record`;
CREATE TABLE `member_level_record` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '编号',
  `user_id` bigint NOT NULL DEFAULT 0 COMMENT '用户编号',
  `level_id` bigint NOT NULL DEFAULT 0 COMMENT '等级编号',
  `level` int NOT NULL DEFAULT 0 COMMENT '会员等级',
  `discount_percent` int NOT NULL DEFAULT 0 COMMENT '享受折扣',
  `experience` int NOT NULL DEFAULT 0 COMMENT '升级经验',
  `user_experience` int NOT NULL DEFAULT 0 COMMENT '会员此时的经验',
  `remark` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '备注',
  `description` varchar(512) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '描述',
  `creator` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '创建者',
  `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updater` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '更新者',
  `update_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `deleted` bit(1) NOT NULL DEFAULT b'0' COMMENT '是否删除',
  PRIMARY KEY (`id`) USING BTREE,
  INDEX `idx_user_id`(`user_id` ASC) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT = '会员等级记录表';

-- ----------------------------
-- 会员经验记录表
-- ----------------------------
DROP TABLE IF EXISTS `member_experience_record`;
CREATE TABLE `member_experience_record` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '编号',
  `user_id` bigint NOT NULL DEFAULT 0 COMMENT '用户编号',
  `biz_type` tinyint NOT NULL DEFAULT 0 COMMENT '业务类型',
  `biz_id` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '业务编号',
  `title` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '标题',
  `description` varchar(512) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '描述',
  `experience` int NOT NULL DEFAULT 0 COMMENT '经验变动值',
  `total_experience` int NOT NULL DEFAULT 0 COMMENT '变更后的经验',
  `creator` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '创建者',
  `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updater` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '更新者',
  `update_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `deleted` bit(1) NOT NULL DEFAULT b'0' COMMENT '是否删除',
  PRIMARY KEY (`id`) USING BTREE,
  INDEX `idx_user_id`(`user_id` ASC) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT = '会员经验记录表';

-- ----------------------------
-- 会员积分记录表
-- ----------------------------
DROP TABLE IF EXISTS `member_point_record`;
CREATE TABLE `member_point_record` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '自增主键',
  `user_id` bigint NOT NULL DEFAULT 0 COMMENT '用户编号',
  `biz_id` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '业务编码',
  `biz_type` tinyint NOT NULL DEFAULT 0 COMMENT '业务类型',
  `title` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '积分标题',
  `description` varchar(512) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '积分描述',
  `point` int NOT NULL DEFAULT 0 COMMENT '变动积分（正数获得，负数消耗）',
  `total_point` int NOT NULL DEFAULT 0 COMMENT '变动后的积分',
  `creator` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '创建者',
  `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updater` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '更新者',
  `update_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `deleted` bit(1) NOT NULL DEFAULT b'0' COMMENT '是否删除',
  PRIMARY KEY (`id`) USING BTREE,
  INDEX `idx_user_id`(`user_id` ASC) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT = '会员积分记录表';

-- ----------------------------
-- 签到规则表
-- ----------------------------
DROP TABLE IF EXISTS `member_sign_in_config`;
CREATE TABLE `member_sign_in_config` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '规则自增主键',
  `day` int NOT NULL DEFAULT 0 COMMENT '签到第 x 天',
  `point` int NOT NULL DEFAULT 0 COMMENT '奖励积分',
  `experience` int NOT NULL DEFAULT 0 COMMENT '奖励经验',
  `status` tinyint NOT NULL DEFAULT 0 COMMENT '状态',
  `creator` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '创建者',
  `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updater` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '更新者',
  `update_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `deleted` bit(1) NOT NULL DEFAULT b'0' COMMENT '是否删除',
  PRIMARY KEY (`id`) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT = '签到规则表';

-- ----------------------------
-- 签到记录表
-- ----------------------------
DROP TABLE IF EXISTS `member_sign_in_record`;
CREATE TABLE `member_sign_in_record` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '编号',
  `user_id` bigint NOT NULL DEFAULT 0 COMMENT '签到用户',
  `day` int NOT NULL DEFAULT 0 COMMENT '第几天签到',
  `point` int NOT NULL DEFAULT 0 COMMENT '签到的积分',
  `experience` int NOT NULL DEFAULT 0 COMMENT '签到的经验',
  `creator` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '创建者',
  `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updater` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '更新者',
  `update_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `deleted` bit(1) NOT NULL DEFAULT b'0' COMMENT '是否删除',
  PRIMARY KEY (`id`) USING BTREE,
  INDEX `idx_user_id`(`user_id` ASC) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT = '签到记录表';

-- ----------------------------
-- 会员分组表
-- ----------------------------
DROP TABLE IF EXISTS `member_group`;
CREATE TABLE `member_group` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '编号',
  `name` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '名称',
  `remark` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '备注',
  `status` tinyint NOT NULL DEFAULT 0 COMMENT '状态',
  `creator` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '创建者',
  `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updater` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '更新者',
  `update_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `deleted` bit(1) NOT NULL DEFAULT b'0' COMMENT '是否删除',
  PRIMARY KEY (`id`) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT = '会员分组表';

-- ----------------------------
-- 会员标签表
-- ----------------------------
DROP TABLE IF EXISTS `member_tag`;
CREATE TABLE `member_tag` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '编号',
  `name` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '标签名称',
  `creator` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '创建者',
  `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updater` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '更新者',
  `update_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `deleted` bit(1) NOT NULL DEFAULT b'0' COMMENT '是否删除',
  PRIMARY KEY (`id`) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT = '会员标签表';

-- ----------------------------
-- 会员收货地址表
-- ----------------------------
DROP TABLE IF EXISTS `member_address`;
CREATE TABLE `member_address` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '编号',
  `user_id` bigint NOT NULL DEFAULT 0 COMMENT '用户编号',
  `name` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '收件人名称',
  `mobile` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '手机号',
  `area_id` bigint NOT NULL DEFAULT 0 COMMENT '地区编号',
  `detail_address` varchar(512) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '' COMMENT '收件详细地址',
  `default_status` bit(1) NOT NULL DEFAULT b'0' COMMENT '是否默认',
  `creator` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '创建者',
  `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updater` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '更新者',
  `update_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `deleted` bit(1) NOT NULL DEFAULT b'0' COMMENT '是否删除',
  PRIMARY KEY (`id`) USING BTREE,
  INDEX `idx_user_id`(`user_id` ASC) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT = '会员收货地址表';

-- ----------------------------
-- 会员配置表
-- ----------------------------
DROP TABLE IF EXISTS `member_config`;
CREATE TABLE `member_config` (
  `id` bigint NOT NULL AUTO_INCREMENT COMMENT '自增主键',
  `point_trade_deduct_enable` bit(1) NOT NULL DEFAULT b'0' COMMENT '积分抵扣开关',
  `point_trade_deduct_unit_price` int NOT NULL DEFAULT 0 COMMENT '积分抵扣，单位：分（1积分抵扣多少分）',
  `point_trade_deduct_max_price` int NOT NULL DEFAULT 0 COMMENT '积分抵扣最大值',
  `point_trade_give_point` int NOT NULL DEFAULT 0 COMMENT '1元赠送多少分',
  `creator` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '创建者',
  `create_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  `updater` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL DEFAULT '' COMMENT '更新者',
  `update_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  `deleted` bit(1) NOT NULL DEFAULT b'0' COMMENT '是否删除',
  PRIMARY KEY (`id`) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_unicode_ci COMMENT = '会员配置表';

SET FOREIGN_KEY_CHECKS = 1;
