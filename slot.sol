pragma solidity ^0.4.11;

import "github.com/oraclize/ethereum-api/oraclizeAPI.sol";
import "github.com/dapphub/ds-math/src/math.sol";

contract LedgerProofVerifyI {
    function external_oraclize_randomDS_setCommitment(bytes32 queryId, bytes32 commitment) public;
    function external_oraclize_randomDS_proofVerify(bytes proof, bytes32 queryId, bytes result, string context_name)  public returns (bool);
}

contract Owned {
    address public owner;

    modifier onlyOwner {
        assert(msg.sender == owner);
        _;
    }
    
    function Owned() {
        owner = msg.sender;
    }

}

contract oraclizeSettings is Owned {
    uint constant ORACLIZE_PER_SPIN_GAS_LIMIT = 6100;
    uint constant ORACLIZE_BASE_GAS_LIMIT = 220000;
    uint safeGas = 9000;
    
    event LOG_newGasLimit(uint _gasLimit);

    function setSafeGas(uint _gas) 
            onlyOwner 
    {
        assert(ORACLIZE_BASE_GAS_LIMIT + _gas >= ORACLIZE_BASE_GAS_LIMIT);
        assert(_gas <= 25000);
        assert(_gas >= 9000); 

        safeGas = _gas;
        LOG_newGasLimit(_gas);
    }       
}

contract HouseManaged is Owned {
    
    address public houseAddress;
    address newOwner;
    bool public isStopped;

    event LOG_ContractStopped();
    event LOG_ContractResumed();
    event LOG_OwnerAddressChanged(address oldAddr, address newOwnerAddress);
    event LOG_HouseAddressChanged(address oldAddr, address newHouseAddress);
    
    modifier onlyIfNotStopped {
        assert(!isStopped);
        _;
    }

    modifier onlyIfStopped {
        assert(isStopped);
        _;
    }
    
    function HouseManaged() {
        houseAddress = msg.sender;
    }

    function stop_or_resume_Contract(bool _isStopped)
        onlyOwner {

        isStopped = _isStopped;
    }

    function changeHouse(address _newHouse)
        onlyOwner {

        assert(_newHouse != address(0x0)); 
        
        houseAddress = _newHouse;
        LOG_HouseAddressChanged(houseAddress, _newHouse);
    }
        
    function changeOwner(address _newOwner) onlyOwner {
        newOwner = _newOwner; 
    }     

    function acceptOwnership() {
        if (msg.sender == newOwner) {
            owner = newOwner;       
            LOG_OwnerAddressChanged(owner, newOwner);
            delete newOwner;
        }
    }
}

