#!/bin/bash

# 设置环境变量
export SUI_RPC_URL="https://fullnode.testnet.sui.io:443"

# 生成10个随机地址
echo "生成10个随机地址..."
ADDRESSES=()
for i in {1..10}; do
    ADDRESSES+=("0x$(openssl rand -hex 32)")
done

# 将地址列表转换为JSON数组格式
RECEIVERS_LIST="["
for addr in "${ADDRESSES[@]}"; do
    RECEIVERS_LIST+="\"$addr\","
done
RECEIVERS_LIST=${RECEIVERS_LIST%,}"]"

echo "接收者列表: $RECEIVERS_LIST"

# 获取合约ID和TreasuryCap ID
PACKAGE_ID="0x9fed724f1aa624cb7cbad335cf4c0e914fceb2d89cfff17fcd0500371ef5d98a"
TREASURY_CAP="0x4d2875cdd64859d42d8b0a9676c04ecb2426cd69aeee0af14443933953925889"

# 创建空投
echo "创建空投..."
TRANSACTION_OUTPUT=$(sui client call \
    --package 0x9fed724f1aa624cb7cbad335cf4c0e914fceb2d89cfff17fcd0500371ef5d98a \
    --module cbh_token \
    --function create_airdrop \
    --args $TREASURY_CAP 1000000000 1000000 $(date +%s) $(($(date +%s) + 3600)) "" "$RECEIVERS_LIST" \
    --gas-budget 100000000 \
    --json 2>&1)

echo "等待交易确认..."

# 从输出中提取JSON部分
JSON_OUTPUT=$(echo "$TRANSACTION_OUTPUT" | sed -n '/^{/,/^}/p')

# 检查是否成功获取JSON输出
if ! jq -e . >/dev/null 2>&1 <<<"$JSON_OUTPUT"; then
    echo "错误：无法解析交易输出为JSON格式"
    echo "交易输出: $TRANSACTION_OUTPUT"
    exit 1
fi

# 使用jq提取空投对象ID
AIRDROP_ID=$(echo "$JSON_OUTPUT" | jq -r '.objectChanges[] | select(.objectType | endswith("::Airdrop")) | .objectId')
if [ -z "$AIRDROP_ID" ]; then
    echo "错误：无法获取空投对象ID"
    echo "交易输出: $JSON_OUTPUT"
    exit 1
fi

echo "空投对象ID: $AIRDROP_ID"

# 获取分片对象数量和ID列表
SHARD_IDS=($(echo "$JSON_OUTPUT" | jq -r '.objectChanges[] | select(.objectType | endswith("::AirdropShard")) | .objectId'))
SHARD_COUNT=${#SHARD_IDS[@]}

if [ "$SHARD_COUNT" -eq 0 ]; then
    echo "错误：未创建任何分片对象"
    exit 1
fi

echo "创建了 $SHARD_COUNT 个分片对象"

# 为每个地址领取空投
i=0
for addr in "${ADDRESSES[@]}"; do
    if [ $i -ge $SHARD_COUNT ]; then
        echo "错误：分片对象数量不足"
        exit 1
    fi
    
    SHARD_ID=${SHARD_IDS[$i]}
    echo "用户地址 $addr 使用分片ID $SHARD_ID 领取空投..."
    
    CLAIM_OUTPUT=$(sui client call \
        --package 0x9fed724f1aa624cb7cbad335cf4c0e914fceb2d89cfff17fcd0500371ef5d98a \
        --module cbh_token \
        --function claim_airdrop \
        --args $AIRDROP_ID $SHARD_ID $addr \
        --gas-budget 10000000 \
        --json 2>&1)
    
    # 从输出中提取JSON部分
    CLAIM_JSON=$(echo "$CLAIM_OUTPUT" | sed -n '/^{/,/^}/p')
    
    # 检查领取结果
    if ! jq -e . >/dev/null 2>&1 <<<"$CLAIM_JSON"; then
        echo "警告：领取结果不是有效的JSON格式"
        echo "领取结果: $CLAIM_OUTPUT"
    else
        DIGEST=$(echo "$CLAIM_JSON" | jq -r '.digest')
        STATUS=$(echo "$CLAIM_JSON" | jq -r '.effects.status.status')
        echo "领取结果 - 交易摘要: $DIGEST, 状态: $STATUS"
    fi
    
    ((i++))
done

echo "空投测试完成" 