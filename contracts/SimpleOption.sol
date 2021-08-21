pragma solidity ^0.6.11;

// imports 
import "https://github.com/smartcontractkit/chainlink/blob/develop/evm-contracts/src/v0.6/interfaces/LinkTokenInterface.sol";
import "https://github.com/smartcontractkit/chainlink/blob/master/evm-contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/math/SafeMath.sol";

contract SimpleOption {
    using SafeMath for uint;
    //Overflow safe operators
    using SafeMath for uint;
    //Pricefeed interfaces
    AggregatorV3Interface internal ethFeed;
    AggregatorV3Interface internal linkFeed;
    //Interface for LINK token functions
    LinkTokenInterface internal LINK;
    uint ethPrice;
    uint linkPrice;
    //Precomputing hash of strings
    bytes32 ethHash = keccak256(abi.encodePacked("ETH"));
    bytes32 linkHash = keccak256(abi.encodePacked("LINK"));
    address payable contractAddr;
    
    //Options stored in arrays of structs
    struct option {
        uint strike; //Price in USD (18 decimal places) option allows buyer to purchase tokens at
        uint premium; //Fee in contract token that option writer charges
        uint expiry; //Unix timestamp of expiration time
        uint amount; //Amount of tokens the option contract is for
        bool exercised; //Has option been exercised
        bool canceled; //Has option been canceled
        uint id; //Unique ID of option, also array index
        uint latestCost; //Helper to show last updated cost to exercise
        address payable writer; //Issuer of option
        address payable buyer; //Buyer of option
    }
    option[] public ethOpts;
    option[] public linkOpts;

    //Kovan feeds: https://docs.chain.link/docs/reference-contracts
    constructor() public {
        //ETH/USD Kovan feed
        ethFeed = AggregatorV3Interface(0x9326BFA02ADD2366b30bacB125260Af641031331);
        //LINK/USD Kovan feed
        linkFeed = AggregatorV3Interface(0x396c5E36DD0a0F5a5D33dae44368D4193f69a1F0);
        //LINK token address on Kovan
        LINK = LinkTokenInterface(0xa36085F69e2889c224210F603D836748e7dC0088);
        contractAddr = payable(address(this));
    }

    //Returns the latest LINK price
    function getLinkPrice() public view returns (uint) {
        (
            uint80 roundID, 
            int price,
            uint startedAt,
            uint timeStamp,
            uint80 answeredInRound
        ) = linkFeed.latestRoundData();
        // If the round is not complete yet, timestamp is 0
        require(timeStamp > 0, "Round not complete");
        //Price should never be negative thus cast int to unit is ok
        //Price is 8 decimal places and will require 1e10 correction later to 18 places
        return uint(price);
    }
    
    //Allows user to write a covered call option
    //Takes which token, a strike price(USD per token w/18 decimal places), premium(same unit as token), expiration time(unix) and how many tokens the contract is for
    function writeOption(string memory token, uint strike, uint premium, uint expiry, uint tknAmt) public payable {
        bytes32 tokenHash = keccak256(abi.encodePacked(token));
        require(tokenHash == ethHash || tokenHash == linkHash, "Only ETH and LINK tokens are supported");
        updatePrices();
        if (tokenHash == ethHash) {
            require(msg.value == tknAmt, "Incorrect amount of ETH supplied"); 
            uint latestCost = strike.mul(tknAmt).div(ethPrice.mul(10**10)); //current cost to exercise in ETH, decimal places corrected
            ethOpts.push(option(strike, premium, expiry, tknAmt, false, false, ethOpts.length, latestCost, msg.sender, address(0)));
        } else {
            require(LINK.transferFrom(msg.sender, contractAddr, tknAmt), "Incorrect amount of LINK supplied");
            uint latestCost = strike.mul(tknAmt).div(linkPrice.mul(10**10));
            linkOpts.push(option(strike, premium, expiry, tknAmt, false, false, linkOpts.length, latestCost, msg.sender, address(0)));
        }
    }
}