contract usingInvestorsModule is HouseManaged, oraclizeSettings {
    
    uint constant MAX_INVESTORS = 5; //maximum number of investors
    uint constant divestFee = 50; //divest fee percentage (10000 = 100%)

     struct Investor {
        address investorAddress;
        uint amountInvested;
        bool votedForEmergencyWithdrawal;
    }
    
    //Starting at 1
    mapping(address => uint) public investorIDs;
    mapping(uint => Investor) public investors;
    uint public numInvestors = 0;

    uint public invested = 0;
    
    uint public investorsProfit = 0;
    uint public investorsLosses = 0;
    bool profitDistributed;
    
    event LOG_InvestorEntrance(address indexed investor, uint amount);
    event LOG_InvestorCapitalUpdate(address indexed investor, int amount);
    event LOG_InvestorExit(address indexed investor, uint amount);
    event LOG_EmergencyAutoStop();
    
    event LOG_ZeroSend();
    event LOG_ValueIsTooBig();
    event LOG_FailedSend(address addr, uint value);
    event LOG_SuccessfulSend(address addr, uint value);
    


    modifier onlyMoreThanMinInvestment {
        assert(msg.value > getMinInvestment());
        _;
    }

    modifier onlyMoreThanZero {
        assert(msg.value != 0);
        _;
    }

    
    modifier onlyInvestors {
        assert(investorIDs[msg.sender] != 0);
        _;
    }

    modifier onlyNotInvestors {
        assert(investorIDs[msg.sender] == 0);
        _;
    }
    
    modifier investorsInvariant {
        _;
        assert(numInvestors <= MAX_INVESTORS);
    }
     
    function getBankroll()
        constant
        returns(uint) {

        if ((invested < investorsProfit) ||
            (invested + investorsProfit < invested) ||
            (invested + investorsProfit < investorsLosses)) {
            return 0;
        }
        else {
            return invested + investorsProfit - investorsLosses;
        }
    }

    function getMinInvestment()
        constant
        returns(uint) {

        if (numInvestors == MAX_INVESTORS) {
            uint investorID = searchSmallestInvestor();
            return getBalance(investors[investorID].investorAddress);
        }
        else {
            return 0;
        }
    }

    function getLossesShare(address currentInvestor)
        constant
        returns (uint) {

        return (investors[investorIDs[currentInvestor]].amountInvested * investorsLosses) / invested;
    }

    function getProfitShare(address currentInvestor)
        constant
        returns (uint) {

        return (investors[investorIDs[currentInvestor]].amountInvested * investorsProfit) / invested;
    }

    function getBalance(address currentInvestor)
        constant
        returns (uint) {

        uint invested = investors[investorIDs[currentInvestor]].amountInvested;
        uint profit = getProfitShare(currentInvestor);
        uint losses = getLossesShare(currentInvestor);

        if ((invested + profit < profit) ||
            (invested + profit < invested) ||
            (invested + profit < losses))
            return 0;
        else
            return invested + profit - losses;
    }

    function searchSmallestInvestor()
        constant
        returns(uint) {

        uint investorID = 1;
        for (uint i = 1; i <= numInvestors; i++) {
            if (getBalance(investors[i].investorAddress) < getBalance(investors[investorID].investorAddress)) {
                investorID = i;
            }
        }

        return investorID;
    }

    
    function addInvestorAtID(uint id)
        private {

        investorIDs[msg.sender] = id;
        investors[id].investorAddress = msg.sender;
        investors[id].amountInvested = msg.value;
        invested += msg.value;

        LOG_InvestorEntrance(msg.sender, msg.value);
    }

    function profitDistribution()
        private {

        if (profitDistributed) return;
                
        uint copyInvested;

        for (uint i = 1; i <= numInvestors; i++) {
            address currentInvestor = investors[i].investorAddress;
            uint profitOfInvestor = getProfitShare(currentInvestor);
            uint lossesOfInvestor = getLossesShare(currentInvestor);
            
            //Check for overflow and underflow
            if ((investors[i].amountInvested + profitOfInvestor >= investors[i].amountInvested) &&
                (investors[i].amountInvested + profitOfInvestor >= lossesOfInvestor))  {
                investors[i].amountInvested += profitOfInvestor - lossesOfInvestor;
                LOG_InvestorCapitalUpdate(currentInvestor, (int) (profitOfInvestor - lossesOfInvestor));
            }
            else {
                isStopped = true;
                LOG_EmergencyAutoStop();
            }

            copyInvested += investors[i].amountInvested; 

        }

        delete investorsProfit;
        delete investorsLosses;
        invested = copyInvested;

        profitDistributed = true;
    }
    
    function increaseInvestment()
        payable
        onlyIfNotStopped
        onlyMoreThanZero
        onlyInvestors  {

        profitDistribution();
        investors[investorIDs[msg.sender]].amountInvested += msg.value;
        invested += msg.value;
    }

    function newInvestor()
        payable
        onlyIfNotStopped
        onlyMoreThanZero
        onlyNotInvestors
        onlyMoreThanMinInvestment
        investorsInvariant {

        profitDistribution();

        if (numInvestors == MAX_INVESTORS) {
            uint smallestInvestorID = searchSmallestInvestor();
            divest(investors[smallestInvestorID].investorAddress);
        }

        numInvestors++;
        addInvestorAtID(numInvestors);
    }

    function divest()
        onlyInvestors {

        divest(msg.sender);
    }


    function divest(address currentInvestor)
        internal
        investorsInvariant {

        profitDistribution();
        uint currentID = investorIDs[currentInvestor];
        uint amountToReturn = getBalance(currentInvestor);

        if (invested >= investors[currentID].amountInvested) {
            invested -= investors[currentID].amountInvested;
            uint divestFeeAmount =  (amountToReturn*divestFee)/10000;
            amountToReturn -= divestFeeAmount;

            delete investors[currentID];
            delete investorIDs[currentInvestor];

            //Reorder investors
            if (currentID != numInvestors) {
                // Get last investor
                Investor lastInvestor = investors[numInvestors];
                //Set last investor ID to investorID of divesting account
                investorIDs[lastInvestor.investorAddress] = currentID;
                //Copy investor at the new position in the mapping
                investors[currentID] = lastInvestor;
                //Delete old position in the mappping
                delete investors[numInvestors];
            }

            numInvestors--;
            safeSend(currentInvestor, amountToReturn);
            safeSend(houseAddress, divestFeeAmount);
            LOG_InvestorExit(currentInvestor, amountToReturn);
        } else {
            isStopped = true;
            LOG_EmergencyAutoStop();
        }
    }
    
    function forceDivestOfAllInvestors()
        onlyOwner {
            
        uint copyNumInvestors = numInvestors;
        for (uint i = 1; i <= copyNumInvestors; i++) {
            divest(investors[1].investorAddress);
        }
    }
    
    function safeSend(address addr, uint value)
        internal {

        if (value == 0) {
            LOG_ZeroSend();
            return;
        }

        if (this.balance < value) {
            LOG_ValueIsTooBig();
            return;
	}

        if (!(addr.call.gas(safeGas).value(value)())) {
            LOG_FailedSend(addr, value);
            if (addr != houseAddress) {
                //Forward to house address all change
                if (!(houseAddress.call.gas(safeGas).value(value)())) LOG_FailedSend(houseAddress, value);
            }
        }

        LOG_SuccessfulSend(addr,value);
    }
}

