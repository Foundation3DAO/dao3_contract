module dao3_contract::dao {
    use sui::object::{Self, UID};
    use sui::balance::{Self, Balance};
    use sui::transfer;
    use sui::tx_context::{TxContext};
    use std::string::{Self, String};
    use sui::table::{Self, Table};
    use sui::test_scenario::Self;
    use sui::sui::{Self, SUI};

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
        balances: Table<String, Balance<T>>,
        name: String,
    }

    public entry fun create_dao<T>(name: vector<u8>, ctx: &mut TxContext) {
        transfer::share_object(DAO<T> {
            id: object::new(ctx),
            name: string::utf8(name),
            dao_admin_cap: DAOAdminCap {},
            balances: table::new(ctx)
        })
    }

    #[test]
    public fun test_create_dao() {
        let admin = @0xABBA; // needed only to initialize "state of the world"

        let scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;
        {
            create_dao<SUI>(b"hello_world_dao", test_scenario::ctx(scenario));
        };

        test_scenario::end(scenario_val);
    }
}