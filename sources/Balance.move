module BalanceAt::Balance{
    use std::coin;
    use std::debug::print;
    use std::account;
    use std::aptos_account;
    use std::aptos_coin::{AptosCoin};
    use std::resource_account;
    use std::signer;
    use std::simple_map::{Self, SimpleMap};
    use std::vector;

    // errors
    const E_ALREADY_INITIALIZED:u64 = 0;
    const E_UNINITIALIZED:u64 = 1;
    const E_NOT_OWNER:u64 = 2;
    const E_CLIENT_NOT_WHITELISTED:u64 = 3;
    const E_CLIENT_ALREADY_WHITELISTED:u64 = 4;
    const E_INSUFFICIENT_BALANCE:u64 = 5;

    struct WhiteList has key {
        balance_map: SimpleMap<address, u64>,
        signer_cap: account::SignerCapability
    }

    fun assert_is_owner(account_address: address){
        assert!(account_address==@Origin, E_NOT_OWNER);
    }

    fun assert_initialized() {
        assert!(exists<WhiteList>(@BalanceAt), E_UNINITIALIZED);
    }

    #[view]
    public fun is_whitelisted(client: address):bool acquires WhiteList {
        let white_list = borrow_global<WhiteList>(@BalanceAt);
        simple_map::contains_key(&white_list.balance_map, &client)
    }

    #[view]
    public fun get_balance(client: address):u64 acquires WhiteList {
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
        assert!(!is_whitelisted(client), E_CLIENT_ALREADY_WHITELISTED);

        simple_map::add(&mut borrow_global_mut<WhiteList>(@BalanceAt).balance_map, client, 0);
    }

    public entry fun add_many_to_whitelist(account: &signer, clients: vector<address>) acquires WhiteList {
        assert_is_owner(signer::address_of(account));
        assert_initialized();

        let white_list = borrow_global_mut<WhiteList>(@BalanceAt);
        while(!vector::is_empty(&clients)){
            let client = vector::pop_back(&mut clients);
            assert!(!simple_map::contains_key(&white_list.balance_map, &client), E_CLIENT_ALREADY_WHITELISTED);

            simple_map::add(&mut white_list.balance_map, client, 0);
        };
    }

    public entry fun remove_from_whitelist(account: &signer, client: address) acquires WhiteList{
        let account_address = signer::address_of(account);
        assert_is_owner(account_address);
        assert_initialized();

        assert!(is_whitelisted(client), E_CLIENT_NOT_WHITELISTED);

        simple_map::remove(&mut borrow_global_mut<WhiteList>(@BalanceAt).balance_map, &client);   
    }

    public entry fun remove_many_from_whitelist(account: &signer, clients: vector<address>) acquires WhiteList {
        let account_address = signer::address_of(account);
        assert_is_owner(account_address);
        assert_initialized();

        let white_list = borrow_global_mut<WhiteList>(@BalanceAt);
        while(!vector::is_empty(&clients)){
            let client = vector::pop_back(&mut clients);
            assert!(simple_map::contains_key(&white_list.balance_map, &client), E_CLIENT_NOT_WHITELISTED);

            simple_map::remove(&mut white_list.balance_map, &client);   
        };
    }

    public entry fun deposit(client: &signer, amount: u64) acquires WhiteList {
        let client_address = signer::address_of(client);
        assert!(is_whitelisted(client_address), E_CLIENT_NOT_WHITELISTED);

        let client_balance = coin::balance<AptosCoin>(client_address);
        assert!(client_balance >= amount, E_INSUFFICIENT_BALANCE);
        aptos_account::transfer(client, @BalanceAt, amount);

        let balance = simple_map::borrow_mut(&mut borrow_global_mut<WhiteList>(@BalanceAt).balance_map, &client_address);
        *balance = *balance + amount;
    }
    
    public entry fun withdraw(client: &signer, amount: u64) acquires WhiteList {
        let client_address = signer::address_of(client);
        assert!(is_whitelisted(client_address), E_CLIENT_NOT_WHITELISTED);

        let white_list = borrow_global_mut<WhiteList>(@BalanceAt);

        let client_balance = simple_map::borrow_mut(&mut white_list.balance_map, &client_address);
        assert!(*client_balance >= amount, E_INSUFFICIENT_BALANCE);
        *client_balance = *client_balance - amount;

        let resource_signer = account::create_signer_with_capability(&white_list.signer_cap);
        aptos_account::transfer(&resource_signer, client_address, amount);
    }

    #[test_only]
    public fun test_setup(resource_acc: &signer, origin: &signer, aptos_framework: &signer){
        account::create_account_for_test(signer::address_of(origin));
        resource_account::create_resource_account(origin, vector[1u8,2u8,3u8,4], vector::empty());
        let (burn_cap, mint_cap) = aptos_framework::aptos_coin::initialize_for_test(aptos_framework);
        init_module(resource_acc);


        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test(resource_account=@BalanceAt,origin=@Origin,aptos_framework=@0x1)]
    public fun test_balance(resource_account: &signer, origin: &signer, aptos_framework: &signer)
    //  acquires WhiteList
      {
        
        test_setup(resource_account, origin, aptos_framework);
        assert!(exists<WhiteList>(@BalanceAt), 9);


        // let stored_at = signer::address_of(resource_account);
        // print(&stored_at);
        // let client1 = account::create_account_for_test(@0x45);
        // let client2 = account::create_account_for_test(@0x46);
        
        // // initialization
        // initialize(account);
        // assert!(exists<WhiteList>(stored_at), 9);

        // // adding single client to whitelist
        // add_to_whitelist(account, signer::address_of(&client1));
        // assert!(simple_map::length(&borrow_global<WhiteList>(stored_at).balance_map)==1, 9);

        // // removing single client from whitelist
        // remove_from_whitelist(account, signer::address_of(&client1));
        // assert!(simple_map::length(&borrow_global<WhiteList>(stored_at).balance_map)==0, 9);

        // // adding multiple clients to whitelist
        // let list_add = vector<address>[@0x11,@0x12,@0x13,@0x14,@0x15];
        // add_many_to_whitelist(account, list_add);
        // assert!(simple_map::length(&borrow_global<WhiteList>(stored_at).balance_map)==5, 9);

        // // removing multiple clients from whitelist
        // let list_remove = vector<address>[@0x13,@0x11,@0x15];
        // remove_many_from_whitelist(account, list_remove);
        // assert!(simple_map::length(&borrow_global<WhiteList>(stored_at).balance_map)==2, 9);

        // // deposit
        // let client2_address = signer::address_of(&client2);
        // add_to_whitelist(account, client2_address);
        // assert!(simple_map::length(&borrow_global<WhiteList>(stored_at).balance_map)==3, 9);
        
        // coin::register<AptosCoin>(&client2);
        // aptos_coin::mint(aptos_framework, client2_address,100);
        // deposit(account, &client2, 80);
        // assert!(get_balance(stored_at, client2_address)==80,9);

        // // withdraw
        // withdraw(account, &client2, 20);
        // assert!(get_balance(stored_at, client2_address)==60,9);

       
    }
}