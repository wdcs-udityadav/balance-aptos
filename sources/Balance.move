module BalanceAt::Balance{
    use std::coin;
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
}