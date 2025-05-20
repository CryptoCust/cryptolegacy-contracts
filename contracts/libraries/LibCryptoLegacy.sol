/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/
pragma solidity 0.8.24;

import "./LibDiamond.sol";
import "../interfaces/IFeeRegistry.sol";
import "../interfaces/ICryptoLegacy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

library LibCryptoLegacy {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using SafeERC20 for IERC20;

    uint256 constant internal SHARE_BASE = 10000;
    uint256 constant internal MAX_CHAINS_ARRAY_LENGTH = 100;
    uint64 constant internal BENEFICIARY_SWITCH_TIMELOCK_DURATION = 1 days;
    uint8 constant internal CLAIM_FUNC_FLAG = 1;
    bytes32 constant internal CRYPTO_LEGACY_STORAGE_POSITION = keccak256("crypto_legacy.storage");
    bytes4 constant internal transferValueSelector = bytes4(uint32(1));
    bytes4 constant internal lockNftSelector = ILockChainGate(address(0)).lockLifetimeNft.selector;

    /**
     * @notice Retrieves the CryptoLegacy storage structure.
     * @dev Uses the fixed storage slot (CRYPTO_LEGACY_STORAGE_POSITION) to locate the storage.
     * @return storageStruct The reference to the CryptoLegacy storage structure.
     */
    function getCryptoLegacyStorage() internal pure returns (ICryptoLegacy.CryptoLegacyStorage storage storageStruct) {
        bytes32 position = CRYPTO_LEGACY_STORAGE_POSITION;
        assembly {
            storageStruct.slot := position
        }
    }

    /**
     * @notice Checks if a specific function is disabled.
     * @dev Performs a bitwise AND between the default disabled functions flag (cls.defaultFuncDisabled) and the provided _funcFlag.
     * If the result is non-zero, it reverts with ICryptoLegacy.DisabledFunc.
     * @param cls The CryptoLegacy storage structure containing configuration.
     * @param _funcFlag The flag value corresponding to the function to check.
     */
    function _checkDisabledFunc(ICryptoLegacy.CryptoLegacyStorage storage cls, uint8 _funcFlag) internal view {
        if ((cls.defaultFuncDisabled & _funcFlag) != 0) {
            revert ICryptoLegacy.DisabledFunc();
        }
    }

    /**
     * @notice Reverts if distribution has already started.
     * @dev Invokes _isDistributionStarted to determine if the token distribution is active.
     * Reverts with ICryptoLegacy.DistributionStarted if the distribution period has begun.
     * @param cls The CryptoLegacy storage structure.
     */
    function _checkDistributionStart(ICryptoLegacy.CryptoLegacyStorage storage cls) internal view {
        if (_isDistributionStarted(cls)) {
            revert ICryptoLegacy.DistributionStarted();
        }
    }

    /**
     * @notice Determines if the token distribution has begun.
     * @dev Checks that the distribution start timestamp is set (non‑zero) and that it is in the past compared to the current block timestamp.
     * @param cls The CryptoLegacy storage structure.
     * @return True if distribution has started, false otherwise.
     */
    function _isDistributionStarted(ICryptoLegacy.CryptoLegacyStorage storage cls) internal view returns(bool) {
        return cls.distributionStartAt != 0 && cls.distributionStartAt < uint64(block.timestamp);
    }

    /**
     * @notice Validates that the caller is the contract owner and that the initial fee has been paid.
     * @dev First invokes _checkDistributionStart to ensure that distribution has not begun.
     * Then it checks that cls.lastFeePaidAt is non‑zero (indicating that the initial fee was paid).
     * Finally, it verifies that the caller is the owner by calling _checkSenderOwner.
     */
    function _checkOwner() internal view {
        ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
        LibCryptoLegacy._checkDistributionStart(cls);
        if (cls.lastFeePaidAt == 0) {
            revert ICryptoLegacy.InitialFeeNotPaid();
        }
        _checkSenderOwner();
    }

    /**
     * @notice Checks that the caller is the contract owner.
     * @dev Retrieves the owner from the Diamond storage via LibDiamond and compares it with msg.sender.
     * Reverts with NotTheOwner if msg.sender is not the owner.
     */
    function _checkSenderOwner() internal view {
        if (LibDiamond.contractOwner() != msg.sender) {
            revert ICryptoLegacy.NotTheOwner();
        }
    }

    /**
     * @notice Ensures that the contract is not paused.
     * @dev Calls LibDiamond.getPause() to check if pausing is enabled.
     * Reverts with ICryptoLegacy.Pause if the contract is currently paused.
     */
    function _checkPause(ICryptoLegacy.CryptoLegacyStorage storage cls) internal view {
        if (LibCryptoLegacy._getPause(cls)) {
            revert ICryptoLegacy.Pause();
        }
    }

    function _setPause(ICryptoLegacy.CryptoLegacyStorage storage cls, bool _isPaused) internal {
        cls.isPaused = _isPaused;
        emit ICryptoLegacy.PauseSet(_isPaused);
    }

    function _getPause(ICryptoLegacy.CryptoLegacyStorage storage cls) internal view returns(bool) {
        return cls.isPaused;
    }

    /**
     * @notice Validates that the provided address is a registered beneficiary.
     * @dev Computes the keccak256 hash of _addr and checks for its presence in the beneficiaries set.
     * Reverts with NotTheBeneficiary if the address is not found.
     * @param cls The CryptoLegacy storage structure containing beneficiary data.
     * @param _addr The address to be verified as beneficiary.
     * @return beneficiary The hash of the provided address.
     */
    function _checkAddressIsBeneficiary(ICryptoLegacy.CryptoLegacyStorage storage cls, address _addr) internal view returns(bytes32 beneficiary){
        beneficiary = _addressToHash(_addr);
        if (!cls.beneficiaries.contains(beneficiary)) {
            revert ICryptoLegacy.NotTheBeneficiary();
        }
    }

    /**
     * @notice Checks if the token distribution is ready and the caller is a beneficiary.
     * @dev Validates that msg.sender is a registered beneficiary by calling _checkAddressIsBeneficiary,
     * then ensures that distribution is active via _checkDistributionReady.
     * @param cls The CryptoLegacy storage structure.
     * @return beneficiary The hash of msg.sender as beneficiary.
     */
    function _checkDistributionReadyForBeneficiary(ICryptoLegacy.CryptoLegacyStorage storage cls) internal view returns(bytes32 beneficiary){
        beneficiary = _checkAddressIsBeneficiary(cls, msg.sender);
        _checkDistributionReady(cls);
    }

    /**
     * @notice Checks if the distribution period is active.
     * @dev Retrieves the current block timestamp (as a uint64) and ensures that:
     * - distributionStartAt is non‑zero, and
     * - the current time is at least one second past distributionStartAt.
     * Reverts with TooEarly if conditions are not met.
     * @param cls The CryptoLegacy storage structure.
     */
    function _checkDistributionReady(ICryptoLegacy.CryptoLegacyStorage storage cls) internal view {
        if (!_isDistributionStarted(cls)) {
            revert ICryptoLegacy.TooEarly();
        }
    }

    /**
     * @notice Retrieves the total number of registered beneficiaries.
     * @dev Uses the length() method from the EnumerableSet for beneficiaries.
     * @param cls The CryptoLegacy storage structure.
     * @return count The total count of beneficiaries.
     */
    function _getBeneficiariesCount(ICryptoLegacy.CryptoLegacyStorage storage cls) internal view returns(uint256){
        return cls.beneficiaries.length();
    }

    /**
     * @notice Checks if the lifetime NFT is active for the owner.
     * @param cls The CryptoLegacy storage struct.
     * @param _owner The owner address.
     * @return isNftLocked True if lifetime NFT is locked, false otherwise.
     */
    function _isLifetimeActiveAndUpdate(ICryptoLegacy.CryptoLegacyStorage storage cls, address _owner) internal returns(bool isNftLocked) {
        ICryptoLegacyBuildManager bm = cls.buildManager;
        try bm.isLifetimeNftLockedAndUpdate{gas: _gasBySelector(cls, bm.isLifetimeNftLockedAndUpdate.selector)}(_owner) returns(bool _isNftLocked) {
            isNftLocked = _isNftLocked;
        } catch (bytes memory reason) {
            if (bytes4(reason) == ICryptoLegacyBuildManager.NotRegisteredCryptoLegacy.selector) {
                revert ICryptoLegacyBuildManager.NotRegisteredCryptoLegacy();
            }
            if (bytes4(reason) == ICryptoLegacyBuildManager.NotOwnerOfCryptoLegacy.selector) {
                revert ICryptoLegacyBuildManager.NotOwnerOfCryptoLegacy();
            }
            emit ICryptoLegacy.IsLifetimeNftLockedAndUpdateCatch(reason);
        }
    }

    /**
     * @notice Processes fee payment and updates fee-related timestamps.
     * @dev This function handles multiple fee scenarios:
     *   - If a lifetime NFT is active (determined by _isLifetimeActiveAndUpdate), it updates cls.lastFeePaidAt and emits FeePaidByLifetime.
     *   - Otherwise, it calculates a multiplier (mul) as:
     *         mul = max(1, (block.timestamp - cls.lastFeePaidAt) / cls.updateInterval)
     *     and if distribution has already started, it updates cls.lastFeePaidAt and calls _sendFeeByTransfer.
     *   - If distribution is not started and either the multiplier is at least 1 or msg.value is non‑zero:
     *         * It further updates cls.lastFeePaidAt by adding (mul * cls.updateInterval).
     *         * Attempts to update the updateFee from the buildManager.
     *         * Sets a gas limit calculated as: 12e5 + (4e5 * number of chain IDs).
     *         * Attempts to pay the fee via buildManager.payFee. On failure, it verifies the fee using _checkFee and falls back to _sendFeeByTransfer.
     * @param cls The CryptoLegacy storage structure.
     * @param _owner The owner's address initiating the fee payment.
     * @param _ref The referral address, if applicable.
     * @param _refShare The referral share percentage in basis points (denom: SHARE_BASE = 10000). Formula: (msg.value * _refShare) / SHARE_BASE.
     * @param _lockToChainIds Array of chain IDs for which the fee locking is applicable.
     * @param _crossChainFees Array of fee amounts for each corresponding chain in _lockToChainIds.
     */
    function _takeFee(ICryptoLegacy.CryptoLegacyStorage storage cls, address _owner, address _ref, uint256 _refShare, uint256[] memory _lockToChainIds, uint256[] memory _crossChainFees) internal {
        ICryptoLegacyBuildManager bm = cls.buildManager;
        if (_isLifetimeActiveAndUpdate(cls, _owner)) {
            _checkNoFee();
            cls.lastFeePaidAt = uint64(block.timestamp);
            emit ICryptoLegacy.FeePaidByLifetime(cls.invitedByRefCode, false, address(bm), cls.lastFeePaidAt);
            return;
        }
        uint64 mul;
        if (uint64(block.timestamp) > cls.lastFeePaidAt) {
            mul = (uint64(block.timestamp) - cls.lastFeePaidAt) / cls.updateInterval;
            if (mul < uint64(1)) {
                mul = uint64(1);
            }
        }
        if (_isDistributionStarted(cls)) {
            cls.lastFeePaidAt += mul * cls.updateInterval;
            return _sendFeeByTransfer(cls, address(bm), _ref, _refShare);
        }
        if (mul >= uint64(1) || msg.value != 0) {
            cls.lastFeePaidAt += mul * cls.updateInterval;

            try bm.getUpdateFee{gas: _gasBySelector(cls, bm.getUpdateFee.selector)}(cls.invitedByRefCode) returns(uint256 fee) {
                if (cls.updateFee != uint128(fee)) {
                    cls.updateFee = uint128(fee);
                }
            } catch (bytes memory reason) {
                emit ICryptoLegacy.GetUpdateFeeCatch(reason);
            }

            if (_lockToChainIds.length > MAX_CHAINS_ARRAY_LENGTH) {
                revert ICryptoLegacy.TooLongArray(MAX_CHAINS_ARRAY_LENGTH);
            }

            uint256 gasLimit = _gasBySelector(cls, bm.payFee.selector) + _lockToChainIds.length * _gasBySelector(cls, lockNftSelector);
            try bm.payFee{value: msg.value, gas: gasLimit}(cls.invitedByRefCode, _owner, uint256(mul), _lockToChainIds, _crossChainFees) returns(uint256 returned) {
                _transferFee(cls, msg.sender, returned);
                emit ICryptoLegacy.FeePaidByDefault(cls.invitedByRefCode, false, msg.value, returned, address(bm), cls.lastFeePaidAt);
            } catch (bytes memory reason) {
                _checkFee(uint256(cls.updateFee) * uint256(mul));
                _sendFeeByTransfer(cls, address(bm), address(0), 0);
                emit ICryptoLegacy.PayFeeCatch(reason);
            }
        }
    }

    /**
     * @notice Verifies that the provided fee amount matches the expected fee.
     * @dev Checks that msg.value is not less than _fee and that any surplus does not exceed 0.00001 ether.
     * Reverts with IncorrectFee if the fee is invalid.
     * @param _fee The required fee amount in wei.
     */
    function _checkFee(uint256 _fee) internal {
        if (msg.value < _fee || msg.value - _fee > 0.00001 ether) {
            revert ICryptoLegacy.IncorrectFee(_fee);
        }
    }

    /**
     * @notice Verifies that there's no fee provided by the sender.
     * @dev Checks that msg.value is zero. Reverts with NoValueAllowed if fee amount provided.
     */
    function _checkNoFee() internal {
        if (msg.value != 0) {
            revert ICryptoLegacy.NoValueAllowed();
        }
    }

    /**
     * @notice Processes fee payment via direct transfers.
     * @dev If msg.value is non‑zero, transfers a portion to the referral (if provided) calculated as:
     *         refValue = (msg.value * _refShare) / SHARE_BASE,
     * and sends the remainder to the build manager.
     * @param cls The CryptoLegacy storage structure.
     * @param _buildManagerAddress The address receiving the fee.
     * @param _ref The referral address to receive a portion of the fee.
     * @param _refShare The referral fee share in basis points (denom: SHARE_BASE = 10000).
     */
    function _sendFeeByTransfer(ICryptoLegacy.CryptoLegacyStorage storage cls, address _buildManagerAddress, address _ref, uint256 _refShare) internal {
        if (msg.value == 0) {
            emit ICryptoLegacy.SkipSendFeeByTransfer(_buildManagerAddress, msg.value);
            return;
        }
        if (_refShare > SHARE_BASE) {
            revert ICryptoLegacy.IncorrectRefShare();
        }
        uint256 value = msg.value;
        if (_ref != address(0)) {
            uint256 refValue = (value * _refShare) / SHARE_BASE;
            value -= refValue;
            _transferFee(cls, _ref, refValue);
            emit ICryptoLegacy.FeeSentToRefByTransfer(cls.invitedByRefCode, refValue, _ref);
        }
        _transferFee(cls, _buildManagerAddress, value);
        emit ICryptoLegacy.FeePaidByTransfer(cls.invitedByRefCode, false, value, _buildManagerAddress, cls.lastFeePaidAt);
    }

    function _transferFee(ICryptoLegacy.CryptoLegacyStorage storage cls, address _recipient, uint256 _value) internal {
        (bool success, bytes memory data) = payable(_recipient).call{value: _value, gas: _gasBySelector(cls, transferValueSelector)}(new bytes(0));
        if (!success) {
            revert ICryptoLegacy.TransferFeeFailed(data);
        }
    }

    /**
     * @notice Prepares the token distribution by adjusting the distributable amount based on the current token balance.
     * @dev Retrieves the TokenDistribution struct for a given token.
     * - If no distribution amount is set (amountToDistribute equals zero), it is set to the contract's current balance of the token.
     * - Otherwise, if the current balance exceeds the undistributed amount (amountToDistribute minus totalClaimedAmount),
     *   the excess is added to amountToDistribute.
     * - If the balance is lower, the distribution amount is adjusted to be the sum of the token balance and the already claimed amount.
     * @param cls The CryptoLegacy storage structure.
     * @param _token The address of the token to be prepared for distribution.
     * @return td The updated TokenDistribution storage reference for the token.
     */
    function _tokenPrepareToDistribute(ICryptoLegacy.CryptoLegacyStorage storage cls, address _token) internal returns(ICryptoLegacy.TokenDistribution storage td) {
        td = cls.tokenDistribution[_token];

        uint bal = IERC20(_token).balanceOf(address(this));
        uint totalClaimed = _getTotalClaimed(cls, _token);
        if (td.amountToDistribute == 0) {
            td.amountToDistribute = uint128(bal);
            return td;
        }
        uint balanceDiff;
        bool negativeRebase = bal < td.amountToDistribute - totalClaimed;
        if (negativeRebase) {
            balanceDiff = (td.amountToDistribute - totalClaimed) - bal;
        } else {
            balanceDiff = bal - (td.amountToDistribute - totalClaimed);
        }
        if (bal == 0 || (balanceDiff * 1 gwei / bal) < 1e3) {
            return td;
        }
        
        if (negativeRebase) {
            uint balanceRatio = bal * 1 ether / td.lastBalance;
            bytes32[] memory beneficiaries = cls.beneficiaries.values();
            totalClaimed = 0;
            for (uint i = 0; i < beneficiaries.length; i++) {
                uint newClaimed = balanceRatio * _getBeneficiaryClaimed(cls, beneficiaries[i], _token) / 1 ether;
                _setBeneficiaryClaimed(cls, beneficiaries[i], _token, newClaimed);
                totalClaimed += newClaimed;
            }
        }
        td.amountToDistribute = uint128(bal + totalClaimed);
    }

    function _getBeneficiaryClaimed(ICryptoLegacy.CryptoLegacyStorage storage cls, bytes32 _hash, address _token) internal view returns(uint claimed) {
        return cls.beneficiaryVesting[cls.originalBeneficiaryHash[_hash]].tokenAmountClaimed[_token];
    }
    function _setBeneficiaryClaimed(ICryptoLegacy.CryptoLegacyStorage storage cls, bytes32 _hash, address _token, uint _amount) internal {
        cls.beneficiaryVesting[cls.originalBeneficiaryHash[_hash]].tokenAmountClaimed[_token] = _amount;
    }

    function _getTotalClaimed(ICryptoLegacy.CryptoLegacyStorage storage cls, address _token) internal view returns(uint totalClaimed) {
        bytes32[] memory beneficiaries = cls.beneficiaries.values();
        for (uint i = 0; i < beneficiaries.length; i++) {
            totalClaimed += _getBeneficiaryClaimed(cls, beneficiaries[i], _token);
        }
    }

    /**
     * @notice Calculates the start and end dates for beneficiary token claims.
     * @dev The start date is computed as: distributionStartAt + claimDelay.
     * The end date is computed as: startDate + vestingPeriod (from beneficiary configuration).
     * @param cls The CryptoLegacy storage structure.
     * @param bc The BeneficiaryConfig struct containing claimDelay and vestingPeriod.
     * @return startDate The timestamp when claims begin.
     * @return endDate The timestamp when claims end.
     */
    function _getStartAndEndDate(ICryptoLegacy.CryptoLegacyStorage storage cls, ICryptoLegacy.BeneficiaryConfig storage bc) internal view returns(uint64 startDate, uint64 endDate) {
        startDate = cls.distributionStartAt + bc.claimDelay;
        endDate = startDate + bc.vestingPeriod;
    }

    /**
     * @notice Calculates the vested token amount, claimed token amount, and total eligible token amount for a beneficiary.
     * @dev First determines the vesting percentage (vestingBps) using the following logic:
     *   - If the current time is before _startDate, vestingBps is 0.
     *   - If the current time is after _endDate, vestingBps equals SHARE_BASE (i.e. fully vested, where SHARE_BASE = 10000).
     *   - Otherwise, vestingBps = ((block.timestamp - _startDate) * SHARE_BASE) / bc.vestingPeriod.
     * Then, totalAmount is computed as: (td.amountToDistribute * bc.shareBps) / SHARE_BASE.
     * Finally, vestedAmount = (totalAmount * vestingBps) / SHARE_BASE and claimedAmount is obtained from bv.tokenAmountClaimed.
     * @param td The TokenDistribution struct for the token.
     * @param bc The BeneficiaryConfig struct containing vesting parameters.
     * @param bv The BeneficiaryVesting struct that tracks the claimed token amounts.
     * @param _token The token address.
     * @param _startDate The timestamp marking the start of vesting.
     * @param _endDate The timestamp marking the end of vesting.
     * @return totalAmount The total amount of tokens allocated for the beneficiary.
     * @return claimedAmount The amount of tokens that have already been claimed.
     * @return vestedAmount The amount of tokens that have vested so far.
     */
    function _getVestedAndClaimedAmount(ICryptoLegacy.TokenDistribution storage td, ICryptoLegacy.BeneficiaryConfig storage bc, ICryptoLegacy.BeneficiaryVesting storage bv, address _token, uint64 _startDate, uint64 _endDate) internal view returns (uint256 totalAmount, uint256 claimedAmount, uint256 vestedAmount) {
        uint256 vestingBps;
        if (_startDate > uint64(block.timestamp)) {
            vestingBps = 0;
        } else {
            vestingBps = uint64(block.timestamp) > _endDate ? LibCryptoLegacy.SHARE_BASE : (uint64(block.timestamp) - _startDate) * LibCryptoLegacy.SHARE_BASE / bc.vestingPeriod;
        }
        totalAmount = td.amountToDistribute * bc.shareBps / LibCryptoLegacy.SHARE_BASE;
        vestedAmount = totalAmount * vestingBps / LibCryptoLegacy.SHARE_BASE;
        claimedAmount = vestedAmount - bv.tokenAmountClaimed[_token];
    }

    /**
     * @notice Retrieves the vesting schedule for a beneficiary based on its hashed identity.
     * @dev Uses the originalBeneficiaryHash mapping to look up the BeneficiaryVesting struct.
     * @param cls The CryptoLegacy storage structure.
     * @param _beneficiary The hashed beneficiary address.
     * @return bc The BeneficiaryConfig struct containing beneficiary info.
     * @return bv The BeneficiaryVesting struct containing claimed token information.
     */
    function _getBeneficiaryConfigAndVesting(
        ICryptoLegacy.CryptoLegacyStorage storage cls,
        bytes32 _beneficiary
    ) internal view returns(
        ICryptoLegacy.BeneficiaryConfig storage bc,
        ICryptoLegacy.BeneficiaryVesting storage bv
    ) {
        bc = cls.beneficiaryConfig[_beneficiary];
        if (bc.shareBps == 0) {
            revert ICryptoLegacy.BeneficiaryNotExist();
        }
        bv = cls.beneficiaryVesting[cls.originalBeneficiaryHash[_beneficiary]];
    }

    /**
     * @notice Registers or unregisters an individual entity in the beneficiary registry.
     * @dev Retrieves the beneficiary registry via buildManager (if available) and then calls:
     *   - setCryptoLegacyOwner if _entityType is OWNER,
     *   - setCryptoLegacyBeneficiary if BENEFICIARY, or
     *   - setCryptoLegacyGuardian if GUARDIAN.
     * Uses a fixed gas limit for each call.
     * @param cls The CryptoLegacy storage structure.
     * @param _hash The keccak256 hash of the entity's address.
     * @param _entityType The type of entity (OWNER, BENEFICIARY, or GUARDIAN).
     * @param _isAdd True to add the entity, false to remove.
     */
    function _setCryptoLegacyToBeneficiaryRegistry(ICryptoLegacy.CryptoLegacyStorage storage cls, bytes32 _hash, IBeneficiaryRegistry.EntityType _entityType, bool _isAdd) internal {
        IBeneficiaryRegistry br = _getBeneficiaryRegistry(cls);
        if (address(br) == address(0)) {
            emit ICryptoLegacy.BeneficiaryRegistryNotDefined();
            return;
        }
        if (_entityType == IBeneficiaryRegistry.EntityType.OWNER) {
            try br.setCryptoLegacyOwner{gas: _gasBySelector(cls, br.setCryptoLegacyOwner.selector)}(_hash, _isAdd) {} catch (bytes memory reason) {
                emit ICryptoLegacy.SetCryptoLegacyOwnerCatch(reason);
            }
        } else if (_entityType == IBeneficiaryRegistry.EntityType.BENEFICIARY) {
            try br.setCryptoLegacyBeneficiary{gas: _gasBySelector(cls, br.setCryptoLegacyBeneficiary.selector)}(_hash, _isAdd) {} catch (bytes memory reason) {
                emit ICryptoLegacy.SetCryptoLegacyBeneficiaryCatch(reason);
            }
        } else if (_entityType == IBeneficiaryRegistry.EntityType.GUARDIAN) {
            try br.setCryptoLegacyGuardian{gas: _gasBySelector(cls, br.setCryptoLegacyGuardian.selector)}(_hash, _isAdd) {} catch (bytes memory reason) {
                emit ICryptoLegacy.SetCryptoLegacyGuardianCatch(reason);
            }
        }
    }

    /**
     * @notice Updates the list of recovery addresses in the beneficiary registry.
     * @dev Retrieves the beneficiary registry from buildManager (if available) and calls setCryptoLegacyRecoveryAddresses.
     * The gas limit is scaled by the total number of hashes (old plus new) plus one.
     * @param cls The CryptoLegacy storage structure.
     * @param _oldHashes Array of hashes representing the old recovery addresses.
     * @param _newHashes Array of hashes representing the new recovery addresses.
     * @param _entityType The entity type; for this operation it should be RECOVERY.
     */
    function _setCryptoLegacyListToBeneficiaryRegistry(ICryptoLegacy.CryptoLegacyStorage storage cls, bytes32[] memory _oldHashes, bytes32[] memory _newHashes, IBeneficiaryRegistry.EntityType _entityType) internal {
        IBeneficiaryRegistry br = _getBeneficiaryRegistry(cls);
        if (address(br) == address(0)) {
            emit ICryptoLegacy.BeneficiaryRegistryNotDefined();
            return;
        }
        if (_entityType == IBeneficiaryRegistry.EntityType.RECOVERY) {
            uint256 gasLimit = _gasBySelector(cls, br.setCryptoLegacyRecoveryAddresses.selector) * (_oldHashes.length + _newHashes.length + 1);
            try br.setCryptoLegacyRecoveryAddresses{gas: gasLimit}(_oldHashes, _newHashes) {} catch (bytes memory reason) {
                emit ICryptoLegacy.SetCryptoLegacyRecoveryAddressesCatch(reason);
            }
        }
    }

    function _getBeneficiaryRegistry(ICryptoLegacy.CryptoLegacyStorage storage cls) internal returns(IBeneficiaryRegistry br) {
        ICryptoLegacyBuildManager bm = cls.buildManager;
        try bm.beneficiaryRegistry{gas: _gasBySelector(cls, bm.beneficiaryRegistry.selector)}() returns(IBeneficiaryRegistry _br) {
            br = _br;
        } catch (bytes memory reason) {
            emit ICryptoLegacy.BeneficiaryRegistryCatch(reason);
        }
    }

    function _gasBySelector(ICryptoLegacy.CryptoLegacyStorage storage cls, bytes4 _selector) internal view returns(uint) {
        return _gasWithoutMultiplierBySelector(cls, _selector) * uint(cls.gasLimitMultiplier == 0 ? 1 : cls.gasLimitMultiplier);
    }

    /**
    * @notice Determines a base gas amount for a given function selector, before applying any multiplier.
    * @dev Returns a preset gas value in wei units, depending on which function selector is matched.
    *      - If `payFee` selector, returns 1,200,000 (12e5).
    *      - If `getUpdateFee` selector, returns 600,000 (6e5).
    *      - If `transferValueSelector`, returns 40,000 (4e4).
    *      - If any of `lockNftSelector`, `setCryptoLegacyOwner.selector`, `setCryptoLegacyGuardian.selector`, 
    *        or `setCryptoLegacyBeneficiary.selector`, returns 400,000 (4e5).
    *      - Otherwise, returns 200,000 (2e5).
    * @param cls Reference to the CryptoLegacy storage, used mainly to read build manager’s function selectors.
    * @param _selector The function selector for which we want a preset base gas limit.
    * @return The base gas limit (in units) for that function selector, before any multiplier is applied.
    */
    function _gasWithoutMultiplierBySelector(ICryptoLegacy.CryptoLegacyStorage storage cls, bytes4 _selector) internal view returns(uint) {
        if (cls.buildManager.payFee.selector == _selector) {
            return 12e5;
        }
        if (cls.buildManager.getUpdateFee.selector == _selector) {
            return 6e5;
        }
        if (transferValueSelector == _selector) {
            return 4e4;
        }
        IBeneficiaryRegistry br = IBeneficiaryRegistry(address(0));
        if (
            lockNftSelector == _selector ||
            br.setCryptoLegacyOwner.selector == _selector ||
            br.setCryptoLegacyGuardian.selector == _selector ||
            br.setCryptoLegacyBeneficiary.selector == _selector
        ) {
            return 4e5;
        }
        return 2e5;
    }

    /**
     * @notice Updates the owner in the beneficiary registry.
     * @dev Unregisters the previous owner and registers the new owner using _setCryptoLegacyToBeneficiaryRegistry.
     * @param cls The CryptoLegacy storage structure.
     * @param _newOwner The address of the new owner.
     */
    function _updateOwnerInBeneficiaryRegistry(ICryptoLegacy.CryptoLegacyStorage storage cls, address _newOwner) internal {
        address oldOwner = LibDiamond.contractOwner();
        _setCryptoLegacyToBeneficiaryRegistry(cls, LibCryptoLegacy._addressToHash(oldOwner), IBeneficiaryRegistry.EntityType.OWNER, false);
        _setCryptoLegacyToBeneficiaryRegistry(cls, LibCryptoLegacy._addressToHash(_newOwner), IBeneficiaryRegistry.EntityType.OWNER, true);
    }

    /**
     * @notice Transfers treasury tokens from specified holders to the legacy contract.
     * @dev Iterates over each token and holder combination, transferring the minimum of the holder's available balance
     * and the approved allowance from the holder to the contract.
     * After transfers, adjusts token distribution via _tokenPrepareToDistribute, emits a transfer event, and records the block number.
     * @param cls The CryptoLegacy storage structure.
     * @param _holders Array of addresses holding the tokens.
     * @param _tokens Array of ERC20 token addresses to be transferred.
     */
    function _transferTreasuryTokensToLegacy(
        ICryptoLegacy.CryptoLegacyStorage storage cls,
        address[] memory _holders,
        address[] memory _tokens
    ) internal {
        for (uint i = 0; i < _tokens.length; i++) {
            IERC20 t = IERC20(_tokens[i]);
            for (uint j = 0; j < _holders.length; j++) {
                uint256 availableBalance = t.balanceOf(_holders[j]);
                uint256 allowance = t.allowance(_holders[j], address(this));
                if (availableBalance > allowance) {
                    availableBalance = allowance;
                }
                if (availableBalance == 0) {
                    continue;
                }
                t.safeTransferFrom(_holders[j], address(this), availableBalance);
            }
            ICryptoLegacy.TokenDistribution storage td = LibCryptoLegacy._tokenPrepareToDistribute(cls, _tokens[i]);
            td.lastBalance = uint128(IERC20(_tokens[i]).balanceOf(address(this)));
        }
        emit ICryptoLegacy.TransferTreasuryTokensToLegacy(_holders, _tokens);
        cls.transfersGotByBlockNumber.push(uint64(block.number));
    }

    /**
     * @notice Transfers tokens from the legacy contract to designated recipients.
     * @dev Iterates over an array of TokenTransferTo structs and transfers the specified token amounts.
     * Emits a transfer event and records the block number of the transfer.
     * @param cls The CryptoLegacy storage structure.
     * @param _transfers Array of TokenTransferTo structs containing token, recipient, and amount details.
     */
    function _transferTokensFromLegacy(
        ICryptoLegacy.CryptoLegacyStorage storage cls,
        ICryptoLegacy.TokenTransferTo[] memory _transfers
    ) internal {
        for (uint i = 0; i < _transfers.length; i++) {
            IERC20 t = IERC20(_transfers[i].token);
            t.safeTransfer(_transfers[i].recipient, _transfers[i].amount);
        }
        emit ICryptoLegacy.TransferTokensFromLegacy(_transfers);
        cls.transfersGotByBlockNumber.push(uint64(block.number));
    }

    /**
     * @notice Computes and returns the keccak256 hash of the given address.
     * @dev Uses abi.encode to safely encode the address before hashing.
     * @param _addr The address to be hashed.
     * @return The keccak256 hash of _addr.
     */
    function _addressToHash(address _addr) internal pure returns(bytes32) {
        return keccak256(abi.encode(_addr));
    }

    function _addressWithSaltToHash(address _addr, bytes32 _salt) internal pure returns(bytes32) {
        return keccak256(abi.encodePacked(_addr, _salt));
    }
}