contract EmergencyWithdrawalModule is usingInvestorsModule {
    uint constant EMERGENCY_WITHDRAWAL_RATIO = 80; //ratio percentage (100 = 100%)
    uint constant EMERGENCY_TIMEOUT = 3 days;
    
    struct WithdrawalProposal {
        address toAddress;
        uint atTime;
    }
    
    WithdrawalProposal public proposedWithdrawal;
    
    event LOG_EmergencyWithdrawalProposed();
    event LOG_EmergencyWithdrawalFailed(address indexed withdrawalAddress);
    event LOG_EmergencyWithdrawalSucceeded(address indexed withdrawalAddress, uint amountWithdrawn);
    event LOG_EmergencyWithdrawalVote(address indexed investor, bool vote);
    
    modifier onlyAfterProposed {
        assert(proposedWithdrawal.toAddress != 0);
        _;
    }
    
    modifier onlyIfEmergencyTimeOutHasPassed {
        assert(proposedWithdrawal.atTime + EMERGENCY_TIMEOUT <= now);
        _;
    }
    
    function voteEmergencyWithdrawal(bool vote)
        onlyInvestors
        onlyAfterProposed
        onlyIfStopped {

        investors[investorIDs[msg.sender]].votedForEmergencyWithdrawal = vote;
        LOG_EmergencyWithdrawalVote(msg.sender, vote);
    }

    function proposeEmergencyWithdrawal(address withdrawalAddress)
        onlyIfStopped
        onlyOwner {

        //Resets previous votes
        for (uint i = 1; i <= numInvestors; i++) {
            delete investors[i].votedForEmergencyWithdrawal;
        }

        proposedWithdrawal = WithdrawalProposal(withdrawalAddress, now);
        LOG_EmergencyWithdrawalProposed();
    }

    function executeEmergencyWithdrawal()
        onlyOwner
        onlyAfterProposed
        onlyIfStopped
        onlyIfEmergencyTimeOutHasPassed {

        uint numOfVotesInFavour;
        uint amountToWithdraw = this.balance;

        for (uint i = 1; i <= numInvestors; i++) {
            if (investors[i].votedForEmergencyWithdrawal == true) {
                numOfVotesInFavour++;
                delete investors[i].votedForEmergencyWithdrawal;
            }
        }

        if (numOfVotesInFavour >= EMERGENCY_WITHDRAWAL_RATIO * numInvestors / 100) {
            if (!proposedWithdrawal.toAddress.send(amountToWithdraw)) {
                LOG_EmergencyWithdrawalFailed(proposedWithdrawal.toAddress);
            }
            else {
                LOG_EmergencyWithdrawalSucceeded(proposedWithdrawal.toAddress, amountToWithdraw);
            }
        }
        else {
            revert();
        }
    }
    
        /*
    The owner can use this function to force the exit of an investor from the
    contract during an emergency withdrawal in the following situations:
        - Unresponsive investor
        - Investor demanding to be paid in other to vote, the facto-blackmailing
        other investors
    */
    function forceDivestOfOneInvestor(address currentInvestor)
        onlyOwner
        onlyIfStopped {

        divest(currentInvestor);
        //Resets emergency withdrawal proposal. Investors must vote again
        delete proposedWithdrawal;
    }
}

