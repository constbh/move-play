module cbh_token::cbh_token {
    use std::option;
    use std::vector;
    use sui::object::{Self, UID, ID};
    use sui::coin::{Self, Coin};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::url::Url;
    use sui::hash::blake2b256;
    use std::bcs;
    use sui::event;
    use sui::dynamic_field;

    /// 代币名称
    const TOKEN_NAME: vector<u8> = b"CBH";
    /// 代币符号
    const TOKEN_SYMBOL: vector<u8> = b"CBH";
    /// 代币精度
    const TOKEN_DECIMALS: u8 = 9;
    /// 代币描述
    const TOKEN_DESCRIPTION: vector<u8> = b"CBH Token";
    /// 默认分片数量
    const DEFAULT_SHARD_NUM: u64 = 16;
    
    /// 错误码：空投已结束
    const EAIRDROP_ENDED: u64 = 1;
    /// 错误码：用户已领取
    const EALREADY_CLAIMED: u64 = 2;
    /// 错误码：空投未开始
    const EAIRDROP_NOT_STARTED: u64 = 4;
    /// 错误码：无效的分片ID
    const EINVALID_SHARD_ID: u64 = 5;
    /// 错误码：用户不在白名单中
    const ENOT_IN_WHITELIST: u64 = 6;

    /// 代币类型
    struct CBH_TOKEN has drop {}

    /// 空投分片对象
    #[allow(lint(coin_field))]
    struct AirdropShard has key, store {
        id: UID,
        shard_id: u64,
        claimed_addresses: vector<address>,
        amount_per_user: u64,
        remaining_tokens: Coin<CBH_TOKEN>
    }

    /// 空投管理对象
    struct Airdrop has key {
        id: UID,
        creator: address,
        total_amount: u64,
        amount_per_user: u64,
        start_time: u64,
        end_time: u64,
        total_shards: u64,
        whitelist_root: vector<u8>,
        is_active: bool,
        receivers: vector<address>
    }

    /// 分片ID事件
    struct ShardIdEvent has copy, drop {
        address: address,
        shard_id: u64,
        shard_object_id: ID
    }

    /// 接收者分片信息
    struct ReceiverShardInfo has copy, drop {
        receiver: address,
        shard_id: u64,
        shard_object_id: ID
    }

    /// 空投创建事件
    struct AirdropCreatedEvent has copy, drop {
        airdrop_id: ID,
        creator: address,
        total_amount: u64,
        amount_per_user: u64,
        start_time: u64,
        end_time: u64,
        total_shards: u64,
        whitelist_root: vector<u8>,
        receiver_shard_infos: vector<ReceiverShardInfo>
    }

    /// 模块初始化函数
    fun init(witness: CBH_TOKEN, ctx: &mut TxContext) {
        let (treasury_cap, metadata) = coin::create_currency(
            witness,
            TOKEN_DECIMALS,
            TOKEN_NAME,
            TOKEN_SYMBOL,
            TOKEN_DESCRIPTION,
            option::none<Url>(),
            ctx
        );
        transfer::public_transfer(metadata, tx_context::sender(ctx));
        transfer::public_transfer(treasury_cap, tx_context::sender(ctx));
    }

    /// 创建空投
    public entry fun create_airdrop(
        treasury_cap: &mut coin::TreasuryCap<CBH_TOKEN>,
        total_amount: u64,
        amount_per_user: u64,
        start_time: u64,
        end_time: u64,
        whitelist_root: vector<u8>,
        receivers: vector<address>,
        ctx: &mut TxContext
    ): ID {
        let creator = tx_context::sender(ctx);
        let total_shards = DEFAULT_SHARD_NUM;
        let amount_per_shard = total_amount / total_shards;

        // 创建主空投对象
        let airdrop = Airdrop {
            id: object::new(ctx),
            creator,
            total_amount,
            amount_per_user,
            start_time,
            end_time,
            total_shards,
            whitelist_root,
            is_active: true,
            receivers
        };
        let airdrop_id = object::id(&airdrop);

        // 创建分片并记录分片信息
        let i = 0;
        let receiver_shard_infos = vector::empty<ReceiverShardInfo>();
        let shard_object_ids = vector::empty<ID>();
        
        // 先创建所有分片
        while (i < total_shards) {
            let shard = AirdropShard {
                id: object::new(ctx),
                shard_id: i,
                claimed_addresses: vector::empty(),
                amount_per_user,
                remaining_tokens: coin::mint(treasury_cap, amount_per_shard, ctx)
            };
            let shard_id = object::id(&shard);
            vector::push_back(&mut shard_object_ids, shard_id);
            transfer::share_object(shard);
            i = i + 1;
        };

        // 计算每个接收者的分片信息
        let j = 0;
        let receivers_len = vector::length(&receivers);
        while (j < receivers_len) {
            let receiver = *vector::borrow(&receivers, j);
            let shard_id = calculate_shard_id(receiver, total_shards);
            let shard_object_id = *vector::borrow(&shard_object_ids, shard_id);
            
            let receiver_info = ReceiverShardInfo {
                receiver,
                shard_id,
                shard_object_id
            };
            vector::push_back(&mut receiver_shard_infos, receiver_info);
            j = j + 1;
        };

        // 发出创建事件
        event::emit(AirdropCreatedEvent {
            airdrop_id,
            creator,
            total_amount,
            amount_per_user,
            start_time,
            end_time,
            total_shards,
            whitelist_root,
            receiver_shard_infos
        });

        transfer::share_object(airdrop);
        airdrop_id
    }

    /// 计算用户应该使用的分片ID
    public fun calculate_shard_id(addr: address, total_shards: u64): u64 {
        let addr_bytes = bcs::to_bytes(&addr);
        let hash_bytes = blake2b256(&addr_bytes);
        let hash_value = vector::empty<u8>();
        let i = 0;
        while (i < 8) {
            vector::push_back(&mut hash_value, *vector::borrow(&hash_bytes, i));
            i = i + 1;
        };
        let value = blake2b256(&hash_value);
        let value_bytes = bcs::to_bytes(&value);
        let value_u64 = 0u64;
        let j = 0;
        while (j < 8) {
            value_u64 = (value_u64 << 8) | (*vector::borrow(&value_bytes, j) as u64);
            j = j + 1;
        };
        value_u64 % total_shards
    }

    /// 检查地址是否在接收者列表中
    fun is_receiver(airdrop: &Airdrop, addr: address): bool {
        let i = 0;
        let len = vector::length(&airdrop.receivers);
        while (i < len) {
            if (*vector::borrow(&airdrop.receivers, i) == addr) {
                return true
            };
            i = i + 1;
        };
        false
    }

    /// 领取空投
    public entry fun claim_airdrop(
        airdrop: &mut Airdrop,
        shard: &mut AirdropShard,
        sender: address,
        ctx: &mut TxContext
    ) {
        let now = tx_context::epoch(ctx);

        // 检查空投是否有效
        assert!(airdrop.is_active, EAIRDROP_ENDED);
        assert!(now >= airdrop.start_time, EAIRDROP_NOT_STARTED);
        assert!(now <= airdrop.end_time, EAIRDROP_ENDED);

        // 验证用户是否在接收者列表中
        assert!(is_receiver(airdrop, sender), ENOT_IN_WHITELIST);

        // 验证用户是否在正确的分片
        let expected_shard_id = calculate_shard_id(sender, airdrop.total_shards);
        assert!(expected_shard_id == shard.shard_id, EINVALID_SHARD_ID);

        // 验证用户是否已领取
        let i = 0;
        let len = vector::length(&shard.claimed_addresses);
        while (i < len) {
            assert!(*vector::borrow(&shard.claimed_addresses, i) != sender, EALREADY_CLAIMED);
            i = i + 1;
        };

        // 发放代币
        let claim_coin = coin::split(&mut shard.remaining_tokens, airdrop.amount_per_user, ctx);
        transfer::public_transfer(claim_coin, sender);
        vector::push_back(&mut shard.claimed_addresses, sender);
    }

    /// 结束空投
    public entry fun end_airdrop(
        airdrop: &mut Airdrop,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == airdrop.creator, 0);
        airdrop.is_active = false;
    }

    /// 铸造代币函数
    public entry fun mint(
        treasury_cap: &mut coin::TreasuryCap<CBH_TOKEN>,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext
    ) {
        let coin = coin::mint(treasury_cap, amount, ctx);
        transfer::public_transfer(coin, recipient);
    }

    /// 批量铸造代币函数
    public entry fun mint_batch(
        treasury_cap: &mut coin::TreasuryCap<CBH_TOKEN>,
        amounts: vector<u64>,
        recipients: vector<address>,
        ctx: &mut TxContext
    ) {
        assert!(vector::length(&amounts) == vector::length(&recipients), 0);
        let i = 0;
        let len = vector::length(&amounts);
        while (i < len) {
            let amount = vector::borrow(&amounts, i);
            let recipient = vector::borrow(&recipients, i);
            let coin = coin::mint(treasury_cap, *amount, ctx);
            transfer::public_transfer(coin, *recipient);
            i = i + 1;
        };
    }

    /// 获取地址对应的分片ID
    public fun get_shard_id_for_address(airdrop: &Airdrop, addr: address): u64 {
        calculate_shard_id(addr, airdrop.total_shards)
    }

    /// 外部调用获取分片ID的入口函数
    public entry fun get_shard_id(airdrop: &Airdrop, shard: &AirdropShard, addr: address, ctx: &mut TxContext) {
        let shard_id = get_shard_id_for_address(airdrop, addr);
        assert!(shard_id == shard.shard_id, EINVALID_SHARD_ID);
        event::emit(ShardIdEvent {
            address: addr,
            shard_id,
            shard_object_id: object::id(shard)
        });
    }
} 