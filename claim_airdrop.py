import json
import asyncio
import aiohttp
import subprocess
from typing import List, Dict

async def claim_airdrop(session: aiohttp.ClientSession, package_id: str, airdrop_id: str, shard_object_id: str, receiver: str) -> Dict:
    """单个用户领取空投的异步函数"""
    cmd = [
        "sui", "client", "call",
        "--package", package_id,
        "--module", "cbh_token",
        "--function", "claim_airdrop",
        "--args",
        airdrop_id,
        shard_object_id,
        receiver,
        "--gas-budget", "5000000"
    ]
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True)
        output = result.stdout + result.stderr
        
        # 忽略API版本不匹配的警告
        if "Client/Server api version mismatch" in output:
            output = output.split("\n", 1)[1] if "\n" in output else ""
        
        if result.returncode == 0:
            return {
                "receiver": receiver,
                "status": "success",
                "message": "空投领取成功",
                "details": output.strip()
            }
        else:
            return {
                "receiver": receiver,
                "status": "failed",
                "message": "空投领取失败",
                "details": output.strip()
            }
    except Exception as e:
        return {
            "receiver": receiver,
            "status": "error",
            "message": str(e),
            "details": ""
        }

async def retry_failed_claims():
    """重新尝试失败的领取操作"""
    # 读取之前的领取结果
    with open('claim_results.json', 'r') as f:
        previous_results = json.load(f)
    
    # 读取空投信息
    with open('airdrop_info.json', 'r') as f:
        airdrop_info = json.load(f)
    
    package_id = "0x9c367a8a2ef5275600b78e263023017b97567fe285e01eb9e697e76cccc0bb5d"
    airdrop_id = airdrop_info["airdrop_id"]
    
    # 找出失败的案例
    failed_claims = [r for r in previous_results if r["status"] == "failed"]
    
    if not failed_claims:
        print("没有需要重试的失败案例")
        return
    
    print(f"\n开始重试失败的领取操作...")
    print(f"需要重试的数量: {len(failed_claims)}")
    
    # 创建任务列表
    tasks = []
    async with aiohttp.ClientSession() as session:
        for failed_claim in failed_claims:
            # 找到对应的shard信息
            receiver_info = next(
                (info for info in airdrop_info["receiver_shard_infos"] 
                 if info["receiver"] == failed_claim["receiver"]),
                None
            )
            
            if receiver_info:
                task = claim_airdrop(
                    session,
                    package_id,
                    airdrop_id,
                    receiver_info["shard_object_id"],
                    failed_claim["receiver"]
                )
                tasks.append(task)
        
        # 并发执行所有任务
        results = await asyncio.gather(*tasks)
        
        # 统计结果
        success_count = sum(1 for r in results if r["status"] == "success")
        failed_count = sum(1 for r in results if r["status"] == "failed")
        error_count = sum(1 for r in results if r["status"] == "error")
        
        print(f"\n重试结果统计:")
        print(f"总重试数: {len(results)}")
        print(f"成功: {success_count}")
        print(f"失败: {failed_count}")
        print(f"错误: {error_count}")
        
        # 更新结果文件
        for result in results:
            # 更新之前的结果
            for prev_result in previous_results:
                if prev_result["receiver"] == result["receiver"]:
                    prev_result.update(result)
        
        # 保存更新后的结果
        with open('claim_results.json', 'w') as f:
            json.dump(previous_results, f, indent=2, ensure_ascii=False)
        
        print("\n更新后的结果已保存到 claim_results.json")
        
        # 显示仍然失败的案例
        if failed_count > 0:
            print("\n仍然失败的案例详情:")
            for result in results:
                if result["status"] == "failed":
                    print(f"\n接收者: {result['receiver']}")
                    print(f"错误信息: {result['details']}")

async def main():
    # 读取空投信息
    with open('airdrop_info.json', 'r') as f:
        airdrop_info = json.load(f)
    
    package_id = "0x9c367a8a2ef5275600b78e263023017b97567fe285e01eb9e697e76cccc0bb5d"
    airdrop_id = airdrop_info["airdrop_id"]
    
    print(f"开始领取空投...")
    print(f"空投ID: {airdrop_id}")
    print(f"总接收者数量: {len(airdrop_info['receiver_shard_infos'])}")
    
    # 创建任务列表
    tasks = []
    async with aiohttp.ClientSession() as session:
        for receiver_info in airdrop_info["receiver_shard_infos"]:
            task = claim_airdrop(
                session,
                package_id,
                airdrop_id,
                receiver_info["shard_object_id"],
                receiver_info["receiver"]
            )
            tasks.append(task)
        
        # 并发执行所有任务
        results = await asyncio.gather(*tasks)
        
        # 统计结果
        success_count = sum(1 for r in results if r["status"] == "success")
        failed_count = sum(1 for r in results if r["status"] == "failed")
        error_count = sum(1 for r in results if r["status"] == "error")
        
        print(f"\n空投领取结果统计:")
        print(f"总用户数: {len(results)}")
        print(f"成功: {success_count}")
        print(f"失败: {failed_count}")
        print(f"错误: {error_count}")
        
        # 保存详细结果到文件
        with open('claim_results.json', 'w') as f:
            json.dump(results, f, indent=2, ensure_ascii=False)
        
        print("\n详细结果已保存到 claim_results.json")
        
        # 显示失败案例的详细信息
        if failed_count > 0:
            print("\n失败案例详情:")
            for result in results:
                if result["status"] == "failed":
                    print(f"\n接收者: {result['receiver']}")
                    print(f"错误信息: {result['details']}")

if __name__ == "__main__":
    # 检查是否存在claim_results.json
    try:
        with open('claim_results.json', 'r') as f:
            # 如果文件存在，执行重试逻辑
            asyncio.run(retry_failed_claims())
    except FileNotFoundError:
        # 如果文件不存在，执行正常的领取逻辑
        asyncio.run(main()) 