contract Slot is usingOraclize, EmergencyWithdrawalModule, DSMath {
    
    uint constant INVESTORS_EDGE = 200; 
    uint constant HOUSE_EDGE = 50;
    uint constant CAPITAL_RISK = 250;
    uint constant MAX_SPINS = 16;
    
    uint minBet = 1 wei;
 
    struct SpinsContainer {
        address playerAddress;
        uint nSpins;
        uint amountWagered;
    }
    
    mapping (bytes32 => SpinsContainer) spins;
    
    /* Both arrays are ordered:
     - probabilities are ordered from smallest to highest
     - multipliers are ordered from highest to lowest
     The probabilities are expressed as integer numbers over a scale of 10000: i.e
     100 is equivalent to 1%, 5000 to 50% and so on.
    */
    uint[] public probabilities;
    uint[] public multipliers;
    
    uint public totalAmountWagered; 
    
    event LOG_newSpinsContainer(bytes32 myid, address playerAddress, uint amountWagered, uint nSpins);
    event LOG_SpinExecuted(bytes32 myid, address playerAddress, uint spinIndex, uint numberDrawn, uint grossPayoutForSpin);
    event LOG_SpinsContainerInfo(bytes32 myid, address playerAddress, uint netPayout);

    LedgerProofVerifyI externalContract;
    
    function Slot(address _verifierAddr) {
        externalContract = LedgerProofVerifyI(_verifierAddr);
    }
    
    //SECTION I: MODIFIERS AND HELPER FUNCTIONS
    
    function oraclize_randomDS_setCommitment(bytes32 queryId, bytes32 commitment) internal {
        externalContract.external_oraclize_randomDS_setCommitment(queryId, commitment);
    }
    
    modifier oraclize_randomDS_proofVerify(bytes32 _queryId, string _result, bytes _proof) {
        // Step 1: the prefix has to match 'LP\x01' (Ledger Proof version 1)
        //if ((_proof[0] != "L")||(_proof[1] != "P")||(_proof[2] != 1)) throw;
        assert(externalContract.external_oraclize_randomDS_proofVerify(_proof, _queryId, bytes(_result), oraclize_getNetworkName()));
        _;
    }

    modifier onlyOraclize {
        assert(msg.sender == oraclize_cbAddress());
        _;
    }

    modifier onlyIfSpinsExist(bytes32 myid) {
        assert(spins[myid].playerAddress != address(0x0));
        _;
    }
    
    function isValidSize(uint _amountWagered) 
        internal 
        returns(bool) {
            
        uint netPotentialPayout = (_amountWagered * (10000 - INVESTORS_EDGE) * multipliers[0])/ 10000; 
        uint maxAllowedPayout = (CAPITAL_RISK * getBankroll())/10000;
        
        return ((netPotentialPayout <= maxAllowedPayout) && (_amountWagered >= minBet));
    }

    modifier onlyIfEnoughFunds(bytes32 myid) {
        if (isValidSize(spins[myid].amountWagered)) {
             _;
        }
        else {
            address playerAddress = spins[myid].playerAddress;
            uint amountWagered = spins[myid].amountWagered;   
            delete spins[myid];
            safeSend(playerAddress, amountWagered);
            return;
        }
    }
    

        modifier onlyValidNumberOfSpins (uint _nSpins) {
        assert(_nSpins <= MAX_SPINS);
              assert(_nSpins > 0);
        _;
    }
    
    /*
        For the game to be fair, the total gross payout over a large number of 
        individual slot spins should be the total amount wagered by the player. 
        
        The game owner, called house, and the investors will gain by applying 
        a small fee, called edge, to the amount won by the player in the case of
        a successful spin. 
        
        The total gross expected payout is equal to the sum of all payout. Each 
        i-th payout is calculated:
                    amountWagered * multipliers[i] * probabilities[i] 
        The fairness condition can be expressed as the equation:
                    sum of aW * m[i] * p[i] = aW
        After having simplified the equation:
                        sum of m[i] * p[i] = 1
        Since our probabilities are defined over 10000, the sum should be 10000.
        
        The contract owner can modify the multipliers and probabilities array, 
        but the  modifier enforces that the number choosen always result in a 
        fare game.
    */
    modifier onlyIfFair(uint[] _prob, uint[] _payouts) {
        if (_prob.length != _payouts.length) revert();
        uint sum = 0;
        for (uint i = 0; i <_prob.length; i++) {
            sum += _prob[i] * _payouts[i];     
        }
        assert(sum == 10000);
        _;
    }

    function()
        payable {
        buySpins(1);
    }

    function buySpins(uint _nSpins) 
        payable 
        onlyValidNumberOfSpins(_nSpins) 
                    onlyIfNotStopped {
            
        uint gas = _nSpins*ORACLIZE_PER_SPIN_GAS_LIMIT + ORACLIZE_BASE_GAS_LIMIT + safeGas;
        uint oraclizeFee = OraclizeI(OAR.getAddress()).getPrice("random", gas);
        
        // Disallow bets that even when maximally winning are a loss for player 
        // due to oraclizeFee
        assert(oraclizeFee/multipliers[0] + oraclizeFee < msg.value);
        uint amountWagered = msg.value - oraclizeFee;
        assert(isValidSize(amountWagered));
        
        bytes32 queryId = oraclize_newRandomDSQuery(0, 2*_nSpins, gas);
        spins[queryId] = 
            SpinsContainer(msg.sender,
                   _nSpins,
                   amountWagered
                  );
        LOG_newSpinsContainer(queryId, msg.sender, amountWagered, _nSpins);
        totalAmountWagered += amountWagered;
    }
    
    function executeSpins(bytes32 myid, bytes randomBytes) 
        private 
        returns(uint)
    {
        uint amountWonTotal = 0;
        uint amountWonSpin = 0;
        uint numberDrawn = 0;
        uint rangeUpperEnd = 0;
        uint nSpins = spins[myid].nSpins;
        
        for (uint i = 0; i < 2*nSpins; i += 2) {
            // A number between 0 and 2**16, normalized over 0 - 10000
            numberDrawn = ((uint(randomBytes[i])*256 + uint(randomBytes[i+1]))*10000)/2**16;
            rangeUpperEnd = 0;
            amountWonSpin = 0;
            for (uint j = 0; j < probabilities.length; j++) {
                rangeUpperEnd += probabilities[j];
                if (numberDrawn < rangeUpperEnd) {
                    amountWonSpin = (spins[myid].amountWagered * multipliers[j]) / nSpins;
                    amountWonTotal += amountWonSpin;
                    break;
                }
            }
            LOG_SpinExecuted(myid, spins[myid].playerAddress, i/2, numberDrawn, amountWonSpin);
        }
        return amountWonTotal;
    }
    
    function sendPayout(bytes32 myid, uint payout) private {

        uint investorsFee = payout*INVESTORS_EDGE/10000; 
        uint houseFee = payout*HOUSE_EDGE/10000;
      
        uint netPlayerPayout = sub(sub(payout,investorsFee), houseFee);
        uint netCostForInvestors = add(netPlayerPayout, houseFee);

        if (netCostForInvestors >= spins[myid].amountWagered) {
            investorsLosses += sub(netCostForInvestors, spins[myid].amountWagered);
        }
        else {
            investorsProfit += sub(spins[myid].amountWagered, netCostForInvestors);
        }
        
        LOG_SpinsContainerInfo(myid, spins[myid].playerAddress, netPlayerPayout);
        safeSend(spins[myid].playerAddress, netPlayerPayout);
        safeSend(houseAddress, houseFee);
    }
    
     function __callback(bytes32 myid, string result, bytes _proof) 
        onlyOraclize
        onlyIfSpinsExist(myid)
        onlyIfEnoughFunds(myid)
        oraclize_randomDS_proofVerify(myid, result, _proof)
    {
                
        uint payout = executeSpins(myid, bytes(result));
        
        sendPayout(myid, payout);
        
        delete profitDistributed;
        delete spins[myid];
    }
    
    // SETTERS - SETTINGS ACCESSIBLE BY OWNER
    
    // Check ordering as well, since ordering assumptions are made in _callback 
    // and elsewhere
    function setConfiguration(uint[] _probabilities, uint[] _multipliers) 
        onlyOwner 
        onlyIfFair(_probabilities, _multipliers) {
                
        oraclize_setProof(proofType_Ledger); //This is here to reduce gas cost as this function has to be called anyway for initialization
        
        delete probabilities;
        delete multipliers;
        
        uint lastProbability = 0;
        uint lastMultiplier = 2**256 - 1;
        
        for (uint i = 0; i < _probabilities.length; i++) {
            probabilities.push(_probabilities[i]);
            if (lastProbability >= _probabilities[i]) revert();
            lastProbability = _probabilities[i];
        }
        
        for (i = 0; i < _multipliers.length; i++) {
            multipliers.push(_multipliers[i]);
            if (lastMultiplier <= _multipliers[i]) revert();
            lastMultiplier = _multipliers[i];
        }
    }
    
    function setMinBet(uint _minBet) onlyOwner {
        minBet = _minBet;
    }
    
    // GETTERS - CONSTANT METHODS
    
    function getSpinsContainer(bytes32 myid)
        constant
        returns(address, uint) {
        return (spins[myid].playerAddress, spins[myid].amountWagered); 
    }

    // Returns minimal amount to wager to return a profit in case of max win
    function getMinAmountToWager(uint _nSpins)
        onlyValidNumberOfSpins(_nSpins)
        constant
                returns(uint) {
        uint gas = _nSpins*ORACLIZE_PER_SPIN_GAS_LIMIT + ORACLIZE_BASE_GAS_LIMIT + safeGas;
        uint oraclizeFee = OraclizeI(OAR.getAddress()).getPrice("random", gas);
        return minBet + oraclizeFee/multipliers[0] + oraclizeFee;
    }
   
    function getMaxAmountToWager(uint _nSpins)
        onlyValidNumberOfSpins(_nSpins)
        constant
        returns(uint) {

        uint oraclizeFee = OraclizeI(OAR.getAddress()).getPrice("random", _nSpins*ORACLIZE_PER_SPIN_GAS_LIMIT + ORACLIZE_BASE_GAS_LIMIT + safeGas);
        uint maxWage =  (CAPITAL_RISK * getBankroll())*10000/((10000 - INVESTORS_EDGE)*10000*multipliers[0]);
        return maxWage + oraclizeFee;
    }
    
}

