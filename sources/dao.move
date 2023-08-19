module dao3_contract::dao {
    use sui::object::{Self, UID};
    use sui::balance::{Self, Balance};
    use sui::transfer;
    use sui::tx_context::{TxContext};
    use std::string;
    use sui::table::{Self, Table};
    use sui::test_scenario::Self;
    use sui::sui::{Self};

    /// Proposal state
    const PENDING: u8 = 1;
    const ACTIVE: u8 = 2;
    const REJECTED: u8 = 3;
    const ACCEPTED: u8 = 4;
    const QUEUED: u8 = 5;
    const EXECUTABLE: u8 = 6;
    const FULFILLED: u8 = 7;

    struct DAOAdminCap has store {}

    struct DAO<phantom T> has key, store {
        id: UID,
        dao_admin_cap: DAOAdminCap,
        treasury: Table<string::String, Balance<T>>,
        name: string::String,
    }

    public entry fun create_dao<T>(name: vector<u8>, ctx: &mut TxContext) {
        let new_dao = DAO<T> {
            id: object::new(ctx),
            name: string::utf8(name),
            dao_admin_cap: DAOAdminCap {},
            treasury: table::new(ctx)
        };
        table::add(&mut new_dao.treasury, string::utf8(b"sui"),  balance::create_for_testing<T>(1000));
        transfer::share_object(new_dao);
    }

    #[test]
    public fun test_create_dao() {
        let admin = @0xABBA;

        let scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;
        {
            create_dao<sui::SUI>(b"hello_world_dao", test_scenario::ctx(scenario));
        };

        test_scenario::next_tx(scenario, admin);
        {
            let dao_val = test_scenario::take_shared<DAO<sui::SUI>>(scenario);
            
            assert!(dao_val.name == string::utf8(b"hello_world_dao"), 1);
            assert!(table::length(&dao_val.treasury) == 1, 2);
            assert!(table::contains(&dao_val.treasury, string::utf8(b"sui")), 3);
            assert!(!table::contains(&dao_val.treasury, string::utf8(b"suis")), 4);
            assert!(balance::value(table::borrow(&dao_val.treasury, string::utf8(b"sui"))) == 1000 , 5);
            test_scenario::return_shared(dao_val);
        };

        test_scenario::end(scenario_val);
    }
}