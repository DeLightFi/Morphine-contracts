%lang starknet

from starkware.starknet.common.syscalls import (
    get_block_timestamp,
    get_caller_address,
    call_contract,
)

from starkware.cairo.common.uint256 import ALL_ONES, Uint256, uint256_eq, uint256_lt, uint256_le
from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.cairo.common.bitwise import bitwise_and, bitwise_xor, bitwise_or
from starkware.cairo.common.math import assert_not_zero
from openzeppelin.token.erc20.IERC20 import IERC20
from openzeppelin.security.safemath.library import SafeUint256

from morphine.utils.RegisteryAccess import RegisteryAccess
from morphine.utils.safeerc20 import SafeERC20
from morphine.utils.various import DEFAULT_FEE_INTEREST, DEFAULT_FEE_LIQUIDATION, DEFAULT_LIQUIDATION_PREMIUM, DEFAULT_FEE_LIQUIDATION_EXPIRED_PREMIUM, DEFAULT_FEE_LIQUIDATION_EXPIRED, PRECISION, DEFAULT_LIMIT_PER_BLOCK_MULTIPLIER

from morphine.interfaces.IRegistery import IRegistery
from morphine.interfaces.IDripManager import IDripManager
from morphine.interfaces.IDripTransit import IDripTransit
from morphine.interfaces.IDripConfigurator import IDripConfigurator, AllowedToken
from morphine.interfaces.IAdapter import IAdapter
from morphine.interfaces.IPool import IPool
from morphine.interfaces.IOracleTransit import IOracleTransit

/// @title Pool Configurator
/// @author 0xSacha
/// @dev Contract Used to Manage Pool parameters
/// @custom:experimental This is an experimental contract.

// Events


@event
func NewBorrowModuleConnected(borrow_module: felt) {
}

@event
func BorrowModuleForbidden(borrow_module: felt) {
}

@event
func NewWithdrawFee(value: Uint256) {
}

@event
func NewExpectedLiquidityLimit(value: Uint256) {
}

@event
func NewInterestRateModel(interest_rate_model: felt) {
}

@event
func BorrowFrozen() {
}

@event
func BorrowUnfrozen() {
}

@event
func PoolConfiguratorUpgraded(new_pool_configurator: felt) {
}



// Storage

@storage_var
func pool() -> (pool : felt) {
}





//Constructor

// @notice: Constructor will be called when the contract is deployed
// @param drip_manager: Address of the DripManager contract
// @param drip_transit: Address of the DripTransit contract
// @param _minimum_borrowed_amount: Minimum amount of tokens that can be borrowed (Uint256)
// @param _maximum_borrowed_amount: Maximum amount of tokens that can be borrowed (Uint256)
// @param _allowed_tokens: Array of allowed tokens
// @param _allowed_tokens_len: Length of the array of allowed tokens (AllowedToken*)
@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _pool: felt) {
    alloc_locals;
    pool.write(_pool);
    let (pool_) = IDripManager.getPool(_drip_manager);
    let (registery_) = IPool.getRegistery(pool_);
    RegisteryAccess.initializer(registery_);
    

    return();
}



