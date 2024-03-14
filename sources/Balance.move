module BalanceAt::Balance{
    use std::bls12381::{Signature, PublicKey, Self}; 
    use std::debug::print;
    use std::option::{Self, Option};
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
        assert!(!is_whitelisted(client), error::already_exists(E_CLIENT_ALREADY_WHITELISTED));

        simple_map::add(&mut borrow_global_mut<WhiteList>(@BalanceAt).balance_map, client, 0);
        event::emit<Whitelisted>(Whitelisted{
            client_added: client
        });
    }

    public entry fun add_many_to_whitelist(account: &signer, clients: vector<address>) acquires WhiteList {
        assert_is_owner(signer::address_of(account));

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
        assert!(is_whitelisted(client), error::not_found(E_CLIENT_NOT_WHITELISTED));

        simple_map::remove(&mut borrow_global_mut<WhiteList>(@BalanceAt).balance_map, &client);
        event::emit<RemovedFromWhitelist>(RemovedFromWhitelist{
            client_removed: client
        });
    }

    public entry fun remove_many_from_whitelist(account: &signer, clients: vector<address>) acquires WhiteList {
        let account_address = signer::address_of(account);
        assert_is_owner(account_address);

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

    // signature verification
    public fun verify_sig(signature: vector<u8>, public_key: vector<u8>, message: vector<u8>):bool {
        let is_valid = bls12381::verify_normal_signature(
            &bls12381::signature_from_bytes(signature), 
            &option::extract(&mut bls12381::public_key_from_bytes(public_key)), 
            message
        );
        is_valid
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
        assert!(simple_map::length(&borrow_global<WhiteList>(@BalanceAt).balance_map)==1, error::internal(1));
        assert!(event::was_event_emitted<Whitelisted>(&Whitelisted{
            client_added: client1_address
        }), error::not_implemented(2));

        // removing single client from whitelist
        remove_from_whitelist(origin, client1_address);
        assert!(simple_map::length(&borrow_global<WhiteList>(@BalanceAt).balance_map)==0, error::internal(1));
        assert!(event::was_event_emitted<RemovedFromWhitelist>(&RemovedFromWhitelist{
            client_removed: client1_address
        }), error::not_implemented(2));

        // adding multiple clients to whitelist
        let list_add = vector<address>[@0x11,@0x12,@0x13,@0x14,@0x15];
        add_many_to_whitelist(origin, list_add);
        assert!(simple_map::length(&borrow_global<WhiteList>(@BalanceAt).balance_map)==5, error::internal(1));

        // removing multiple clients from whitelist
        let list_remove = vector<address>[@0x13,@0x11,@0x15];
        remove_many_from_whitelist(origin, list_remove);
        assert!(simple_map::length(&borrow_global<WhiteList>(@BalanceAt).balance_map)==2, error::internal(1));

        // deposit funds
        let client2_address = signer::address_of(&client2);
        add_to_whitelist(origin, client2_address);
        assert!(simple_map::length(&borrow_global<WhiteList>(@BalanceAt).balance_map)==3, error::internal(1));
        
        coin::register<AptosCoin>(&client2);
        aptos_coin::mint(aptos_framework, client2_address,100);
        deposit(&client2, 80);
        assert!(get_balance(client2_address)==80, error::internal(3));
        assert!(event::was_event_emitted<Deposited>(&Deposited{
            deposited_by: client2_address,
            amount: 80
        }), error::not_implemented(2));

        // withdraw funds
        withdraw(&client2, 20);
        assert!(get_balance(client2_address)==60, error::internal(3));
        assert!(event::was_event_emitted<Withdrawn>(&Withdrawn{
            withdrawn_by: client2_address,
            amount: 20
        }), error::not_implemented(2)); 
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
    fun test_add_multiple_clients(origin: &signer, aptos_framework: &signer) acquires WhiteList {
        test_setup(origin, aptos_framework);
        
        let clients = vector<address>[@0x31,@0x32,@0x33];
        add_many_to_whitelist(origin, clients);
        assert!(simple_map::length(&borrow_global<WhiteList>(@BalanceAt).balance_map)==3, error::internal(1));
    }

    #[test(origin = @Origin, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 524292, location = Self)]
    fun test_add_client_fail_if_already_whitelisted(origin: &signer, aptos_framework: &signer) acquires WhiteList {
        test_setup(origin, aptos_framework);

        let client = @0x22;
        add_to_whitelist(origin, client);
        add_to_whitelist(origin, client);
    }

    #[test(origin = @Origin, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 327682, location = Self)]
    fun test_remove_client_fail_if_not_owner(origin: &signer, aptos_framework: &signer) acquires WhiteList {
        test_setup(origin, aptos_framework);
        
        add_to_whitelist(origin, @0x22);
        assert!(is_whitelisted(@0x22), error::not_found(E_CLIENT_NOT_WHITELISTED));
        
        let user = account::create_account_for_test(@0x21);
        remove_from_whitelist(&user, @0x22);
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
        assert!(!is_whitelisted(client), error::not_implemented(4));
    }

    #[test(origin = @Origin, aptos_framework = @0x1)]
    fun test_remove_multiple_clients(origin: &signer, aptos_framework: &signer) acquires WhiteList {
        test_setup(origin, aptos_framework);
        
        let clients_add = vector<address>[@0x31,@0x32,@0x33];
        add_many_to_whitelist(origin, clients_add);
        assert!(simple_map::length(&borrow_global<WhiteList>(@BalanceAt).balance_map)==3, error::internal(1));

        let clients_remove = vector<address>[@0x31,@0x33];
        remove_many_from_whitelist(origin, clients_remove);
        assert!(simple_map::length(&borrow_global<WhiteList>(@BalanceAt).balance_map)==1, error::internal(1));
    }

    #[test(origin = @Origin, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 393219, location = Self)]
    fun test_deposit_fail_if_not_whitelisted(origin: &signer, aptos_framework: &signer) acquires WhiteList {
        test_setup(origin, aptos_framework);
        
        let user = account::create_account_for_test(@0x22);
        assert!(!is_whitelisted(signer::address_of(&user)), error::not_implemented(4));

        coin::register<AptosCoin>(&user);
        aptos_coin::mint(aptos_framework, signer::address_of(&user), 100);
        deposit(&user, 40);
    }

    #[test(origin = @Origin, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 65541, location = Self)]
    fun test_deposit_fail_unsufficient_balance(origin: &signer, aptos_framework: &signer) acquires WhiteList {
        test_setup(origin, aptos_framework);
        
        let user = account::create_account_for_test(@0x22);
        let user_address = signer::address_of(&user);
        add_to_whitelist(origin, user_address);
        assert!(is_whitelisted(user_address), error::not_found(E_CLIENT_NOT_WHITELISTED));

        coin::register<AptosCoin>(&user);
        aptos_coin::mint(aptos_framework, signer::address_of(&user), 100);
        deposit(&user, 200);
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
        assert!(get_balance(user_address)==40, error::internal(3));
    }

    #[test(origin = @Origin, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 393219, location = Self)]
    fun test_withdraw_fail_if_not_whitelisted(origin: &signer, aptos_framework: &signer) acquires WhiteList {
        test_setup(origin, aptos_framework);
        
        let user = account::create_account_for_test(@0x22);
        withdraw(&user,20);
    }

    #[test(origin = @Origin, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 65541, location = Self)]
    fun test_withdraw_fail_unsufficient_balance(origin: &signer, aptos_framework: &signer) acquires WhiteList {
        test_setup(origin, aptos_framework);

        let user = account::create_account_for_test(@0x22);
        let user_address = signer::address_of(&user);
        add_to_whitelist(origin, user_address);
        assert!(is_whitelisted(user_address), error::not_found(E_CLIENT_NOT_WHITELISTED));

        coin::register<AptosCoin>(&user);
        aptos_coin::mint(aptos_framework, user_address, 100);
        deposit(&user, 40);
        assert!(get_balance(user_address)==40, error::internal(3));

        withdraw(&user, 50);
    }

    #[test(origin = @Origin, aptos_framework = @0x1)]
    fun test_withdraw(origin: &signer, aptos_framework: &signer) acquires WhiteList {
        test_setup(origin, aptos_framework);

        let user = account::create_account_for_test(@0x22);
        let user_address = signer::address_of(&user);
        add_to_whitelist(origin, user_address);
        assert!(is_whitelisted(user_address), error::not_found(E_CLIENT_NOT_WHITELISTED));

        coin::register<AptosCoin>(&user);
        aptos_coin::mint(aptos_framework, user_address, 100);
        deposit(&user, 40);
        assert!(get_balance(user_address)==40, error::internal(3));

        withdraw(&user, 40);
        assert!(get_balance(user_address)==0, error::internal(3));
    }

    // test signature verification
    #[test]
    public fun test_signature() {
        let signature = vector<u8>[128,201,160,126,35,212,230,128,78,144,5,254,254,83,192,186,93,17,60,49,98,107,221,46,170,204,157,195,232,5,210,22,183,22,119,71,25,36,62,16,0,206,203,107,17,123,119,203,23,161,28,159,150,189,173,177,104,165,159,13,37,169,57,45,98,98,201,242,29,245,111,185,190,243,7,226,26,194,201,199,220,54,147,222,177,243,159,236,106,1,107,200,116,114,195,111];
        let pub_key = vector<u8>[182,66,53,211,4,186,224,64,62,231,162,102,99,204,196,203,21,28,138,169,84,85,72,205,20,239,105,158,36,181,14,179,196,129,43,79,191,111,13,252,24,159,217,9,230,177,171,166];
        let mssg = vector<u8>[1,2,3,4];
        let is_valid = verify_sig(signature, pub_key, mssg);
        // print(&is_valid);
        assert!(is_valid, 9);
    }
}