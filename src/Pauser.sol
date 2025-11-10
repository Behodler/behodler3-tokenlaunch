// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @notice Interface for Behodler pause/unpause functions
 */
interface IBehodler {
    function pause() external;
    function unpause() external;
}

/**
 * @title Pauser
 * @notice Emergency pause mechanism for Behodler3Tokenlaunch contract
 * @dev Allows anyone to pause the Behodler contract by burning EYE tokens
 *      This creates a cost barrier to prevent griefing while allowing emergency response
 */
contract Pauser is Ownable {
    // ============ STATE VARIABLES ============

    /// @notice The EYE token contract
    IERC20 public eyeToken;

    /// @notice The Behodler3Tokenlaunch contract that can be paused
    address public behodlerContract;

    /// @notice Amount of EYE tokens required to trigger pause
    uint256 public eyeBurnAmount;

    // ============ EVENTS ============

    event ConfigUpdated(uint256 newEyeBurnAmount, address newBehodlerContract);
    event PauseTriggered(address indexed triggeredBy, uint256 eyeBurned);
    event UnpauseTriggered(address indexed triggeredBy);

    // ============ CONSTRUCTOR ============

    /**
     * @notice Create a new Pauser contract
     * @param _eyeToken Address of the EYE token contract
     */
    constructor(address _eyeToken) Ownable(msg.sender) {
        require(_eyeToken != address(0), "Pauser: EYE token cannot be zero address");
        eyeToken = IERC20(_eyeToken);

        // Default to 1000 EYE tokens (assuming 18 decimals)
        eyeBurnAmount = 1000 * 1e18;
    }

    // ============ PUBLIC FUNCTIONS ============

    /**
     * @notice Pause the Behodler contract by burning EYE tokens
     * @dev Anyone can call this function if they have enough EYE tokens
     *      The EYE tokens will be burned from the caller's balance
     */
    function pause() external {
        require(behodlerContract != address(0), "Pauser: Behodler contract not configured");
        require(eyeBurnAmount > 0, "Pauser: EYE burn amount not configured");

        // Burn EYE tokens from caller
        require(
            eyeToken.transferFrom(msg.sender, address(0xdead), eyeBurnAmount),
            "Pauser: Failed to burn EYE tokens"
        );

        // Trigger pause on Behodler contract
        IBehodler(behodlerContract).pause();

        emit PauseTriggered(msg.sender, eyeBurnAmount);
    }

    /**
     * @notice Unpause the Behodler contract
     * @dev Only the owner can unpause to ensure controlled recovery
     */
    function unpause() external onlyOwner {
        require(behodlerContract != address(0), "Pauser: Behodler contract not configured");

        // Trigger unpause on Behodler contract
        IBehodler(behodlerContract).unpause();

        emit UnpauseTriggered(msg.sender);
    }

    // ============ OWNER FUNCTIONS ============

    /**
     * @notice Configure the Pauser contract parameters
     * @param _eyeBurnAmount New amount of EYE tokens required to pause
     * @param _behodlerContract New Behodler contract address
     */
    function config(uint256 _eyeBurnAmount, address _behodlerContract) external onlyOwner {
        require(_behodlerContract != address(0), "Pauser: Behodler contract cannot be zero address");
        require(_eyeBurnAmount > 0, "Pauser: EYE burn amount must be positive");

        eyeBurnAmount = _eyeBurnAmount;
        behodlerContract = _behodlerContract;

        emit ConfigUpdated(_eyeBurnAmount, _behodlerContract);
    }
}
