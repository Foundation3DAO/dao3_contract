module dao3_contract::dao {
    use std::string;
    use std::option;

    use sui::object::{Self, ID, UID};
    use sui::balance::Balance;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::table::{Self, Table};

    use dao3_contract::daocoin::{Self, DaoCoinAdminCap};

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

    struct DAO has key, store {
        id: UID,
        dao_admin_cap: DAOAdminCap,
        name: string::String,
    }

    /// global DAO info of the specified token type `Token`.
    struct SharedDaoProposalInfo has key {
        id: UID,
        proposals: Table<ID, u8>,
    }

    /// Configuration of the `Token`'s DAO.
    struct SharedDaoConfig has key {
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
    struct Proposal<Action: store> has key {
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
    struct Vote has key {
        id: UID,
        /// vote for the proposal under the `proposer`.
        proposer: address,
        /// how many tokens voted.
        votes: u256,
        /// vote for or vote against.
        accept: bool,
    }

    // plugin function, can only be called by token issuer.
    /// Any token who wants to has gov functionality
    /// can optin this module by call this `register function`.
    public entry fun plugin (
        admin_cap: DaoCoinAdminCap,
        name: vector<u8>,
        voting_delay: u64,
        voting_period: u64,
        voting_quorum_rate: u8,
        min_action_delay: u64,
        ctx: &mut TxContext
    ) {
        let new_dao = DAO {
            id: object::new(ctx),
            name: string::utf8(name),
            dao_admin_cap: DAOAdminCap {},
        };
        transfer::share_object(new_dao);

        let gov_info = SharedDaoProposalInfo {
            id: object::new(ctx),
            proposals: table::new(ctx)
        };
        transfer::share_object(gov_info);

        let config = new_dao_config(
            voting_delay,
            voting_period,
            voting_quorum_rate,
            min_action_delay,
            ctx
        );
        transfer::share_object(config);
        transfer::public_transfer(admin_cap, tx_context::sender(ctx))
    }

    public fun new_dao_config(
        voting_delay: u64,
        voting_period: u64,
        voting_quorum_rate: u8,
        min_action_delay: u64,
        ctx: &mut TxContext
    ): SharedDaoConfig {
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

        test_scenario::next_tx(scenario, admin);
        {
            daocoin::init_for_testing(test_scenario::ctx(scenario));
        };

        test_scenario::next_tx(scenario, admin);
        {
            let adminCap = test_scenario::take_from_sender<DaoCoinAdminCap>(scenario);
            plugin(adminCap, b"hello_world_dao", 60 * 1000, 60 * 60 * 1000, 4, 60 * 60 * 1000, test_scenario::ctx(scenario));
        };

        test_scenario::end(scenario_val);
    }
}