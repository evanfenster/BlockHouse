// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract TokenizedUSTreasuryBond is ERC20, AccessControl, ReentrancyGuard {
    // Define roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");

    // decimals used for interest payments
    uint256 public constant INTEREST_DECIMALS = 1e18;
    // bond maturity date
    uint256 public maturity;
    // par value of the bond
    uint public par;
    // interest rate of the bond
    uint256 public interestRate;
    // token used to pay interest and principal
    address public paymentToken;

    // last time interest was paid
    uint256 public lastInterestPayment;
    // time between interest payments, set to 26 weeks for semi-annual payments by default
    uint256 public interestPaymentInterval = 26 weeks;

    // mapping of addresses to the amount of interest they are eligible to claim
    mapping(address => uint256) private interestClaimable;

    // mapping of addresses to their auto-claim preference
    mapping(address => bool) private autoClaimInterest;

    // event emitted when interest is paid to an address's interestClaimable balance
    event InterestPaid(address indexed user, uint256 interest);
    // event emitted when interest is claimed by an address and officially transferred to them
    event InterestClaimed(address indexed user, uint256 interest);

    // used to keep track of all bond holders
    mapping(address => uint256) private bondHoldersIndices;
    address[] private bondHolders;

    // modifier to check if the bond is past maturity
    modifier pastMaturity() {
        require(isMature(), "Bond is not mature");
        _;
    }

    // modifier to check if interest claimable can be updated  
    modifier interestValid() {
        require(block.timestamp >= lastInterestPayment + interestPaymentInterval, "It's too early to pay the next interest payment");
        _;
    }

    // used to initialize the contract
    constructor(
        string memory name,
        string memory symbol,
        uint _parValue,
        uint256 _interestRate,
        uint256 _maturity,
        address _paymentToken,
        uint256 maxSupply,
        uint256 _interestPaymentInterval
    ) ERC20(name, symbol) {
        require(_interestRate > 0, "Interest rate must be positive");
        require(_maturity > block.timestamp, "Maturity date must be in the future");
        require(maxSupply > 0, "Max supply must be greater than zero");

        maturity = _maturity;
        par = _parValue;
        interestRate = _interestRate;
        paymentToken = _paymentToken;
        interestPaymentInterval = _interestPaymentInterval;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ADMIN_ROLE, msg.sender);
        _setupRole(ISSUER_ROLE, msg.sender);

        // Transfers 100% of the bonds to the address deploying this contract.
        _mint(this, maxSupply);
    }

    // this is used to add those interest values to the interestClaimable mapping for users holding the bonds at the time of the interest payment
    // settle next round of interest payments if it's a valid time
    function interestPayment() public interestValid onlyRole(ISSUER_ROLE) {

        for (uint256 i = 0; i < bondHolders.length; i++) {
            address account = bondHolders[i];
            uint256 interestPayment = balanceOf(account).mul(interestRate).div(INTEREST_DECIMALS);
            interestClaimable[account] += interestPayment;

            emit InterestPaid(account, interestPayment);

            if (autoClaimInterest[account]) {
                _transferInterest(account, interestPayment);
                interestClaimable[account] = 0;
            }

        }

        lastInterestPayment = block.timestamp;
    }

    // used by a user to claim their current amount of interest claimable
    function claimInterest() external nonReentrant {
        require(interestClaimable[msg.sender] > 0, "No interest claimable");

        uint256 interest = interestClaimable[msg.sender];
        interestClaimable[msg.sender] = 0;

        _transferInterest(msg.sender, interest);
    }

    // redeem bond par value after maturity
    function redeem(uint256 bonds) external pastMaturity nonReentrant {
        require(bonds <= balanceOf(msg.sender), "Not enough bonds to redeem");

        _burn(msg.sender, bonds);
        require(paymentToken.transfer(msg.sender, bonds.mul(par)), "Transfer failed");
    }

    // sets the user's auto-claim preference
    function setAutoClaimInterest(bool autoClaim) external {
        autoClaimInterest[msg.sender] = autoClaim;
    }

    // returns true if the bond is mature
    function isMature() public view returns (bool isBondMature) {
        isBondMature = block.timestamp >= maturity;
    }

    // override the transfer function to update the bondHolders array
    function _transfer(address sender, address recipient, uint256 amount) internal override {
        super._transfer(sender, recipient, amount);

        // Add recipient to the list of bond holders if not already present
        if (bondHoldersIndices[recipient] == 0 && recipient != address(0)) {
            bondHolders.push(recipient);
            bondHoldersIndices[recipient] = bondHolders.length;
        }
    }

    // internal function to transfer interest
    function _transferInterest(address recipient, uint256 interest) internal {
        require(paymentToken.transfer(recipient, interest), "Transfer failed");
        emit InterestClaimed(recipient, interest);
    }
}