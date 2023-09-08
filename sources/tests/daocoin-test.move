#[test_only]
module dao3_contract::daocoin_tests {
  use sui::test_scenario::{Self as test, next_tx, Scenario, ctx};
  use sui::test_utils::{assert_eq};
  use sui::coin::{burn_for_testing as burn};

  use  dao3_contract::daocoin::{Self, DaoCoinStorage, DaoCoinAdminCap};
  use  dao3_contract::foo::{Self, FooStorage};

  fun scenario(): Scenario { test::begin(@0x1) }

  fun people():(address, address) { (@0xBEEF, @0x1337)}

  #[test]
  fun test_mint() {
      let scenario = scenario();
      let (alice, _) = people();
      let test = &mut scenario;

      start_daocoin(test);

      next_tx(test, alice);
      {
        let daocoin_storage = test::take_shared<DaoCoinStorage>(test);
        let foo_storage = test::take_shared<FooStorage>(test);
        let admin_cap = test::take_from_address<DaoCoinAdminCap>(test, alice);

        assert_eq(burn(daocoin::mint(&mut daocoin_storage, 100, ctx(test))), 100);

        test::return_shared(daocoin_storage);
        test::return_shared(foo_storage);
        test::return_to_address(alice, admin_cap);
      };
      test::end(scenario);
  }

  #[test]
  fun test_burn() {
      let scenario = scenario();
      let (alice, _) = people();
      let test = &mut scenario;

      start_daocoin(test);

      next_tx(test, alice);
      {
        let daocoin_storage = test::take_shared<DaoCoinStorage>(test);
        let foo_storage = test::take_shared<FooStorage>(test);
        let admin_cap = test::take_from_address<DaoCoinAdminCap>(test, alice);

        let coin_ipx = daocoin::mint(&mut daocoin_storage, 100, ctx(test));
        assert_eq(daocoin::burn(&mut daocoin_storage, coin_ipx), 100);

        test::return_shared(daocoin_storage);
        test::return_shared(foo_storage);
        test::return_to_address(alice, admin_cap);
      };
      test::end(scenario);
  }

  fun start_daocoin(test: &mut Scenario) {
       let (alice, _) = people();
       next_tx(test, alice);
       {
        daocoin::init_for_testing(ctx(test));
        foo::init_for_testing(ctx(test));
       };
  }
}