// @notice: Connect new borrow module to the pool
// @param token_address: Address of the borrow module to connect(felt)
@external
func connectBorrowModule{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(_borrow_module: felt){
    RegisteryAccess.assert_only_owner();

    with_attr error_message("zero address for borrow module"){
        assert_not_zero(_borrow_module);
    }

    let (pool_) = pool.read();
    let (pool_from_borrow_manager_) = IDripManager.getPool(_borrow_module);
    with_attr error_message("incompatible pool for borrow module") {
        assert pool_ = pool_from_borrow_manager_;
    }

    let (borrow_module_mask_) = IPool.borrowModuleMask(_borrow_module);
    let (is_lt_) = uint256_lt(Uint256(0, 0), borrow_module_mask_);
    with_attr error_message("Borrow module already added") {
        assert is_lt_ = 0;
    }
    IPool.connectBorrowModule(_borrow_module);
    NewBorrowModuleConnected.emit(_borrow_module);
    return();
}

// @notice: Forbid a borrow module
// @param: _borrow_module Address of the borrow module to forbid (felt)
@external
func forbidBorrowModule{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*}(_borrow_module: felt){
    alloc_locals;
    RegisteryAccess.assert_only_owner();
    let (pool_) = pool.read();
    let (borrow_module_mask_) = IPool.borrowModuleMask(pool_, _borrow_module);
    let (forbidden_mask_) = IPool.forbiddenMask(pool_);
    
    let (is_eq1_) = uint256_eq(Uint256(0,0),borrow_module_mask_);
    with_attr error_message("borrow module not allowed"){
        assert is_eq1_ = 0;
    }

    let (low_) = bitwise_and(forbidden_mask_.low, borrow_module_mask_.low);
    let (high_) = bitwise_and(forbidden_mask_.high, borrow_module_mask_.high);
    let (is_lt_) = uint256_lt(Uint256(0,0), Uint256(low_, high_));
    if (is_lt_ == 0){
        let (low_) = bitwise_or(forbidden_mask_.low, borrow_module_mask_.low);
        let (high_) = bitwise_or(forbidden_mask_.high, borrow_module_mask_.high);
        IPool.setForbidMask(pool_, Uint256(low_, high_));
        BorrowModuleForbidden.emit(_borrow_module);
        return();
    }
    return();
}

// @notice set withdraw fee for pool
// @param _base_withdraw_fee fee when withdraw pool
@external
func setWithdrawFee{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _base_withdraw_fee: Uint256
) {
    RegisteryAccess.assert_only_owner();
    let (pool_) = pool.read();
    let (max_fee_,_) = unsigned_div_rem(PRECISION, 100);
    let (is_allowed_amount1_) = uint256_le(_base_withdraw_fee, Uint256(max_fee_, 0));
    let (is_allowed_amount2_) = uint256_le(Uint256(0, 0), _base_withdraw_fee);
    with_attr error_message("withdraw fee 1 max") {
        assert is_allowed_amount1_ * is_allowed_amount2_ = 1;
    }
    IPool.setWithdrawFee(pool_, _base_withdraw_fee);
    return ();
}

// @notice liquidity limit in pool
// @param _expected_liquidity_limit liquidity limit in pool
@external
func setExpectedLiquidityLimit{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _expected_liquidity_limit: Uint256
) {
    RegisteryAccess.assert_only_owner();
    let (pool_) = pool.read();
    IPool.setExpectedLiquidityLimit(pool_, _expected_liquidity_limit);
    NewExpectedLiquidityLimit.emit(_expected_liquidity_limit)
    return ();
}

// @notice update interest rate model for pool
// @param _interest_rate_model modify interest rate in pool
@external
func updateInterestRateModel{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    _interest_rate_model: felt
) {
    RegisteryAccess.assert_only_owner();
    with_attr error_message("zero address"){
        assert_not_zero(_interest_rate_model);
    }
    let (pool_) = pool.read();
    IPool.updateInterestRateModel(pool_, _interest_rate_model);
    NewInterestRateModel.emit(_interest_rate_model);
    return ();
}


// @notice freeze borrow from pool
@external
func freezeBorrow{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    RegisteryAccess.assert_only_owner();
    let (pool_) = pool.read();
    let (is_frozen_) = IPool.isBorrowFrozen();
    with_attr error_message("borrow frozen") {
        assert is_frozen_ = 0;
    }
    IPool.freezeBorrow(pool_);
    BorrowFrozen.emit();
    return ();
}

// @notice unfreeze borrow from pool
@external
func unfreezeBorrow{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    RegisteryAccess.assert_only_owner();
    let (pool_) = pool.read();
    let (is_frozen_) = IPool.isBorrowFrozen();
    with_attr error_message("borrow not frozen") {
        assert is_frozen_ = 1;
    }
    IPool.unfreezeBorrow(pool_);
    BorrowUnfrozen.emit();
    return ();
}

// @notice: Upgrade Pool Configurator
// @param: _pool_configurator new pool configurator
@external
func upgradeConfigurator{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(_pool_configurator: felt){
    alloc_locals;
    RegisteryAccess.assert_only_owner();
    with_attr error_message("zero address"){
        assert_not_zero(_pool_configurator);
    }
    let (pool_) = pool.read();
    let (pool_from_pool_configurator_) = IPoolConfigurator.getPool(_pool_configurator);
    with_attr error_message("wrong pool from pool configurator"){
        assert pool_from_pool_configurator_ = pool_;
    }
    IPool.setConfigurator(pool, _pool_configurator);
    PoolConfiguratorUpgraded.emit(_pool_configurator);
    return();
}


// @notice get associated pool 
@view
func getPool{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (pool: felt){
    let (pool_) = pool.read();
    return (pool_,);
}