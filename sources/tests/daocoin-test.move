#[test_only]
module dao3_contract::daocoin_tests {
  use sui::test_scenario::{Self as test, next_tx, Scenario, ctx};
  use sui::test_utils::{assert_eq};
  use sui::coin::{burn_for_testing as burn};

  use  dao3_contract::daocoin::{Self, DaoCoinStorage, DaoCoinAdminCap};
  use  dao3_contract::foo::{Self, FooStorage};

  fun scenario(): Scenario { test::begin(@0x1) }

  fun people():(address, address) { (@0xBEEF, @0x1337)}

//   #[test]
//   #[expected_failure(abort_code = daocoin::ERROR_NOT_ALLOWED_TO_MINT)]
//   fun test_mint_amount_error() {
//       let scenario = scenario();
//       let (alice, _) = people();
//       let test = &mut scenario;

//       start_suid(test);

//       next_tx(test, alice);
//       {
//         let suid_storage = test::take_shared<DaoCoinStorage>(test);
//         let foo_storage = test::take_shared<FooStorage>(test);

//         let publisher = foo::get_publisher(&foo_storage);
//         let id = foo::get_publisher_id(&foo_storage);

//         burn(daocoin::mint(&mut suid_storage, publisher, 1, ctx(test)));

//         assert_eq(daocoin::is_minter(&suid_storage, id), true);

//         test::return_shared(suid_storage);
//         test::return_shared(foo_storage);
//       };
//       test::end(scenario);
//   }

//   #[test]
//   fun test_mint() {
//       let scenario = scenario();
//       let (alice, _) = people();
//       let test = &mut scenario;

//       start_suid(test);

//       next_tx(test, alice);
//       {
//         let suid_storage = test::take_shared<DaoCoinStorage>(test);
//         let foo_storage = test::take_shared<FooStorage>(test);
//         let admin_cap = test::take_from_address<DaoCoinAdminCap>(test, alice);

//         let publisher = foo::get_publisher(&foo_storage);
//         let id = foo::get_publisher_id(&foo_storage);


//         daocoin::add_minter(&admin_cap, &mut suid_storage, id);
//         assert_eq(burn(daocoin::mint(&mut suid_storage, publisher, 100, ctx(test))), 100);


//         test::return_shared(suid_storage);
//         test::return_shared(foo_storage);
//         test::return_to_address(alice, admin_cap);
//       };
//       test::end(scenario);
//   }
  
//   #[test]
//   #[expected_failure(abort_code = daocoin::ERROR_NOT_ALLOWED_TO_MINT)]
//   fun test_remove_minter() {
//       let scenario = scenario();
//       let (alice, _) = people();
//       let test = &mut scenario;

//       start_suid(test);

//       next_tx(test, alice);
//       {
//         let suid_storage = test::take_shared<DaoCoinStorage>(test);
//         let foo_storage = test::take_shared<FooStorage>(test);
//         let admin_cap = test::take_from_address<DaoCoinAdminCap>(test, alice);

//         let publisher = foo::get_publisher(&foo_storage);
//         let id = foo::get_publisher_id(&foo_storage);


//         daocoin::add_minter(&admin_cap, &mut suid_storage, id);
//         assert_eq(burn(daocoin::mint(&mut suid_storage, publisher, 100, ctx(test))), 100);

//         daocoin::remove_minter(&admin_cap, &mut suid_storage, id);

//         assert_eq(daocoin::is_minter(&suid_storage, id), false);
//         assert_eq(burn(daocoin::mint(&mut suid_storage, publisher, 100, ctx(test))), 100);

//         test::return_shared(suid_storage);
//         test::return_shared(foo_storage);
//         test::return_to_address(alice, admin_cap);
//       };
//       test::end(scenario);
//   }

//   #[test]
//   fun test_burn() {
//       let scenario = scenario();
//       let (alice, _) = people();
//       let test = &mut scenario;

//       start_suid(test);

//       next_tx(test, alice);
//       {
//         let suid_storage = test::take_shared<DaoCoinStorage>(test);
//         let foo_storage = test::take_shared<FooStorage>(test);
//         let admin_cap = test::take_from_address<DaoCoinAdminCap>(test, alice);

//         let publisher = foo::get_publisher(&foo_storage);
//         let id = foo::get_publisher_id(&foo_storage);


//         daocoin::add_minter(&admin_cap, &mut suid_storage, id);

//         let coin_ipx = daocoin::mint(&mut suid_storage, publisher, 100, ctx(test));
//         assert_eq(daocoin::burn(&mut suid_storage, coin_ipx), 100);


//         test::return_shared(suid_storage);
//         test::return_shared(foo_storage);
//         test::return_to_address(alice, admin_cap);
//       };
//       test::end(scenario);
//   }

  fun start_suid(test: &mut Scenario) {
       let (alice, _) = people();
       next_tx(test, alice);
       {
        daocoin::init_for_testing(ctx(test));
        foo::init_for_testing(ctx(test));
       };
  }
}