import json
import subprocess
import re

# 读取接收者地址
with open('airdrop_receivers.txt', 'r') as f:
    addresses = [line.strip() for line in f.readlines()]

# 构建命令
package_id = "0x9c367a8a2ef5275600b78e263023017b97567fe285e01eb9e697e76cccc0bb5d"
treasury_cap = "0x0b00031c2fa77ac76c9268ed53136ef3cac1e7ef89f6046cd3eb30328990dfce"
total_amount = "500000000000"  # 500 CBH
amount_per_user = "10000000000"  # 10 CBH
start_time = "0"
end_time = "18446744073709551615"
whitelist_root = "0x0000000000000000000000000000000000000000000000000000000000000000"

# 构建地址数组字符串
addresses_str = "[" + ",".join(f'"{addr}"' for addr in addresses) + "]"

# 构建完整命令
cmd = [
    "sui", "client", "call",
    "--package", package_id,
    "--module", "cbh_token",
    "--function", "create_airdrop",
    "--args",
    treasury_cap,
    total_amount,
    amount_per_user,
    start_time,
    end_time,
    whitelist_root,
    addresses_str,
    "--gas-budget", "100000000"
]

# 执行命令
result = subprocess.run(cmd, capture_output=True, text=True)

# 解析输出以获取事件信息
output = result.stdout
if "AirdropCreatedEvent" in output:
    # 提取事件信息
    event_pattern = r'AirdropCreatedEvent.*?ParsedJSON:\s*({.*?})'
    match = re.search(event_pattern, output, re.DOTALL)
    
    if match:
        event_json = match.group(1)
        # 解析JSON字符串
        event_data = json.loads(event_json)
        
        # 格式化JSON以便于阅读
        formatted_json = json.dumps(event_data, indent=2)
        
        # 保存事件信息到文件
        with open('airdrop_info.json', 'w') as f:
            f.write(formatted_json)
        
        print("空投创建成功！信息已保存到 airdrop_info.json")
        
        # 打印一些关键信息
        print("\n空投关键信息:")
        print(f"空投ID: {event_data['airdrop_id']}")
        print(f"总数量: {int(event_data['total_amount'])/1000000000} CBH")
        print(f"每个用户数量: {int(event_data['amount_per_user'])/1000000000} CBH")
        print(f"总分片数: {event_data['total_shards']}")
        print(f"接收者数量: {len(event_data['receiver_shard_infos'])}")
        print("\n接收者信息示例(前3个):")
        for info in event_data['receiver_shard_infos'][:3]:
            print(f"地址: {info['receiver']}")
            print(f"分片ID: {info['shard_id']}")
            print(f"分片对象ID: {info['shard_object_id']}")
            print("---")
    else:
        print("无法解析事件信息")
        print("输出:", output)
else:
    print("空投创建失败！")
    print("错误信息:", result.stderr) 