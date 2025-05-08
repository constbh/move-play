import random
import string

def generate_random_sui_address():
    # Sui地址是32字节的十六进制字符串,以0x开头
    hex_chars = string.hexdigits.lower()[:16]  # 0-9, a-f
    address = '0x' + ''.join(random.choice(hex_chars) for _ in range(64))
    return address

# 生成50个随机地址
addresses = [generate_random_sui_address() for _ in range(50)]

# 将地址写入文件
with open('airdrop_receivers.txt', 'w') as f:
    for addr in addresses:
        f.write(addr + '\n')

print(f"Generated {len(addresses)} random Sui addresses and saved to airdrop_receivers.txt") 