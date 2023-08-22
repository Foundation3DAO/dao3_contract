module dao3_contract::daocoin {
  use std::option;

  use sui::object::{Self, UID};
  use sui::tx_context::{TxContext};
  use sui::balance::{Self, Supply};
  use sui::transfer;
  use sui::coin::{Self, Coin};
  use sui::url;
  use sui::package::{Publisher};
  use sui::tx_context;
  use sui::event::{emit};

  const ERROR_NOT_ALLOWED_TO_MINT: u64 = 1;
  const ERROR_NO_ZERO_ADDRESS: u64 = 2;
  const ERROR_WRONG_FLASH_MINT_BURN_AMOUNT: u64 = 3;

  // OTW to create the Sui Stable DaoCoin currency
  struct DAOCOIN has drop {}

  // Shared object
  struct DaoCoinStorage has key {
    id: UID,
    supply: Supply<DAOCOIN>,
  }

  struct FlashMint {
    burn_amount: u64
  }

  // The owner of this object
  struct DaoCoinAdminCap has key {
    id: UID
  }

  struct NewAdmin has copy, drop {
    admin: address
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

      // Share the DaoCoinStorage Object with the Sui network
      transfer::share_object(
        DaoCoinStorage {
          id: object::new(ctx),
          supply,
        }
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

  /**
  * @dev Only packages can mint dinero by passing the storage publisher
  * @param storage The DaoCoinStorage
  * @param publisher The Publisher object of the package who wishes to mint DaoCoin
  * @return Coin<DAOCOIN> New created DAOCOIN coin
  */
  public fun mint(storage: &mut DaoCoinStorage, _publisher: &Publisher, value: u64, ctx: &mut TxContext): Coin<DAOCOIN> {
    // assert!(is_minter(storage, object::id(publisher)), ERROR_NOT_ALLOWED_TO_MINT);

    coin::from_balance(balance::increase_supply(&mut storage.supply, value), ctx)
  }

  public fun flash_mint(storage: &mut DaoCoinStorage, value: u64, ctx: &mut TxContext): (FlashMint, Coin<DAOCOIN>) {
    (FlashMint { burn_amount: value }, coin::from_balance(balance::increase_supply(&mut storage.supply, value), ctx))
  }

  public fun read_flash_mint(potato: &FlashMint): u64 {
    potato.burn_amount
  }

  public fun flash_burn(storage: &mut DaoCoinStorage, potato: FlashMint, asset: Coin<DAOCOIN>) {
    let FlashMint { burn_amount } = potato;
    
    assert!(coin::value(&asset) >= burn_amount, ERROR_WRONG_FLASH_MINT_BURN_AMOUNT);
    balance::decrease_supply(&mut storage.supply, coin::into_balance(asset));
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

 /**
  * @dev It gives the admin rights to the recipient. 
  * @param admin_cap The DaoCoinAdminCap that will be transferred
  * @recipient the new admin address
  *
  * It emits the NewAdmin event with the new admin address
  *
  */
  entry public fun transfer_admin(admin_cap: DaoCoinAdminCap, recipient: address) {
    assert!(recipient != @0x0, ERROR_NO_ZERO_ADDRESS);
    transfer::transfer(admin_cap, recipient);

    emit(NewAdmin {
      admin: recipient
    });
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