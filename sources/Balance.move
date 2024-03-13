module BalanceAt::Balance{
    use std::coin;
    use std::error;
    use std::event;
    use std::account;
    use std::aptos_account;
    use std::aptos_coin::{AptosCoin, Self};
    use std::resource_account;
    use std::signer;
    use std::simple_map::{Self, SimpleMap};
    use std::vector;

    /// resource is not initialized yet
    const E_UNINITIALIZED:u64 = 1;
    /// signer is not owner
    const E_NOT_OWNER:u64 = 2;
    /// client is not whitelisted
    const E_CLIENT_NOT_WHITELISTED:u64 = 3;
    /// client is already whitelisted
    const E_CLIENT_ALREADY_WHITELISTED:u64 = 4;
    /// signer has insufficient balance
    const E_INSUFFICIENT_BALANCE:u64 = 5;

    struct WhiteList has key {
        balance_map: SimpleMap<address, u64>,
        signer_cap: account::SignerCapability
    }

    #[event]
    struct Deposited has drop, store {
        deposited_by: address,
        amount: u64
    }

    #[event]
    struct Withdrawn has drop, store {
        withdrawn_by: address,
        amount: u64
    }

    #[event]
    struct Whitelisted has drop, store {
        client_added: address
    }

    #[event]
    struct RemovedFromWhitelist has drop, store {
        client_removed: address
    }

    fun assert_is_owner(account_address: address){
        assert!(account_address==@Origin, error::permission_denied(E_NOT_OWNER));
    }

    fun assert_initialized() {
        assert!(exists<WhiteList>(@BalanceAt), error::invalid_state(E_UNINITIALIZED));
    }

    #[view]
    public fun is_whitelisted(client: address):bool acquires WhiteList {
        let white_list = borrow_global<WhiteList>(@BalanceAt);
        simple_map::contains_key(&white_list.balance_map, &client)
    }

    #[view]
    public fun get_balance(client: address):u64 acquires WhiteList {
        assert!(is_whitelisted(client), error::not_found(E_CLIENT_NOT_WHITELISTED));

        let white_list = borrow_global<WhiteList>(@BalanceAt);
        *simple_map::borrow(&white_list.balance_map, &client)
    }

    fun init_module(resource_signer: &signer){
        let signer_cap = resource_account::retrieve_resource_account_cap(resource_signer, @Origin);

        move_to<WhiteList>(resource_signer, WhiteList{
            balance_map: simple_map::new(),
            signer_cap
        });
    }

    public entry fun add_to_whitelist(account: &signer, client: address) acquires WhiteList {
        assert_is_owner(signer::address_of(account));
        assert_initialized();       
        assert!(!is_whitelisted(client), error::already_exists(E_CLIENT_ALREADY_WHITELISTED));

        simple_map::add(&mut borrow_global_mut<WhiteList>(@BalanceAt).balance_map, client, 0);
        event::emit<Whitelisted>(Whitelisted{
            client_added: client
        });
    }

    public entry fun add_many_to_whitelist(account: &signer, clients: vector<address>) acquires WhiteList {
        assert_is_owner(signer::address_of(account));
        assert_initialized();

        let white_list = borrow_global_mut<WhiteList>(@BalanceAt);
        while(!vector::is_empty(&clients)){
            let client = vector::pop_back(&mut clients);
            assert!(!simple_map::contains_key(&white_list.balance_map, &client), error::already_exists(E_CLIENT_ALREADY_WHITELISTED));

            simple_map::add(&mut white_list.balance_map, client, 0);
            event::emit<Whitelisted>(Whitelisted{
                client_added: client
            });
        };
    }

    public entry fun remove_from_whitelist(account: &signer, client: address) acquires WhiteList{
        let account_address = signer::address_of(account);
        assert_is_owner(account_address);
        assert_initialized();

        assert!(is_whitelisted(client), error::not_found(E_CLIENT_NOT_WHITELISTED));

        simple_map::remove(&mut borrow_global_mut<WhiteList>(@BalanceAt).balance_map, &client);
        event::emit<RemovedFromWhitelist>(RemovedFromWhitelist{
            client_removed: client
        });
    }

    public entry fun remove_many_from_whitelist(account: &signer, clients: vector<address>) acquires WhiteList {
        let account_address = signer::address_of(account);
        assert_is_owner(account_address);
        assert_initialized();

        let white_list = borrow_global_mut<WhiteList>(@BalanceAt);
        while(!vector::is_empty(&clients)){
            let client = vector::pop_back(&mut clients);
            assert!(simple_map::contains_key(&white_list.balance_map, &client), error::not_found(E_CLIENT_NOT_WHITELISTED));

            simple_map::remove(&mut white_list.balance_map, &client);
            event::emit<RemovedFromWhitelist>(RemovedFromWhitelist{
                client_removed: client
            }); 
        };
    }

    public entry fun deposit(client: &signer, amount: u64) acquires WhiteList {
        let client_address = signer::address_of(client);
        assert!(is_whitelisted(client_address), error::not_found(E_CLIENT_NOT_WHITELISTED));

        let client_balance = coin::balance<AptosCoin>(client_address);
        assert!(client_balance >= amount, error::invalid_argument(E_INSUFFICIENT_BALANCE));
        aptos_account::transfer(client, @BalanceAt, amount);

        let balance = simple_map::borrow_mut(&mut borrow_global_mut<WhiteList>(@BalanceAt).balance_map, &client_address);
        *balance = *balance + amount;

        event::emit(Deposited {
            deposited_by: client_address,
            amount
        });
    }
    
    public entry fun withdraw(client: &signer, amount: u64) acquires WhiteList {
        let client_address = signer::address_of(client);
        assert!(is_whitelisted(client_address), error::not_found(E_CLIENT_NOT_WHITELISTED));

        let white_list = borrow_global_mut<WhiteList>(@BalanceAt);

        let client_balance = simple_map::borrow_mut(&mut white_list.balance_map, &client_address);
        assert!(*client_balance >= amount, error::invalid_argument(E_INSUFFICIENT_BALANCE));
        *client_balance = *client_balance - amount;

        let resource_signer = account::create_signer_with_capability(&white_list.signer_cap);
        aptos_account::transfer(&resource_signer, client_address, amount);

        event::emit(Withdrawn {
            withdrawn_by: client_address,
            amount
        });
    }

    #[test_only]
    fun test_setup(origin: &signer, aptos_framework: &signer){
        let origin_address = signer::address_of(origin);
        let resource_address = account::create_resource_address(&origin_address, x"01");

        let resource_signer = account::create_account_for_test(resource_address);
        account::create_account_for_test(origin_address);
        resource_account::create_resource_account(origin, x"01", vector::empty());
        let (burn_cap, mint_cap) = aptos_framework::aptos_coin::initialize_for_test(aptos_framework);
        init_module(&resource_signer);

        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(origin = @Origin, aptos_framework = @0x1)]
    fun test_balance(origin: &signer, aptos_framework: &signer) acquires WhiteList {
        test_setup(origin, aptos_framework);
        assert!(exists<WhiteList>(@BalanceAt), error::invalid_state(E_UNINITIALIZED));

        let client1 = account::create_account_for_test(@0x45);
        let client2 = account::create_account_for_test(@0x46);

        // adding single client to whitelist
        let client1_address = signer::address_of(&client1);
        add_to_whitelist(origin, client1_address);
        assert!(simple_map::length(&borrow_global<WhiteList>(@BalanceAt).balance_map)==1, 9);
        assert!(event::was_event_emitted<Whitelisted>(&Whitelisted{
            client_added: client1_address
        }), 9);

        // removing single client from whitelist
        remove_from_whitelist(origin, client1_address);
        assert!(simple_map::length(&borrow_global<WhiteList>(@BalanceAt).balance_map)==0, 9);
        assert!(event::was_event_emitted<RemovedFromWhitelist>(&RemovedFromWhitelist{
            client_removed: client1_address
        }), 9);

        // adding multiple clients to whitelist
        let list_add = vector<address>[@0x11,@0x12,@0x13,@0x14,@0x15];
        add_many_to_whitelist(origin, list_add);
        assert!(simple_map::length(&borrow_global<WhiteList>(@BalanceAt).balance_map)==5, 9);

        // removing multiple clients from whitelist
        let list_remove = vector<address>[@0x13,@0x11,@0x15];
        remove_many_from_whitelist(origin, list_remove);
        assert!(simple_map::length(&borrow_global<WhiteList>(@BalanceAt).balance_map)==2, 9);

        // deposit funds
        let client2_address = signer::address_of(&client2);
        add_to_whitelist(origin, client2_address);
        assert!(simple_map::length(&borrow_global<WhiteList>(@BalanceAt).balance_map)==3, 9);
        
        coin::register<AptosCoin>(&client2);
        aptos_coin::mint(aptos_framework, client2_address,100);
        deposit(&client2, 80);
        assert!(get_balance(client2_address)==80,9);
        assert!(event::was_event_emitted<Deposited>(&Deposited{
            deposited_by: client2_address,
            amount: 80
        }), 9);

        // withdraw funds
        withdraw(&client2, 20);
        assert!(get_balance(client2_address)==60,9);
        assert!(event::was_event_emitted<Withdrawn>(&Withdrawn{
            withdrawn_by: client2_address,
            amount: 20
        }), 9); 
    }

    #[test(origin = @Origin, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 327682, location = Self)]
    fun test_add_client_fail_if_not_owner(origin: &signer, aptos_framework: &signer) acquires WhiteList {
        test_setup(origin, aptos_framework);

        let user = account::create_account_for_test(@0x21);
        add_to_whitelist(&user, @0x22);
    }

    #[test(origin = @Origin, aptos_framework = @0x1)]
    fun test_add_client(origin: &signer, aptos_framework: &signer) acquires WhiteList {
        test_setup(origin, aptos_framework);
        
        let client = @0x22;
        add_to_whitelist(origin, client);
        assert!(is_whitelisted(client), error::not_found(E_CLIENT_NOT_WHITELISTED));
    }

    #[test(origin = @Origin, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 393219, location = Self)]
    fun test_remove_client_fail_if_not_whitelisted(origin: &signer, aptos_framework: &signer) acquires WhiteList {
        test_setup(origin, aptos_framework);

        remove_from_whitelist(origin, @0x22);
    }

    #[test(origin = @Origin, aptos_framework = @0x1)]
    fun test_remove_client(origin: &signer, aptos_framework: &signer) acquires WhiteList {
        test_setup(origin, aptos_framework);
        
        let client = @0x22;
        add_to_whitelist(origin, client);
        assert!(is_whitelisted(client), error::not_found(E_CLIENT_NOT_WHITELISTED));

        remove_from_whitelist(origin, client);
        assert!(!is_whitelisted(client), error::not_implemented(1));
    }

    #[test(origin = @Origin, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 393219, location = Self)]
    fun test_deposit_fail_if_not_whitelisted(origin: &signer, aptos_framework: &signer) acquires WhiteList {
        test_setup(origin, aptos_framework);
        
        let user = account::create_account_for_test(@0x22);
        assert!(!is_whitelisted(signer::address_of(&user)), error::not_implemented(1));

        coin::register<AptosCoin>(&user);
        aptos_coin::mint(aptos_framework, signer::address_of(&user), 100);
        deposit(&user, 40);
    }

    #[test(origin = @Origin, aptos_framework = @0x1)]
    fun test_deposit(origin: &signer, aptos_framework: &signer) acquires WhiteList {
        test_setup(origin, aptos_framework);
        
        let user = account::create_account_for_test(@0x22);
        let user_address = signer::address_of(&user);
        add_to_whitelist(origin, user_address);
        assert!(is_whitelisted(user_address), error::not_found(E_CLIENT_NOT_WHITELISTED));

        coin::register<AptosCoin>(&user);
        aptos_coin::mint(aptos_framework, user_address, 100);
        deposit(&user, 40);
        assert!(get_balance(user_address)==40, error::internal(2));
    }
}