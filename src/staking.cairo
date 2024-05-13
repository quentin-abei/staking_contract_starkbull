// SPDX-License-Identifier: MIT
use starknet::ContractAddress;

// In order to make contract calls within our Vault,
// we need to have the interface of the remote ERC20 contract (starkbull) defined to import the Dispatcher.
 //In order to make contract calls within our Vault,
 //we need to have the interface of the remote ERC20 contract (starkbull) defined to import the Dispatcher.
 #[starknet::interface]
 pub trait IERC20<TContractState> {
     fn name(self: @TContractState) -> felt252;
     fn symbol(self: @TContractState) -> felt252;
     fn decimals(self: @TContractState) -> u8;
     fn total_supply(self: @TContractState) -> u256;
     //fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
     // fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
     //fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    //  fn transfer_from(
    //      ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    //  ) -> bool;
    //  fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
     fn balance_of(self: @TContractState, account: ContractAddress) -> felt252;
    fn allowance(
        self: @TContractState, owner: ContractAddress, spender: ContractAddress
    ) -> felt252;
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: felt252);
    fn transfer_from(
        ref self: TContractState,
        sender: ContractAddress,
        recipient: ContractAddress,
        amount: felt252
    );
    fn approve(ref self: TContractState, spender: ContractAddress, amount: felt252);
}

#[starknet::interface]
pub trait IStakingRewards<TContractState> {
    fn stake(ref self: TContractState, amount: felt252);
    fn unstake(ref self: TContractState, amount: felt252);
    fn claim(ref self: TContractState) -> u256;
    fn update_rewards_index(ref self: TContractState, reward: felt252);
    fn calculate_rewards_earned(self: @TContractState, account: ContractAddress) -> u256;
    fn staking_Token(self: @TContractState) -> ContractAddress;
    fn rewards_Token(self: @TContractState) -> ContractAddress;
    fn total_Staked(self: @TContractState) -> u256;
    fn get_remaining_time(self: @TContractState) -> u64;
    //fn updateTime(ref self: TContractState);
    fn updateStakingDuration(ref self: TContractState, duration: u64);
    fn get_staking_duration(self: @TContractState) -> u64;
}


