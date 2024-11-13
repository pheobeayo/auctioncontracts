use starknet::{SyscallResultTrait, ContractAddress, syscalls};
use core::serde::Serde;

#[starknet::interface]
trait IKillSwitchTrait<T> {
    fn is_active(self: @T) -> bool;
}

#[derive(Copy, Drop, starknet::Store, Serde)]
struct IKillSwitch {
    contract_address: ContractAddress,
}

impl IKillSwitchImpl of IKillSwitchTrait<IKillSwitch> {
    fn is_active(self: @IKillSwitch) -> bool {
        let mut call_data: Array<felt252> = ArrayTrait::new();
        let contract_address: ContractAddress = *self.contract_address;
        let mut res = syscalls::call_contract_syscall(
            contract_address, selector!("is_active"), call_data.span()
        )
            .unwrap_syscall();

        Serde::<bool>::deserialize(ref res).unwrap()
    }
}

#[starknet::interface]
trait ICounter<T> {
    fn get_counter(self: @T) -> u32;
    fn increase_counter(ref self: T);
}

#[starknet::contract]
mod Counter {
    use openzeppelin::access::ownable::OwnableComponent;
    use core::traits::Into;
    use core::starknet::event::EventEmitter;
    use super::ICounter;
    use starknet::ContractAddress;
    use super::IKillSwitchTrait;
    use super::IKillSwitch;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl InternalImpl = OwnableComponent::InternalImpl<ContractState>;
    
    #[storage]
    struct Storage {
        counter: u32,
        kill_switch: ContractAddress,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage
    }

    #[constructor]
    fn constructor(ref self: ContractState, input: u32, kill_switch: ContractAddress,  initial_owner: ContractAddress) {
        self.counter.write(input); 
        self.kill_switch.write(kill_switch);
        self.ownable.initializer(initial_owner)
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        CounterIncreased:CounterIncreased,
        #[flat]
        OwnableEvent: OwnableComponent::Event
    }

    #[derive(Drop, starknet::Event)]
    struct CounterIncreased {
        #[key]
        counter: u32,
    }

    #[abi(embed_v0)]
    impl ICounterImpl of super:: ICounter<ContractState>{
        fn get_counter(self: @ContractState) -> u32 {
            self.counter.read()
        } 

        fn increase_counter(ref self: ContractState) {
            self.ownable.assert_only_owner();
            let kill_switch_address = self.kill_switch.read();
            let active = IKillSwitch { contract_address: kill_switch_address }.is_active();

            assert!(!active, "Kill Switch is active");

            self.counter.write(self.counter.read() + 1);
            self.emit(CounterIncreased { counter: self.counter.read()});
            
        }       
    }
}