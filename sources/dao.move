module dao3_contract::dao {
    use std::string::{Self, String};
    use std::vector;

    use sui::address;
    use sui::coin::{Self, Coin};
    use sui::event;
    use sui::object::{Self, ID, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::table::{Self, Table};
    use sui::clock::{Self, Clock};

    use dao3_contract::daocoin::{Self, DaoCoinAdminCap, DaoCoinStorage, mint_with_proposal};

    const BLACK_HOLE: address = @0x0;

    // Proposal state
    const PENDING: u8 = 1;
    const ACTIVE: u8 = 2;
    const REJECTED: u8 = 3;
    const ACCEPTED: u8 = 4;
    const QUEUED: u8 = 5;
    const EXECUTABLE: u8 = 6;
    const FULFILLED: u8 = 7;

    const CREATE: u8 = 1;

    const WITHDRAW_ACTION: vector<u8> = b"withdraw";

    const ERR_NOT_AUTHORIZED: u64 = 101;
    const ERR_ACTION_DELAY_TOO_SMALL: u64 = 102;
    const ERR_PROPOSAL_STATE_INVALID: u64 = 103;
    const ERR_PROPOSAL_ID_MISMATCH: u64 = 104;
    const ERR_PROPOSER_MISMATCH: u64 = 105;
    const ERR_QUORUM_RATE_INVALID: u64 = 106;
    const ERR_CONFIG_PARAM_INVALID: u64 = 107;
    const ERR_VOTE_STATE_MISMATCH: u64 = 108;
    const ERR_ACTION_MUST_EXIST: u64 = 109;
    const ERR_VOTED_OTHERS_ALREADY: u64 = 110;
    const ERR_ZERO_COIN: u64 = 111;
    const ERR_NEGATIVE_AMOUNT: u64 = 112;
    const ERR_NO_RECEIVER: u64 = 113;

    struct DAOAdminCap has store, drop {}

    struct DAO has key, store {
        id: UID,
        dao_admin_cap: DAOAdminCap,
        name: String,
    }

    // users can get proposals' state from this table.
    struct SharedDaoVotingMachine has key {
        id: UID,
        proposals: Table<ID, u8>,
    }

    // Configuration of the `Token`'s DAO.
    struct SharedDaoConfig has key {
        id: UID,
        // after proposal created, how long use should wait before he can vote.
        voting_delay: u64,
        // how long the voting window is.
        voting_period: u64,
        // the quorum rate to agree on the proposal.
        // if 50% votes needed, then the voting_quorum_rate should be 50.
        // it should between (0, 100].
        voting_quorum_rate: u8,
        // how long the proposal should wait before it can be executed.
        min_action_delay: u64,
    }

    struct MintAction has store {}

    // Proposal data struct.
    struct Proposal has key {
        id: UID,
        // creator of the proposal
        proposer: address,
        // when voting begins.
        start_time: u64,
        // when voting ends.
        end_time: u64,
        // count of votes for agree.
        for_votes: u64,
        // count of votes for againest.
        against_votes: u64,
        // executable after this time.
        eta: u64,
        // after how long, the accepted proposal can be executed.
        action_delay: u64,
        // how many votes to reach to make the proposal pass.
        quorum_votes: u64,
        // proposal action.
        action: vector<u8>,
        // consistent with state in the voting machine's proposals table
        propsal_state: u8,
        // check if an address voted or not
        voters: Table<address, bool>,
        // how much the proposal grants
        amount: u64,
        // receive the money the accepted proposal grants  
        receiver: vector<u8>,
    }

    struct ProposalEvent has copy, drop {
        operation: u8,
        id: ID,
    }

    // register function, can only be called once by the token issuer.
    public entry fun register (
        admin_cap: DaoCoinAdminCap,
        name: vector<u8>,
        voting_delay: u64,
        voting_period: u64,
        voting_quorum_rate: u8,
        min_action_delay: u64,
        ctx: &mut TxContext
    ) {
        assert!(vector::length(&name) > 0, ERR_CONFIG_PARAM_INVALID);
        let new_dao = DAO {
            id: object::new(ctx),
            name: string::utf8(name),
            dao_admin_cap: DAOAdminCap {},
        };
        transfer::share_object(new_dao);

        let shared_voting_machine = SharedDaoVotingMachine {
            id: object::new(ctx),
            proposals: table::new(ctx)
        };
        transfer::share_object(shared_voting_machine);

        let config = new_dao_config(
            voting_delay,
            voting_period,
            voting_quorum_rate,
            min_action_delay,
            ctx
        );
        transfer::share_object(config);
        transfer::public_transfer(admin_cap, BLACK_HOLE)
    }

    fun new_dao_config(
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

    public entry fun create_proposal<DAOCOIN>(
        propose_right: Coin<DAOCOIN>,
        config: &SharedDaoConfig,
        voting_machine: &mut SharedDaoVotingMachine,
        dao_coin_storage: &DaoCoinStorage,
        clock: &Clock,
        action: vector<u8>,
        amount: u64,
        receiver: vector<u8>,
        ctx: &mut TxContext
    ) {
        let b = coin::value(&propose_right);
        assert!(b > 0, ERR_ZERO_COIN);
        assert!(amount >= 0, ERR_NEGATIVE_AMOUNT);
        if (action == WITHDRAW_ACTION && amount == 0) {
            assert!(false, ERR_ZERO_COIN);
        };
        if (action == WITHDRAW_ACTION && vector::length(&receiver) == 0) {
            assert!(false, ERR_NO_RECEIVER);
        };
        
        let rate = (config.voting_quorum_rate as u64);
        let eta = 0;
        if (vector::length<u8>(&action) > 0) {
            eta = clock::timestamp_ms(clock) + config.voting_delay + config.voting_period + config.min_action_delay;
        };
        let proposal = Proposal {
            id: object::new(ctx),
            proposer: tx_context::sender(ctx),
            start_time: clock::timestamp_ms(clock) + config.voting_delay,
            end_time: clock::timestamp_ms(clock) + config.voting_delay + config.voting_period,
            for_votes: 0,
            against_votes: 0,
            eta,
            action_delay: config.min_action_delay,
            quorum_votes: daocoin::total_supply_for_proposal(dao_coin_storage) * rate / 100,
            action,
            propsal_state: PENDING,
            voters: table::new(ctx),
            amount,
            receiver
        };
        let id = object::uid_to_inner(&proposal.id);
        event::emit( ProposalEvent {
            operation: CREATE,
            id
        });
        table::add(&mut voting_machine.proposals, object::uid_to_inner(&proposal.id), PENDING);
        transfer::share_object(proposal);
        transfer::public_transfer(propose_right, tx_context::sender(ctx));
    }
    
    public fun proposal_state(proposal: &Proposal): u8 {
        proposal.propsal_state
    }

    public entry fun vote_for_proposal<DAOCOIN>(
        voting_right: Coin<DAOCOIN>,
        proposal: &mut Proposal,
        for: bool,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(proposal.end_time >= clock::timestamp_ms(clock), ERR_PROPOSAL_STATE_INVALID);
        assert!(proposal.start_time <= clock::timestamp_ms(clock), ERR_PROPOSAL_STATE_INVALID);
        assert!(proposal.propsal_state == ACTIVE, ERR_PROPOSAL_STATE_INVALID);
        assert!(coin::value<DAOCOIN>(&voting_right) > 0, ERR_ZERO_COIN);

        if (for) {
            proposal.for_votes = proposal.for_votes + coin::value<DAOCOIN>(&voting_right);
        } else {
            proposal.against_votes = proposal.against_votes + coin::value<DAOCOIN>(&voting_right);
        };
        
        if (!table::contains(&proposal.voters, tx_context::sender(ctx))) {
            table::add(&mut proposal.voters, tx_context::sender(ctx) , true);
        };

        transfer::public_transfer(voting_right, tx_context::sender(ctx));
    }

    public entry fun trigger_proposal_state_change (
        voting_machine: &mut SharedDaoVotingMachine,
        proposal: &mut Proposal,
        clock: &Clock,
    ) {
        assert!(table::contains(&voting_machine.proposals, object::uid_to_inner(&proposal.id)), ERR_PROPOSAL_ID_MISMATCH);
        
        let current_time = clock::timestamp_ms(clock);
        let new_state;
        if (current_time < proposal.start_time) {
            new_state = PENDING;
        } else if (current_time <= proposal.end_time) {
            new_state = ACTIVE;
        } else if (((proposal.for_votes > 0 || proposal.against_votes > 0) && proposal.for_votes <= proposal.against_votes) ||
            proposal.for_votes < proposal.quorum_votes) {
            new_state = REJECTED;
        } else if (proposal.eta == 0) {
            new_state = ACCEPTED;
        } else if (current_time < proposal.eta) {
            new_state = QUEUED;
        } else if (vector::length<u8>(&proposal.action) > 0) {
            new_state = EXECUTABLE;
        } else {
            new_state = FULFILLED;
        };
        proposal.propsal_state = new_state;
        table::remove(&mut voting_machine.proposals, object::uid_to_inner(&proposal.id));
        table::add(&mut voting_machine.proposals, object::uid_to_inner(&proposal.id), new_state);
    }

    // anyone can execute an executable proposal
    public entry fun execute_proposal(
        dao_coin_storage: &mut DaoCoinStorage,
        voting_machine: &mut SharedDaoVotingMachine,
        proposal: &mut Proposal,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(proposal.eta <= clock::timestamp_ms(clock), ERR_PROPOSAL_STATE_INVALID);
        assert!(proposal.propsal_state == EXECUTABLE, ERR_PROPOSAL_STATE_INVALID);
        if (proposal.action == WITHDRAW_ACTION) {
            let withdrew_coin = mint_with_proposal(dao_coin_storage, proposal.amount, ctx);
            transfer::public_transfer(withdrew_coin, address::from_bytes(proposal.receiver));
        };
        proposal.propsal_state = FULFILLED;
        if (!table::contains(&mut voting_machine.proposals, object::uid_to_inner(&proposal.id))) {
            assert!(false, ERR_PROPOSAL_STATE_INVALID);
        } else {
            table::remove(&mut voting_machine.proposals, object::uid_to_inner(&proposal.id));
            table::add(&mut voting_machine.proposals, object::uid_to_inner(&proposal.id), FULFILLED);
        }
    }

    #[test]
    public fun test_create_dao() {
        use sui::test_scenario;

        let admin = @0xABBA;
        let non_coin_holder = @0x5678;

        let scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;

        test_scenario::next_tx(scenario, admin);
        {
            daocoin::init_for_testing(test_scenario::ctx(scenario));
        };

        test_scenario::next_tx(scenario, admin);
        {
            let adminCap = test_scenario::take_from_sender<DaoCoinAdminCap>(scenario);
            register(adminCap, b"hello_world_dao", 1, 1, 10, 2, test_scenario::ctx(scenario));
        };

        // acceptance happy path
        // test coin holder can create a proposal
        test_scenario::next_tx(scenario, admin);
        {
            let dao_coin_storage_val = test_scenario::take_shared<DaoCoinStorage>(scenario);
            let dao_coin_storage = &mut dao_coin_storage_val;
            let coin_item = daocoin::mint_for_testing(dao_coin_storage, 100, test_scenario::ctx(scenario));
            let shared_dao_config = test_scenario::take_shared<SharedDaoConfig>(scenario);
            let shared_dao_voting_machine = test_scenario::take_shared<SharedDaoVotingMachine>(scenario);
            let c = clock::create_for_testing(test_scenario::ctx(scenario));
            create_proposal<daocoin::DAOCOIN>(coin_item, &shared_dao_config, &mut shared_dao_voting_machine, &dao_coin_storage_val, &c, b"test proposal", 100, b"", test_scenario::ctx(scenario));
            
            test_scenario::return_shared(dao_coin_storage_val);
            test_scenario::return_shared(shared_dao_config);
            test_scenario::return_shared(shared_dao_voting_machine);
            clock::destroy_for_testing(c);
        };

        // test coin holder can vote for a proposal
        test_scenario::next_tx(scenario, admin);
        {
            let dao_coin_storage_val = test_scenario::take_shared<DaoCoinStorage>(scenario);
            let dao_coin_storage = &mut dao_coin_storage_val;
            let coin_item = daocoin::mint_for_testing(dao_coin_storage, 100, test_scenario::ctx(scenario));
            let shared_dao_config = test_scenario::take_shared<SharedDaoConfig>(scenario);
            let shared_dao_voting_machine = test_scenario::take_shared<SharedDaoVotingMachine>(scenario);
            let c = clock::create_for_testing(test_scenario::ctx(scenario));
            let proposal = test_scenario::take_shared<Proposal>(scenario);
            assert!(proposal_state(&proposal) == PENDING, ERR_PROPOSAL_STATE_INVALID);
            clock::increment_for_testing(&mut c, 2);
            trigger_proposal_state_change(&mut shared_dao_voting_machine, &mut proposal, &c);
            assert!(proposal_state(&proposal) == ACTIVE, ERR_PROPOSAL_STATE_INVALID);
            vote_for_proposal<daocoin::DAOCOIN>(coin_item,&mut proposal,true, &c, test_scenario::ctx(scenario));
            clock::increment_for_testing(&mut c, 1);
            trigger_proposal_state_change(&mut shared_dao_voting_machine, &mut proposal, &c);
            assert!(proposal_state(&proposal) == QUEUED, ERR_PROPOSAL_STATE_INVALID);
            clock::increment_for_testing(&mut c, 1);
            trigger_proposal_state_change(&mut shared_dao_voting_machine, &mut proposal, &c);
            assert!(proposal_state(&proposal) == EXECUTABLE, ERR_PROPOSAL_STATE_INVALID);
            execute_proposal(&mut dao_coin_storage_val, &mut shared_dao_voting_machine, &mut proposal, &c, test_scenario::ctx(scenario));
            assert!(proposal_state(&proposal) == FULFILLED, ERR_PROPOSAL_STATE_INVALID);

            test_scenario::return_shared(dao_coin_storage_val);
            test_scenario::return_shared(shared_dao_config);
            test_scenario::return_shared(shared_dao_voting_machine);
            test_scenario::return_shared(proposal);
            clock::destroy_for_testing(c);
        };

        // normal acceptance happy path - no action
        // test coin holder can create a proposal
        test_scenario::next_tx(scenario, admin);
        {
            let dao_coin_storage_val = test_scenario::take_shared<DaoCoinStorage>(scenario);
            let dao_coin_storage = &mut dao_coin_storage_val;
            let coin_item = daocoin::mint_for_testing(dao_coin_storage, 100, test_scenario::ctx(scenario));
            let shared_dao_config = test_scenario::take_shared<SharedDaoConfig>(scenario);
            let shared_dao_voting_machine = test_scenario::take_shared<SharedDaoVotingMachine>(scenario);
            let c = clock::create_for_testing(test_scenario::ctx(scenario));
            create_proposal<daocoin::DAOCOIN>(coin_item, &shared_dao_config, &mut shared_dao_voting_machine, &dao_coin_storage_val, &c, b"", 100, b"", test_scenario::ctx(scenario));
            
            test_scenario::return_shared(dao_coin_storage_val);
            test_scenario::return_shared(shared_dao_config);
            test_scenario::return_shared(shared_dao_voting_machine);
            clock::destroy_for_testing(c);
        };

        // test coin holder can vote for a proposal
        test_scenario::next_tx(scenario, admin);
        {
            let dao_coin_storage_val = test_scenario::take_shared<DaoCoinStorage>(scenario);
            let dao_coin_storage = &mut dao_coin_storage_val;
            let coin_item = daocoin::mint_for_testing(dao_coin_storage, 100, test_scenario::ctx(scenario));
            let shared_dao_config = test_scenario::take_shared<SharedDaoConfig>(scenario);
            let shared_dao_voting_machine = test_scenario::take_shared<SharedDaoVotingMachine>(scenario);
            let c = clock::create_for_testing(test_scenario::ctx(scenario));
            let proposal = test_scenario::take_shared<Proposal>(scenario);
            assert!(proposal_state(&proposal) == PENDING, ERR_PROPOSAL_STATE_INVALID);
            clock::increment_for_testing(&mut c, 2);
            trigger_proposal_state_change(&mut shared_dao_voting_machine, &mut proposal, &c);
            assert!(proposal_state(&proposal) == ACTIVE, ERR_PROPOSAL_STATE_INVALID);
            vote_for_proposal<daocoin::DAOCOIN>(coin_item, &mut proposal,true, &c, test_scenario::ctx(scenario));
            clock::increment_for_testing(&mut c, 1);
            trigger_proposal_state_change(&mut shared_dao_voting_machine, &mut proposal, &c);
            assert!(proposal_state(&proposal) == ACCEPTED, ERR_PROPOSAL_STATE_INVALID);

            test_scenario::return_shared(dao_coin_storage_val);
            test_scenario::return_shared(shared_dao_config);
            test_scenario::return_shared(shared_dao_voting_machine);
            test_scenario::return_shared(proposal);
            clock::destroy_for_testing(c);
        };

        // reject happy path
        // test coin holder can create a proposal
        test_scenario::next_tx(scenario, admin);
        {
            let dao_coin_storage_val = test_scenario::take_shared<DaoCoinStorage>(scenario);
            let dao_coin_storage = &mut dao_coin_storage_val;
            let coin_item = daocoin::mint_for_testing(dao_coin_storage, 100, test_scenario::ctx(scenario));
            let shared_dao_config = test_scenario::take_shared<SharedDaoConfig>(scenario);
            let shared_dao_voting_machine = test_scenario::take_shared<SharedDaoVotingMachine>(scenario);
            let c = clock::create_for_testing(test_scenario::ctx(scenario));
            create_proposal<daocoin::DAOCOIN>(coin_item, &shared_dao_config, &mut shared_dao_voting_machine, &dao_coin_storage_val, &c, b"test proposal", 100, b"", test_scenario::ctx(scenario));
            
            test_scenario::return_shared(dao_coin_storage_val);
            test_scenario::return_shared(shared_dao_config);
            test_scenario::return_shared(shared_dao_voting_machine);
            clock::destroy_for_testing(c);
        };

        // test coin holder can vote for a proposal
        test_scenario::next_tx(scenario, admin);
        {
            let dao_coin_storage_val = test_scenario::take_shared<DaoCoinStorage>(scenario);
            let dao_coin_storage = &mut dao_coin_storage_val;
            let coin_item = daocoin::mint_for_testing(dao_coin_storage, 100, test_scenario::ctx(scenario));
            let shared_dao_config = test_scenario::take_shared<SharedDaoConfig>(scenario);
            let shared_dao_voting_machine = test_scenario::take_shared<SharedDaoVotingMachine>(scenario);
            let c = clock::create_for_testing(test_scenario::ctx(scenario));
            let proposal = test_scenario::take_shared<Proposal>(scenario);
            assert!(proposal_state(&proposal) == PENDING, ERR_PROPOSAL_STATE_INVALID);
            clock::increment_for_testing(&mut c, 2);
            trigger_proposal_state_change(&mut shared_dao_voting_machine, &mut proposal, &c);
            assert!(proposal_state(&proposal) == ACTIVE, ERR_PROPOSAL_STATE_INVALID);
            vote_for_proposal<daocoin::DAOCOIN>(coin_item, &mut proposal,false, &c, test_scenario::ctx(scenario));
            clock::increment_for_testing(&mut c, 1);
            trigger_proposal_state_change(&mut shared_dao_voting_machine, &mut proposal, &c);
            assert!(proposal_state(&proposal) == REJECTED, ERR_PROPOSAL_STATE_INVALID);
            clock::increment_for_testing(&mut c, 1);
            trigger_proposal_state_change(&mut shared_dao_voting_machine, &mut proposal, &c);

            test_scenario::return_shared(dao_coin_storage_val);
            test_scenario::return_shared(shared_dao_config);
            test_scenario::return_shared(shared_dao_voting_machine);
            test_scenario::return_shared(proposal);
            clock::destroy_for_testing(c);
        };

        // acceptance happy path - with withdraw action
        // test coin holder can create a proposal
        test_scenario::next_tx(scenario, admin);
        {
            let dao_coin_storage_val = test_scenario::take_shared<DaoCoinStorage>(scenario);
            let dao_coin_storage = &mut dao_coin_storage_val;
            let coin_item = daocoin::mint_for_testing(dao_coin_storage, 100, test_scenario::ctx(scenario));
            let shared_dao_config = test_scenario::take_shared<SharedDaoConfig>(scenario);
            let shared_dao_voting_machine = test_scenario::take_shared<SharedDaoVotingMachine>(scenario);
            let c = clock::create_for_testing(test_scenario::ctx(scenario));
            create_proposal<daocoin::DAOCOIN>(coin_item, &shared_dao_config, &mut shared_dao_voting_machine, &dao_coin_storage_val, &c, WITHDRAW_ACTION, 100, address::to_bytes(non_coin_holder), test_scenario::ctx(scenario));
            
            test_scenario::return_shared(dao_coin_storage_val);
            test_scenario::return_shared(shared_dao_config);
            test_scenario::return_shared(shared_dao_voting_machine);
            clock::destroy_for_testing(c);
        };

        // test coin holder can vote for a proposal
        test_scenario::next_tx(scenario, admin);
        {
            let dao_coin_storage_val = test_scenario::take_shared<DaoCoinStorage>(scenario);
            let dao_coin_storage = &mut dao_coin_storage_val;
            let coin_item = daocoin::mint_for_testing(dao_coin_storage, 100, test_scenario::ctx(scenario));
            let shared_dao_config = test_scenario::take_shared<SharedDaoConfig>(scenario);
            let shared_dao_voting_machine = test_scenario::take_shared<SharedDaoVotingMachine>(scenario);
            let c = clock::create_for_testing(test_scenario::ctx(scenario));
            let proposal = test_scenario::take_shared<Proposal>(scenario);
            assert!(proposal_state(&proposal) == PENDING, ERR_PROPOSAL_STATE_INVALID);
            clock::increment_for_testing(&mut c, 2);
            trigger_proposal_state_change(&mut shared_dao_voting_machine, &mut proposal, &c);
            assert!(proposal_state(&proposal) == ACTIVE, ERR_PROPOSAL_STATE_INVALID);
            vote_for_proposal<daocoin::DAOCOIN>(coin_item, &mut proposal,true, &c, test_scenario::ctx(scenario));
            clock::increment_for_testing(&mut c, 1);
            trigger_proposal_state_change(&mut shared_dao_voting_machine, &mut proposal, &c);
            assert!(proposal_state(&proposal) == QUEUED, ERR_PROPOSAL_STATE_INVALID);
            clock::increment_for_testing(&mut c, 1);
            trigger_proposal_state_change(&mut shared_dao_voting_machine, &mut proposal, &c);
            assert!(proposal_state(&proposal) == EXECUTABLE, ERR_PROPOSAL_STATE_INVALID);
            execute_proposal(&mut dao_coin_storage_val, &mut shared_dao_voting_machine, &mut proposal, &c, test_scenario::ctx(scenario));
            assert!(proposal_state(&proposal) == FULFILLED, ERR_PROPOSAL_STATE_INVALID);

            test_scenario::return_shared(dao_coin_storage_val);
            test_scenario::return_shared(shared_dao_config);
            test_scenario::return_shared(shared_dao_voting_machine);
            test_scenario::return_shared(proposal);
            clock::destroy_for_testing(c);
        };

        test_scenario::end(scenario_val);
    }
}