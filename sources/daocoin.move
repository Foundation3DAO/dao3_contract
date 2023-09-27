module dao3_contract::daocoin {
  use std::option;

  use sui::object::{Self, UID};
  use sui::tx_context::{TxContext};
  use sui::balance::{Self, Supply};
  use sui::transfer;
  use sui::coin::{Self, Coin};
  use sui::url;
  use sui::tx_context;

  friend dao3_contract::dao;

  const ERROR_NOT_ALLOWED_TO_MINT: u64 = 1;
  const ERROR_NO_ZERO_ADDRESS: u64 = 2;
  const ERROR_WRONG_FLASH_MINT_BURN_AMOUNT: u64 = 3;

  // OTW to create the DaoCoin currency
  struct DAOCOIN has drop {}

  // Shared object
  struct DaoCoinStorage has key, store {
    id: UID,
    supply: Supply<DAOCOIN>,
  }

  // The owner of this object
  struct DaoCoinAdminCap has key, store {
    id: UID
  }

  fun init(witness: DAOCOIN, ctx: &mut TxContext) {
      let (treasury, metadata) = coin::create_currency<DAOCOIN>(
            witness, 
            9,
            b"DAOCOIN",
            b"DAO Coin",
            b"DAO Coin description",
            option::some(url::new_unsafe_from_bytes(b"https://interestprotocol.infura-ipfs.io/ipfs/QmTZtraqcGAJHA2BLsHK2EK6xzv1kz36LvGZiUpj493Q7a")),
            ctx
        );

      // Transform the treasury_cap into a supply struct to allow this contract to mint/burn DAOCOIN
      let supply = coin::treasury_into_supply(treasury);

      let storage = DaoCoinStorage {
          id: object::new(ctx),
          supply,
      };
      let init_coin = mint_with_proposal(&mut storage, 1000000000, ctx);
      // Share the DaoCoinStorage Object with the Sui network
      transfer::transfer(
        storage,
        tx_context::sender(ctx)
      );

      transfer::public_transfer(
        init_coin,
        tx_context::sender(ctx)
      );

      // Send the AdminCap to the deployer
      transfer::transfer(
        DaoCoinAdminCap {
          id: object::new(ctx)
        },
        tx_context::sender(ctx)
      );

      // Freeze the metadata object, since we cannot update without the TreasuryCap
      transfer::public_freeze_object(metadata);
  }

  public(friend) fun mint_with_proposal(storage: &mut DaoCoinStorage, value: u64, ctx: &mut TxContext): Coin<DAOCOIN> {
    coin::from_balance(balance::increase_supply(&mut storage.supply, value), ctx)
  }

  public entry fun mint_to_play(storage: &mut DaoCoinStorage, value: u64, ctx: &mut TxContext) {
    let minted = coin::from_balance(balance::increase_supply(&mut storage.supply, value), ctx);
    transfer::public_transfer(minted, tx_context::sender(ctx));
  }

  /**
  * @dev This function allows anyone to burn their own DAOCOIN.
  * @param storage The DaoCoinStorage shared object
  * @param asset The dinero coin that will be burned
  */
  public fun burn(storage: &mut DaoCoinStorage, asset: Coin<DAOCOIN>): u64 {
    balance::decrease_supply(&mut storage.supply, coin::into_balance(asset))
  }

  /**
  * @dev Utility function to transfer Coin<DAOCOIN>
  * @param The coin to transfer
  * @param recipient The address that will receive the Coin<DAOCOIN>
  */
  public entry fun transfer(coin_dnr: coin::Coin<DAOCOIN>, recipient: address) {
    transfer::public_transfer(coin_dnr, recipient);
  }

  /**
  * It allows anyone to know the total value in existence of DAOCOIN
  * @storage The shared DaoCoinStorage
  * @return u64 The total value of DAOCOIN in existence
  */
  public fun total_supply(storage: &DaoCoinStorage): u64 {
    balance::supply_value(&storage.supply)
  }

  public(friend) fun total_supply_for_proposal(storage: &DaoCoinStorage): u64 {
    balance::supply_value(&storage.supply)
  }

  // Test only functions
  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(DAOCOIN {}, ctx);
  }

  #[test_only]
  public fun mint_for_testing(storage: &mut DaoCoinStorage, value: u64, ctx: &mut TxContext): Coin<DAOCOIN> {
    coin::from_balance(balance::increase_supply(&mut storage.supply, value), ctx)
  }
}