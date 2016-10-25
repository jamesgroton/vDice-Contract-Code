
import "./Token.sol";

pragma solidity ^0.4.0;
/*
The ProfitContainer contract receives profits from the vDice games and allows a
a fair distribution between token holders.
*/

contract Ownable {
  address public owner;

  function Ownable() {
    owner = msg.sender;
  }

  modifier onlyOwner() {
    if (msg.sender == owner)
      _;
  }

  function transferOwnership(address _newOwner)
      external
      onlyOwner {
      if (_newOwner == address(0x0)) throw;
      owner = _newOwner;
  }

}

contract ProfitContainer is Ownable {
    uint public currentEpoch;
    //This is to mitigate supersend and the possibility of
    //different payouts for same token ownership during payout phase
    uint public initEpochBalance;
    mapping (address => uint) lastPaidOutEpoch;
    Token public tokenCtr;

    event WithdrawalEnabled();
    event ProfitWithdrawn(address tokenHolder, uint amountPaidOut);
    event TokenContractChanged(address newTokenContractAddr);

    // The modifier onlyNotPaidOut prevents token holders who have
    // already withdrawn their share of profits in the epoch, to cash
    // out additional shares.
    modifier onlyNotPaidOut {
        if (lastPaidOutEpoch[msg.sender] == currentEpoch) throw;
        _;
    }

    // The modifier onlyLocked prevents token holders from collecting
    // their profits when the token contract is in an unlocked state
    modifier onlyLocked {
        if (!tokenCtr.lock()) throw;
        _;
    }

    // The modifier resetPaidOut updates the currenct epoch, and
    // enables the smart contract to track when a token holder
    // has already received their fair share of profits or not
    // and sets the balance for the epoch using current balance
    modifier resetPaidOut {
        if(currentEpoch < tokenCtr.numOfCurrentEpoch()) {
            currentEpoch = tokenCtr.numOfCurrentEpoch();
            initEpochBalance = this.balance;
            WithdrawalEnabled();
        }
        _;
    }

    function ProfitContainer(address _token) {
        tokenCtr = Token(_token);
    }

    function ()
        payable {

    }

    // The function withdrawalProfit() enables token holders
    // to collect a fair share of profits from the ProfitContainer,
    // proportional to the amount of tokens they own. Token holders
    // will be able to collect their profits only once
    function withdrawalProfit()
        external
        resetPaidOut
        onlyLocked
        onlyNotPaidOut {
        uint currentEpoch = tokenCtr.numOfCurrentEpoch();
        uint tokenBalance = tokenCtr.balanceOf(msg.sender);
        uint totalSupply = tokenCtr.totalSupply();

        if (tokenBalance == 0) throw;

        lastPaidOutEpoch[msg.sender] = currentEpoch;

        // Overflow risk only exists if balance is greater than
        // 1e+33 ether, assuming max of 96M tokens minted.
        // Functions throws, as such a state should never be reached
        // Unless significantly more tokens are minted
        if (!safeToMultiply(tokenBalance, initEpochBalance)) throw;
        uint senderPortion = (tokenBalance * initEpochBalance);

        uint amountToPayOut = senderPortion / totalSupply;

        if(!msg.sender.send(amountToPayOut)) {
            throw;
        }

        ProfitWithdrawn(msg.sender, amountToPayOut);
    }

    function changeTokenContract(address _newToken)
        external
        onlyOwner {

        if (_newToken == address(0x0)) throw;

        tokenCtr = Token(_newToken);
        TokenContractChanged(_newToken);
    }

    // returns expected payout for tokenholder during lock phase
    function expectedPayout(address _tokenHolder)
        external
        constant returns (uint) {

        if (!tokenCtr.lock())
            return 0;

        return (tokenCtr.balanceOf(_tokenHolder) * initEpochBalance) / tokenCtr.totalSupply();
    }

    function safeToMultiply(uint _a, uint _b)
        private
        constant returns (bool) {

        return (_b == 0 || ((_a * _b) / _b) == _a);
    }
}
