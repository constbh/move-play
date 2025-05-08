#!/bin/bash

# 生成随机地址的函数
generate_random_addresses() {
    local count=$1
    local addresses=()
    
    for ((i=0; i<count; i++)); do
        # 生成32字节的随机十六进制字符串
        local random_bytes=$(openssl rand -hex 32)
        addresses+=("0x$random_bytes")
    done
    
    echo "${addresses[@]}"
}

# 计算分片ID的函数
calculate_shard_id() {
    local address=$1
    local total_shards=$2
    
    # 使用Python计算blake2b哈希
    local shard_id=$(python3 -c "
import hashlib
import sys

address = sys.argv[1]
total_shards = int(sys.argv[2])

# 移除0x前缀
address = address[2:]

# 计算blake2b哈希
hash_obj = hashlib.blake2b(digest_size=8)
hash_obj.update(bytes.fromhex(address))
first_hash = hash_obj.hexdigest()

# 再次计算哈希
hash_obj = hashlib.blake2b(digest_size=8)
hash_obj.update(bytes.fromhex(first_hash))
final_hash = hash_obj.hexdigest()

# 转换为十进制并对分片总数取模
shard_id = int(final_hash, 16) % total_shards
print(shard_id)
" "$address" "$total_shards")
    
    echo "$shard_id"
}

# 生成20个随机地址
echo "生成20个随机地址..."
addresses=($(generate_random_addresses 20))
echo "接收者列表: ${addresses[*]}"

# 创建空投
echo "创建空投..."
airdrop_result=$(sui client call --package 0x8a0c838415206b7a47f19d19db0dde65d3e1b169179210f6d2ebe71d21e58b21 \
    --module airdrop \
    --function create_airdrop \
    --args "${addresses[@]}" \
    --gas-budget 100000000)

# 提取空投对象ID
airdrop_id=$(echo "$airdrop_result" | grep -oP 'Created Objects:.*?ID: \K[0-9a-fx]+')
echo "空投对象ID: $airdrop_id"

# 等待交易确认
echo "等待交易确认..."
sleep 5

# 获取分片对象
shard_objects=($(sui client call --package 0x8a0c838415206b7a47f19d19db0dde65d3e1b169179210f6d2ebe71d21e58b21 \
    --module airdrop \
    --function get_shard_objects \
    --args "$airdrop_id" \
    --gas-budget 100000000 | grep -oP 'ID: \K[0-9a-fx]+'))

echo "创建了 ${#shard_objects[@]} 个分片对象"

# 为每个地址计算分片ID并领取
for address in "${addresses[@]}"; do
    # 计算分片ID
    shard_id=$(calculate_shard_id "$address" ${#shard_objects[@]})
    shard_object=${shard_objects[$shard_id]}
    
    echo "用户地址 $address 计算得到的分片ID: $shard_id, 使用分片对象: $shard_object"
    
    # 异步领取
    (
        claim_result=$(sui client call --package 0x8a0c838415206b7a47f19d19db0dde65d3e1b169179210f6d2ebe71d21e58b21 \
            --module airdrop \
            --function claim \
            --args "$airdrop_id" "$shard_object" "$address" \
            --gas-budget 100000000)
        
        # 提取交易摘要和状态
        digest=$(echo "$claim_result" | grep -oP 'Transaction Digest: \K[0-9a-f]+')
        status=$(echo "$claim_result" | grep -oP 'Status: \K[A-Z]+')
        
        echo "地址 $address 领取结果 - 交易摘要: $digest, 状态: $status"
    ) &
done

# 等待所有后台任务完成
wait

echo "空投测试完成" 