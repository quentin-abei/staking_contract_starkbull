//use core::option::OptionTrait;
use core::traits::TryInto;
use core::serde::Serde;
use starknet::ContractAddress;

use snforge_std::{ContractClass, ContractClassTrait, CheatTarget, declare, start_prank, stop_prank, TxInfoMock,
    start_warp, stop_warp, get_class_hash};

use staking_stbull::hellostarknet::IHelloStarknetSafeDispatcher;
use staking_stbull::hellostarknet::IHelloStarknetSafeDispatcherTrait;
use staking_stbull::hellostarknet::IHelloStarknetDispatcher;
use staking_stbull::hellostarknet::IHelloStarknetDispatcherTrait;
use staking_stbull::staking::IStakingRewardsDispatcher;
use staking_stbull::staking::IStakingRewardsDispatcherTrait;
use staking_stbull::erc20::IERC20Dispatcher;
use staking_stbull::erc20::IERC20DispatcherTrait;

fn deploycontract(name: ByteArray) -> ContractAddress {
    let contract = declare(name).unwrap();
    let (contract_address, _) = contract.deploy(@ArrayTrait::new()).unwrap();
    return (contract_address);
}
fn deployToken(name: ByteArray) -> ContractAddress {
    let contract = declare(name).unwrap();
    let mut calldata = array![];
    (OWNER(), NAME(), DECIMALS(), SUPPLY()).serialize(ref calldata);
    (SYMBOL(),).serialize(ref calldata);
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    return (contract_address);
}
fn OWNER() -> ContractAddress {
    return('owner'.try_into().unwrap());
}
fn NAME() -> felt252 {
    return('STAKING TOKEN');
}
fn SYMBOL() -> felt252 {
    return('STAKING');
}
fn SUPPLY() -> felt252 {
    return(30_000_000);
}
fn DECIMALS() -> u8 {
    return(18);
}
fn USER() -> ContractAddress {
    return('user'.try_into().unwrap());
}
fn USER1() -> ContractAddress {
    return('user123'.try_into().unwrap());
}
fn MALICIOUS() -> ContractAddress {
    return('user1234'.try_into().unwrap());
}

fn deploy_staking(name: ByteArray) -> ContractAddress {
    let contract = declare(name).unwrap();
    let STAKING_TOKEN = deployToken("erc20");
    let mut calldata = array![];
    (OWNER(), STAKING_TOKEN,).serialize(ref calldata);
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    return (contract_address);
}

#[test]
fn test_increase_balance() {
    let contract_address = deploycontract("HelloStarknet");

    let dispatcher = IHelloStarknetDispatcher { contract_address };

    let balance_before = dispatcher.get_balance();
    assert(balance_before == 0, 'Invalid balance');

    dispatcher.increase_balance(42);

    let balance_after = dispatcher.get_balance();
    assert(balance_after == 42, 'Invalid balance');
}

