module dao3_contract::dao {
    use std::string;
    use std::option;

    use sui::object::{Self, UID};
    use sui::balance::Balance;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::table::{Self, Table};

    use dao3_contract::daocoin::DaoCoinAdminCap;

    /// Proposal state
    const PENDING: u8 = 1;
    const ACTIVE: u8 = 2;
    const REJECTED: u8 = 3;
    const ACCEPTED: u8 = 4;
    const QUEUED: u8 = 5;
    const EXECUTABLE: u8 = 6;
    const FULFILLED: u8 = 7;

    const ERR_NOT_AUTHORIZED: u64 = 1401;
    const ERR_ACTION_DELAY_TOO_SMALL: u64 = 1402;
    const ERR_PROPOSAL_STATE_INVALID: u64 = 1403;
    const ERR_PROPOSAL_ID_MISMATCH: u64 = 1404;
    const ERR_PROPOSER_MISMATCH: u64 = 1405;
    const ERR_QUORUM_RATE_INVALID: u64 = 1406;
    const ERR_CONFIG_PARAM_INVALID: u64 = 1407;
    const ERR_VOTE_STATE_MISMATCH: u64 = 1408;
    const ERR_ACTION_MUST_EXIST: u64 = 1409;
    const ERR_VOTED_OTHERS_ALREADY: u64 = 1410;

    struct DAOAdminCap has store, drop {}

    struct DAO<phantom T> has key, store {
        id: UID,
        dao_admin_cap: DAOAdminCap,
        treasury: Table<string::String, Balance<T>>,
        name: string::String,
    }

    /// global DAO info of the specified token type `Token`.
    struct SharedDaoProposalInfo<phantom Token: key + store> has key {
        id: UID,
        /// next proposal id.
        next_proposal_id: u64
    }

    /// Configuration of the `Token`'s DAO.
    struct SharedDaoConfig<phantom TokenT: key + store> has key {
        id: UID,
        /// after proposal created, how long use should wait before he can vote.
        voting_delay: u64,
        /// how long the voting window is.
        voting_period: u64,
        /// the quorum rate to agree on the proposal.
        /// if 50% votes needed, then the voting_quorum_rate should be 50.
        /// it should between (0, 100].
        voting_quorum_rate: u8,
        /// how long the proposal should wait before it can be executed.
        min_action_delay: u64,
    }


    /// Proposal data struct.
    struct Proposal<phantom Token: key + store, Action: store> has key {
        id: UID,
        /// creator of the proposal
        proposer: address,
        /// when voting begins.
        start_time: u64,
        /// when voting ends.
        end_time: u64,
        /// count of votes for agree.
        for_votes: u256,
        /// count of votes for againest.
        against_votes: u256,
        /// executable after this time.
        eta: u64,
        /// after how long, the accepted proposal can be executed.
        action_delay: u64,
        /// how many votes to reach to make the proposal pass.
        quorum_votes: u256,
        /// proposal action.
        action: option::Option<Action>,
    }

    /// User vote info.
    struct Vote<phantom TokenT: key + store> has key {
        id: UID,
        /// vote for the proposal under the `proposer`.
        proposer: address,
        /// how many tokens voted.
        votes: u256,
        /// vote for or vote against.
        accept: bool,
    }


    public entry fun create_dao<T>(name: vector<u8>, ctx: &mut TxContext) {
        let new_dao = DAO<T> {
            id: object::new(ctx),
            name: string::utf8(name),
            dao_admin_cap: DAOAdminCap {},
            treasury: table::new(ctx)
        };
        transfer::share_object(new_dao);
    }

    // plugin function, can only be called by token issuer.
    /// Any token who wants to has gov functionality
    /// can optin this module by call this `register function`.
    public entry fun plugin<TokenT: key + store>(
        admin_cap: DaoCoinAdminCap,
        voting_delay: u64,
        voting_period: u64,
        voting_quorum_rate: u8,
        min_action_delay: u64,
        ctx: &mut TxContext
    ) {
        let gov_info = SharedDaoProposalInfo<TokenT> {
            id: object::new(ctx),
            next_proposal_id: 0,
        };
        transfer::share_object(gov_info);

        let config = new_dao_config<TokenT>(
            voting_delay,
            voting_period,
            voting_quorum_rate,
            min_action_delay,
            ctx
        );
        transfer::share_object(config);
        transfer::public_transfer(admin_cap, tx_context::sender(ctx))
    }

    public fun new_dao_config<TokenT: key + store>(
        voting_delay: u64,
        voting_period: u64,
        voting_quorum_rate: u8,
        min_action_delay: u64,
        ctx: &mut TxContext
    ): SharedDaoConfig<TokenT> {
        assert!(voting_delay > 0, ERR_CONFIG_PARAM_INVALID);
        assert!(voting_period > 0, ERR_CONFIG_PARAM_INVALID);
        assert!(voting_quorum_rate > 0 && voting_quorum_rate <= 100, ERR_CONFIG_PARAM_INVALID);
        assert!(min_action_delay > 0, ERR_CONFIG_PARAM_INVALID);
        SharedDaoConfig { id: object::new(ctx), voting_delay, voting_period, voting_quorum_rate, min_action_delay }
    }

    #[test]
    public fun test_create_dao() {
        use sui::test_scenario;
        use sui::sui::{Self};

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
            // assert!(table::length(&dao_val.treasury) == 1, 2);
            // assert!(table::contains(&dao_val.treasury, string::utf8(b"sui")), 3);
            // assert!(!table::contains(&dao_val.treasury, string::utf8(b"suis")), 4);
            // assert!(balance::value(table::borrow(&dao_val.treasury, string::utf8(b"sui"))) == 1000 , 5);
            test_scenario::return_shared(dao_val);
        };

        test_scenario::end(scenario_val);
    }
}