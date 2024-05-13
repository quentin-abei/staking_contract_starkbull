use  starknet::ContractAddress;
use  starknet::ClassHash;

#[starknet::interface]
pub trait IDeployFactory<TContractState> {
    /// Create a new counter contract from stored arguments
    fn create_staking_at(ref self: TContractState, owner_: ContractAddress, staking_token_: ContractAddress) -> ContractAddress;

    /// Create a new counter contract from the given arguments
    fn create_staking(ref self: TContractState, staking_token_: ContractAddress) -> ContractAddress;
    /// Update the argument
    fn update_constructor_args(ref self: TContractState, owner_: ContractAddress, staking_token_: ContractAddress);

    /// Update the class hash of the Counter contract to deploy when creating a new counter
    fn update_staking_class_hash(ref self: TContractState, staking_class_hash_: ClassHash);
}

#[starknet::contract]
pub mod DeployFactory {
    // 0x5b9d30f08879118d9887358e4b8e3673d50919f503e537843058a9f43947a33
    use starknet::{ContractAddress, ClassHash, SyscallResultTrait, syscalls::deploy_syscall};
    use starknet::get_caller_address;

    #[storage]
    struct Storage {
        /// Store the constructor arguments of the contract to deploy
        owner: ContractAddress,
        stakingToken: ContractAddress,
        factoryOwner: ContractAddress,
        /// Store the class hash of the contract to deploy
        staking_class_hash: ClassHash,
    }

    #[constructor]
    fn constructor(ref self: ContractState, _owner: ContractAddress, _staking_token: ContractAddress, class_hash: ClassHash, factoryOwner_: ContractAddress) {
        self.stakingToken.write(_staking_token);
        self.owner.write(_owner);
        self.staking_class_hash.write(class_hash);
        self.factoryOwner.write(factoryOwner_);
    }

    #[abi(embed_v0)]
    impl Factory of super::IDeployFactory<ContractState> {
        fn create_staking_at(ref self: ContractState, owner_: ContractAddress, staking_token_: ContractAddress) -> ContractAddress {
            // Contructor arguments
            let mut constructor_calldata: Array::<felt252> = array![owner_.into(), staking_token_.into()];

            // Contract deployment
            let (deployed_address, _) = deploy_syscall(
                self.staking_class_hash.read(), 0, constructor_calldata.span(), false
            )
                .unwrap_syscall();

            deployed_address
        }
        
        // owner of staking contract will be the caller address
        fn create_staking(ref self: ContractState, staking_token_: ContractAddress) -> ContractAddress {
            let caller = get_caller_address();
            return (self.create_staking_at(caller, staking_token_));
        }

        fn update_constructor_args(ref self: ContractState, owner_: ContractAddress, staking_token_: ContractAddress) {
            let caller = get_caller_address();
            assert(caller == self.factoryOwner.read(), 'error calling function');
            self.stakingToken.write(staking_token_);
            self.owner.write(owner_);
        }

        fn update_staking_class_hash(ref self: ContractState, staking_class_hash_: ClassHash) {
            let caller = get_caller_address();
            assert(caller == self.factoryOwner.read(), 'error calling function');
            self.staking_class_hash.write(staking_class_hash_);
        }
    }
}