// this contract does not have any guarantee to work, this is a solidityByExample implementation in ClaimedDrop
// I did not audit nor write tests for this contract.
// Use at your own risks
#[starknet::contract]
pub mod StakingRewards {
    use core::option::OptionTrait;
    use core::traits::TryInto;
    use core::starknet::event::EventEmitter;
    use starknet::{ContractAddress, get_caller_address, get_contract_address, get_block_timestamp};
    use core::num::traits::Zero;
    use super::{IERC20Dispatcher, IERC20DispatcherTrait};
    const MULTIPLIER: u256 = 1000000000000000000;
    
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
      Staked: Staked,
      Unstaked: Unstaked,
      Claim: Claimed,
    }

    #[derive(Drop, starknet::Event)]
    struct Staked {
      amount: felt252
    }

    #[derive(Drop, starknet::Event)]
    struct Unstaked {
      amount: felt252
    }
    
    #[derive(Drop, starknet::Event)]
    struct Claimed {
      reward: u256
    }

    #[storage]
    struct Storage {
        stakingToken: IERC20Dispatcher, 
        rewardsToken: IERC20Dispatcher,
        // Total staked
        totalSupply: u256,
        currentTime: u64,
        staking_duration: u64,
        // User address => staked amount
        balanceOf: LegacyMap<ContractAddress, u256>,
        rewardsIndex: u256,
        owner: ContractAddress,
        rewardsIndexOf: LegacyMap<ContractAddress, u256>,
        earned: LegacyMap<ContractAddress, u256>
    }

    #[constructor]
    fn constructor(ref self: ContractState, _owner: ContractAddress, _staking_token: ContractAddress) {
        let time = get_block_timestamp();
        self.stakingToken.write( IERC20Dispatcher { contract_address: _staking_token });
        self.rewardsToken.write( IERC20Dispatcher { contract_address: _staking_token });
        self.owner.write(_owner);
        self.currentTime.write(time);
    }

     #[generate_trait]
    impl PrivateFunctions of PrivateFunctionsTrait {
       fn _calculate_rewards(self: @ContractState, account: ContractAddress) -> u256 {
          let shares: u256 = self.balanceOf.read(account);
          return (shares * (self.rewardsIndex.read() - self.rewardsIndexOf.read(account)))/ MULTIPLIER;
       }

       fn _update_rewards(ref self: ContractState, account: ContractAddress) {
          self.earned.write(account, self.earned.read(account) + self._calculate_rewards(account));
          self.rewardsIndexOf.write(account, self.rewardsIndex.read());
       }
    }

    #[abi(embed_v0)]
    impl SimpleRewardsImpl of super::IStakingRewards<ContractState> {
       fn stake(ref self: ContractState, amount: felt252) {
         //let _amount: u256 = amount.into();
         let time = get_block_timestamp();
         assert(time - self.currentTime.read() <= self.staking_duration.read(), 'staking ended or not started');
         let caller = get_caller_address();
         let this = get_contract_address();
         PrivateFunctions::_update_rewards(ref self, caller);
         assert(amount != 0, 'cannot stake 0 token');
         self.stakingToken.read().transfer_from(caller, this, amount);
         self.balanceOf.write(caller, self.balanceOf.read(caller) + amount.try_into().unwrap());
         self.totalSupply.write(self.totalSupply.read() + amount.try_into().unwrap());
         self.emit(Staked{amount});
       }

       fn unstake(ref self: ContractState, amount: felt252) {
         let time = get_block_timestamp();
         assert(time - self.currentTime.read() >= self.staking_duration.read(), 'cannot unstake now');
         let caller = get_caller_address();
         PrivateFunctions::_update_rewards(ref self, caller);
         assert(amount != 0, 'amount is 0');
         assert(self.balanceOf.read(caller) - amount.try_into().unwrap() >=0, 'not enough funds');
         self.balanceOf.write(caller, self.balanceOf.read(caller) - amount.try_into().unwrap());
         self.totalSupply.write(self.totalSupply.read() - amount.try_into().unwrap());
         self.stakingToken.read().transfer(caller, amount.try_into().unwrap());
         self.emit(Unstaked{amount});
       }

       fn claim(ref self: ContractState) -> u256 {
         let caller = get_caller_address();
         PrivateFunctions::_update_rewards(ref self, caller);
         let reward: u256 = self.earned.read(caller);
         if(reward >0) {
            self.earned.write(caller, 0);
            self.rewardsToken.read().transfer(caller, reward.try_into().unwrap());
         }
         self.emit(Claimed{reward});
         return reward;
       }

       fn staking_Token(self: @ContractState) -> ContractAddress {
        return (self.stakingToken.read().contract_address);
       }

       fn rewards_Token(self: @ContractState) -> ContractAddress {
        return (self.rewardsToken.read().contract_address);
       }

       fn total_Staked(self: @ContractState) -> u256 {
        return (self.totalSupply.read());
       }
       
       /// dev: should be called before telling people to stake
      //  fn updateTime(ref self: ContractState)  {
      //   let caller = get_caller_address();
      //   assert(caller == self.owner.read(), 'error');
      //   let this_time = get_block_timestamp();
      //   self.currentTime.write(this_time);
      //  }

       fn updateStakingDuration(ref self: ContractState, duration: u64)  {
        let caller = get_caller_address();
        assert(caller == self.owner.read(), 'error');
        let this_time = get_block_timestamp();
        self.currentTime.write(this_time);
        self.staking_duration.write(duration);
       }

       fn get_staking_duration(self: @ContractState) -> u64 {
        return(self.staking_duration.read());
       }

       fn get_remaining_time(self: @ContractState) -> u64 {
        let this_time = get_block_timestamp();
        let total_time = self.currentTime.read() + self.staking_duration.read();
        let remainder = total_time - this_time;
        return(remainder);
       }

       fn update_rewards_index(ref self: ContractState, reward: felt252) {
         let caller = get_caller_address();
         assert(caller == self.owner.read(), 'error');
         let this = get_contract_address();
         self.rewardsToken.read().transfer_from(caller, this, reward);
         self.rewardsIndex.write(self.rewardsIndex.read() + ((reward.try_into().unwrap() * MULTIPLIER.try_into().unwrap() / self.totalSupply.read())));
       }

       fn calculate_rewards_earned(self: @ContractState, account: ContractAddress) -> u256 {
         return self.earned.read(account) + self._calculate_rewards(account);
       }
    }
}