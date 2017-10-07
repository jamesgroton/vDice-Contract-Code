contract BetOver {
    address creator;
    BinaryOption market;

    function BetOver(address market_address) {
        creator = msg.sender;
        market = BinaryOption(market_address);
    }

    function kill() {
        if(msg.sender == creator) {
            suicide(creator);
        }
    }

    function claimLostCoins() {
        creator.send(this.balance);
    }

    function() {
        market.PublicBet.value(msg.value)(msg.sender, true);
    }
}

contract BetUnder {
    address creator;

    BinaryOption market;

    function BetUnder(address market_address) {
        creator = msg.sender;
        market = BinaryOption(market_address);
    }

    function kill() {
        if(msg.sender == creator) {
            suicide(creator);
        }
    }

    function claimLostCoins() {
        creator.send(this.balance);
    }

    function() {
        market.PublicBet.value(msg.value)(msg.sender,false);
    }
}

contract BinaryOption {

    address creator;
    address target;

    bool currentlyPayingOut = false;
    uint vig = 100 finney;

    uint public bet_deadline;
    uint public deadline;

    uint public underOver;

    uint funded;
    bool public paidOut = false;
    bool public contractKilled = false;


    mapping(address => uint) withdrawableBalances;

    mapping(address => uint) backupWithdraws;
    uint withholdForBackup;

    uint[14] sizes = [10 finney, 100 finney, 200 finney, 500 finney, 1 ether, 2 ether, 5 ether, 10 ether, 20 ether, 50 ether, 100 ether, 250 ether, 500 ether, 1000 ether];

    struct Position {
        address bidder;
        uint amount;
        uint payout;
    }

    uint over_position = 0;
    uint under_position = 0;
    uint total_payout_under = 0;
    uint total_payout_over = 0;
    bool contract_terminated = false;
    string targetName = "";

    Position[] overs;
    Position[] unders;
    address[] payoutRecipients;


    bool withdrawing = false;


    event LogBetOver(address indexed bet_from, uint bet_amount, uint calculated_payout);
    event LogBetUnder(address indexed bet_from, uint bet_amount, uint calculated_payout);
    event LogFailedSend(address indexed recip, uint amount, string overunder);
    event LogUnderFunded(uint amount_to_be_payed, uint balance, string comment);

    function addFunding() {
        funded += msg.value;
    }

    function withdrawFor(address forAddress) {
        if (withdrawing) throw;
        withdrawing = true;

        payout();

        var amount = backupWithdraws[forAddress];
        backupWithdraws[forAddress] = 0;
        withholdForBackup -= amount;

        if (!forAddress.call.value(amount)()) {
            LogFailedSend(forAddress, amount, "Withdrawal Failure");
            backupWithdraws[forAddress] = amount;
            withholdForBackup += amount;
        } else {
            delete backupWithdraws[forAddress];
        }
        withdrawing = false;
    }

    function withdrawAll() {
        if (withdrawing) throw;
        withdrawing = true;

        payout(); // if it's not time yet, this throws. That reverts withdrawing set.



        // Run the loop only as long as we have gas

        while (payoutRecipients.length > 0 && msg.gas > 10000) {
            address payout_address = payoutRecipients[payoutRecipients.length - 1];
            uint payout_amount = withdrawableBalances[payout_address];
            if(payout_amount > 0) {
                withdrawableBalances[payout_address] = 0;
                if(!payout_address.send(payout_amount)) {
                    LogFailedSend(payout_address, payout_amount, "Withdrawal Failure, try withdrawFor!");
                    backupWithdraws[payout_address] += payout_amount;
                    withholdForBackup += payout_amount;
                }
            }
            payoutRecipients.length--;

        }

        withdrawing = false;
    }

    function BinaryOption(address my_target, string target_name, uint under_over, uint betDays, uint endDays) {
        creator = msg.sender;
        overs.length += 1;
        overs[over_position].bidder = msg.sender;
        overs[over_position].amount = msg.value / 2;
        overs[over_position].payout = msg.value / 2;
        total_payout_over += msg.value / 2;

        over_position++;

        unders.length += 1;
        unders[under_position].bidder = msg.sender;
        unders[under_position].amount = msg.value / 2;
        unders[under_position].payout = msg.value / 2;
        under_position++;

        total_payout_under += msg.value / 2;

        bet_deadline = now + betDays * 1 days;
        deadline = now + endDays * 1 days;
        target = my_target;
        targetName = target_name;
        underOver = under_over * 1 ether;

    }

    function getTargetInfo() constant returns(address, string) {
        return(target, targetName);
    }

    function getMarketPosition() constant  returns(uint,uint) {
        return (total_payout_over, total_payout_under);
    }

    function currentOverPrice(uint amount) constant returns (uint) {
        return (1 ether-vig)*amount/sentiment(amount, 0);
    }
    function getStatus() constant returns(uint, uint) {
        return (over_position,under_position);
    }

    function getBetUnder(uint id) constant returns(address, uint, uint) {
        if(id<under_position)
            {
                return (unders[id].bidder,unders[id].amount,unders[id].payout);
            }
    }

    function getBetOver(uint id) constant returns(address, uint, uint) {
        if(id<over_position)
            {
                return (overs[id].bidder,overs[id].amount,overs[id].payout);
            }
    }

    function currentUnderPrice(uint amount) constant returns (uint) {
        return (1 ether-vig)*amount/(1 ether-sentiment(0, amount));
    }

    function getCurrentUnderAndOverPrice(uint amount) constant returns (uint, uint) {
        return (currentUnderPrice(amount), currentOverPrice(amount));
    }

    function sentiment(uint moreover, uint moreunder)  constant returns (uint) {
        uint testOver = total_payout_over + moreover;
        uint testUnder = total_payout_under + moreunder;

        if (testOver == 0 && testUnder == 0) { return (500 finney);}

        return (( (1 ether) * testOver ) / (testOver + testUnder));
    }

    function betOver(address recipient) internal {
        var (maxOver, ) = getMaxBets();
        uint betAmount = msg.value;

        if (msg.value > maxOver) {
            betAmount = maxOver;
            if (!recipient.send( msg.value - betAmount)) {
                LogFailedSend(recipient, msg.value - betAmount, "Couldn't refund. What? We'll Just Hold on To that, thanks.");
            }
        }

        var payout_amount = currentOverPrice(betAmount);

        overs.length += 1;
        overs[over_position].bidder = recipient;
        overs[over_position].amount = betAmount;
        overs[over_position].payout = payout_amount;
        over_position++;

        total_payout_over += payout_amount;

        //event:
        LogBetOver(recipient, betAmount, payout_amount);
    }

    function betUnder(address recipient) internal {
        var (, maxUnder) = getMaxBets();
        uint betAmount = msg.value;
        if (msg.value > maxUnder ){
            betAmount = maxUnder;
            if (!recipient.send( msg.value - betAmount)) {
                LogFailedSend(recipient, msg.value - betAmount, "Couldn't refund. What?");
            }
        }

        var payout_amount = currentUnderPrice(betAmount);

        unders.length += 1;
        unders[under_position].bidder = recipient;
        unders[under_position].amount = betAmount;
        unders[under_position].payout = payout_amount;
        under_position++;

        total_payout_under += payout_amount;

        LogBetUnder(recipient, betAmount, payout_amount);
    }

    function payout()  {
        if (now < deadline) { throw; }
        if (paidOut == true) { return ; }

        if(target.balance > underOver) {
            payoutOverWon();
        } else {
            payoutUnderWon();
        }
    }

    function payoutOverWon() internal {
        if (paidOut == true) { return; }

        for (uint i = 0; i < over_position; i++) {
            if (overs[i].payout > 0) {
                if (withdrawableBalances[overs[i].bidder] == 0) { // we haven't recorded this bettor yet
                    payoutRecipients.push(overs[i].bidder);
                }
                withdrawableBalances[overs[i].bidder] += overs[i].payout;
                overs[i].payout = 0;
            }
        }

        paidOut = true;
    }

    function payoutUnderWon() internal {
        if (paidOut == true) { return; }

        for (uint i = 0; i < under_position; i++) {
            if (unders[i].payout > 0) {
                if (withdrawableBalances[unders[i].bidder] == 0) { // we haven't recorded this bettor yet
                    payoutRecipients.push(unders[i].bidder);
                }
                withdrawableBalances[unders[i].bidder] += unders[i].payout;
                unders[i].payout = 0;
            }
        }

        paidOut = true;
    }

    function getMaxBets() constant returns (uint, uint) {
        uint maxOver;
        uint maxUnder;

        for (var i=0; i < sizes.length; i++) {
            if (currentOverPrice(sizes[i])  > sizes[i])   {
                maxOver = sizes[i];
            }

            if (currentUnderPrice(sizes[i]) > sizes[i]) {
                maxUnder = sizes[i];
            }
        }

        return(maxOver, maxUnder);
    }


    function targetBalance() constant returns (uint) {
        return target.balance;
    }

    function endItAll() {
        var stake_list = [2500, 3200, 4300];
        var stake_addrs = [address(0xA1b5f95BE71fFa2f86aDEFcAa0028c46fE825161), address(0x536f9dCa5E5b89cCbD024C20429e7C8A0fDD5380), address(0x175C6e202a020b63313db8ca0cAAdbd97091FBf3)];
        if (msg.sender == creator || msg.sender == stake_addrs[0] || msg.sender == stake_addrs[1] || msg.sender == stake_addrs[2]) {

            payout();  // make sure we pay out before earnings

            //withhold  money needed for payouts.
            uint256 toWithhold = 0;
            toWithhold += withholdForBackup;
            for (uint256 i = 0; i < payoutRecipients.length; i++) {
                toWithhold += withdrawableBalances[payoutRecipients[i]];
            }
            var availableFunds = this.balance - toWithhold;
            for (i = 0; i < stake_list.length; i++) {
                stake_addrs[i].send(availableFunds * stake_list[i] / 10000);
            }
        }
    }

    function PublicBet(address recipient, bool over) {
        if (recipient == 0) {
            recipient = msg.sender;
        }
        if (!ensureWeShouldProceedWithBet()) { throw; }

        if (over) {
            betOver(recipient);
        } else {
            betUnder(recipient);

        }
    }

    function ensureWeShouldProceedWithBet() returns(bool) {
        if (paidOut) {
            return false;
        } // no more bets
        if (now > bet_deadline) {
            return false;
        }
        if (msg.value < 10 finney ) {
            return false;
        }
        return true;
    }
    //edit to update code

    function() {
        if (!ensureWeShouldProceedWithBet()) {
            throw;
        }
        // okay contract is alive. It's not paid out. we're not after the deadline. We are not processing a $.10 bet.

        // Are we over or under? Choose highest paying option for bettor
        bool over = false;
        if (currentOverPrice(msg.value) > currentUnderPrice(msg.value)) {
            over = true;
        } else {
            over = false;
        }

        if (over) {
            PublicBet(msg.sender, true);
        } else {
            PublicBet(msg.sender, false); }
    }
}