#[test]
fn test_staking_token() {
    let owner = OWNER();
    let user = USER();
    let user1 = USER1();
    let abusor = MALICIOUS();
    let stake_contract_address = deploy_staking("StakingRewards");
    let stake_dispatcher = IStakingRewardsDispatcher{contract_address: stake_contract_address};
    let staking_token = stake_dispatcher.staking_Token();
    let token_address = IERC20Dispatcher{contract_address: staking_token};

    let contract_bal_before = token_address.balance_of(stake_contract_address);
    assert(contract_bal_before == 0, 'something is wrong');

    start_prank(CheatTarget::One(staking_token), owner);
    token_address.approve(stake_dispatcher.contract_address, 11_000_000);
    println!("1");
    
    let allow: felt252 = token_address.allowance(owner, stake_dispatcher.contract_address);
    assert(allow == 11_000_000, 'did not allow' );

    // let owner_bal = token_address.balance_of(owner);
    // println!("owner bal {:?}", owner_bal);

    //token_address.transfer(stake_dispatcher.contract_address, 11_000_000);
    token_address.transfer(user, 6_000_000);
    token_address.transfer(user1, 4_000_000);
    token_address.transfer(abusor, 4_000_000);
    println!("2");

    // let owner_bal = token_address.balance_of(owner);
    // println!("owner bal {:?}", owner_bal);
    // let user_bal = token_address.balance_of(user);
    // println!("owner bal {:?}", user_bal);

    stop_prank(CheatTarget::One(staking_token));

    start_prank(CheatTarget::One(stake_contract_address), user);
    println!("3");
    stake_dispatcher.stake(6_000_000);
    let totalstakes: u256 = stake_dispatcher.total_Staked();
    println!("total staked is {:?}", totalstakes);
    //stake_dispatcher.update_rewards_index(11000000);
    println!("4");
    stop_prank(CheatTarget::One(stake_dispatcher.contract_address));

    start_prank(CheatTarget::One(stake_contract_address), user1);
    stake_dispatcher.stake(4_000_000);
    let totalstakes: u256 = stake_dispatcher.total_Staked();
    println!("total staked is {:?}", totalstakes);
    //stake_dispatcher.update_rewards_index(11000000);
    stop_prank(CheatTarget::One(stake_dispatcher.contract_address));

    start_prank(CheatTarget::One(stake_contract_address), owner);
    stake_dispatcher.update_rewards_index(11000000);
    stop_prank(CheatTarget::One(stake_dispatcher.contract_address));

    // start_prank(CheatTarget::One(stake_contract_address), user);
    // stake_dispatcher.update_rewards_index(11000000);
    // stop_prank(CheatTarget::One(stake_dispatcher.contract_address));

    start_prank(CheatTarget::One(stake_contract_address), abusor);
    stake_dispatcher.stake(6000000);
    // let claimed: u256 = stake_dispatcher.claim();
    // println!("total claimed by abusor is {:?}", claimed);
    stop_prank(CheatTarget::One(stake_dispatcher.contract_address));

    start_warp(CheatTarget::One(stake_contract_address), 12000);
    start_prank(CheatTarget::One(stake_contract_address), user);
    let rew: u256 = stake_dispatcher.calculate_rewards_earned(user);
    println!("rewards earned by user is {:?}", rew);
    let claimed: u256 = stake_dispatcher.claim();
    println!("total claimed is {:?}", claimed);
    stake_dispatcher.unstake(6000000);
    stop_prank(CheatTarget::One(stake_dispatcher.contract_address));
    start_prank(CheatTarget::One(stake_contract_address), user1);
    let claimed: u256 = stake_dispatcher.claim();
    println!("total claimed is {:?}", claimed);
    stake_dispatcher.unstake(4000000);
    let totalstakes: u256 = stake_dispatcher.total_Staked();
    println!("total staked is {:?}", totalstakes);
    stop_prank(CheatTarget::One(stake_dispatcher.contract_address));
    start_prank(CheatTarget::One(stake_contract_address), abusor);
    let claimed: u256 = stake_dispatcher.claim();
    println!("total claimed by abusor is {:?}", claimed);
    stop_prank(CheatTarget::One(stake_dispatcher.contract_address));
    stop_warp(CheatTarget::One(stake_contract_address));

    

    // start_prank(CheatTarget::One(staking_token), owner);
    // // let bal_stake = token_address.balance_of(stake_contract_address);
    // // assert(bal_stake == 11_000_000, 'did not match' );
    // stop_prank(CheatTarget::One(staking_token));

    

    //println!("address {:?}", stake_contract_address);
}

#[test]
#[feature("safe_dispatcher")]
fn test_cannot_increase_balance_with_zero_value() {
    let contract_address = deploycontract("HelloStarknet");

    let safe_dispatcher = IHelloStarknetSafeDispatcher { contract_address };

    let balance_before = safe_dispatcher.get_balance().unwrap();
    assert(balance_before == 0, 'Invalid balance');

    match safe_dispatcher.increase_balance(0) {
        Result::Ok(_) => core::panic_with_felt252('Should have panicked'),
        Result::Err(panic_data) => {
            assert(*panic_data.at(0) == 'Amount cannot be 0', *panic_data.at(0));
        }
    };
}
