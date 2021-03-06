pragma solidity ^0.4.2;

// import "http://github.com/oraclize/ethereum-api/oraclizeAPI_0.4.sol";

import "./usingOraclize.sol";

contract DSSafeAddSub {
    function safeToAdd(uint a, uint b) internal returns (bool) {
        return (a + b >= a);
    }
    function safeAdd(uint a, uint b) internal returns (uint) {
        if (!safeToAdd(a, b)) throw;
        return a + b;
    }

    function safeToSubtract(uint a, uint b) internal returns (bool) {
        return (b <= a);
    }

    function safeSub(uint a, uint b) internal returns (uint) {
        if (!safeToSubtract(a, b)) throw;
        return a - b;
    }
}

contract E93 is DSSafeAddSub, usingOraclize {

    modifier onlyOwner {

        // ETH93 admin accounts

        require(msg.sender == 0x3a31AC87092909AF0e01B4d8fC6E03157E91F4bb || msg.sender == 0x44fc32c2a5d18700284cc9e0e2da3ad83e9a6c5d);
        _;
    }

    modifier onlyOraclize {
        require(msg.sender == oraclize_cbAddress());
        _;
    }

    modifier onlyOwnerOrOraclize {
        require(msg.sender == oraclize_cbAddress() || msg.sender == owner);
        _;
    }

    address owner;
    address public charity = 0xD3F81260a44A1df7A7269CF66Abd9c7e4f8CdcD1; // Heifer International - see https://www.heifer.org/support/faq/online-donations to verify this is their Ethereum donation address. 5% of ticket sale revenue goes to this address.
    address public tokenContract = 0xfc5429ef09ed041622a23fee92e65efab389c1ce; // 1% of ticket sales go to E93 token holders, who can trade their E93 tokens in at any time.
    uint public roundNumber;

    struct Lottery {
        uint256 ticketsSold;
        uint256 winningTicket;
        address winner;
        bool finished;
        mapping (uint256 => address) tickets;
		mapping (address => uint256) ticketsPerUser;
    }

    mapping (uint => Lottery) public lotteries;

    uint public totalTicketsSold;

    function() payable {

        if (msg.value < 0.01 ether) revert();

        uint256 remainder = msg.value % (0.01 ether);

        uint256 numberOfTicketsForUser = safeSub(msg.value, remainder)/10**16; // msg.value will be the amount of Ether the user sends times 10^18, so divide this by 10^16 to get the number of tickets for that user (each ticket costs 0.01 Ether)

        totalTicketsSold = safeAdd(totalTicketsSold, numberOfTicketsForUser);

        lotteries[roundNumber].ticketsPerUser[msg.sender] = safeAdd(lotteries[roundNumber].ticketsPerUser[msg.sender], numberOfTicketsForUser);

        // Each ticket for a lottery round is mapped to an address, eg. lotteries[0][5] would be the 6th ticket for the 1st lottery and might equal an address like 0x344ad635fd4e3684a326664e0698c8fefbe6dd91. With the below code, if the current round number was 0 and 6 tickets had been sold, and say the user has sent 0.03 Ether (buying 3 tickets), then their address would be mapped to lotteries[0][6], lotteries[0][7] and lotteries[0][8]

        uint256 ticketToGiveUser = lotteries[roundNumber].ticketsSold;

        for (uint i = 0; i < numberOfTicketsForUser; i++) {
            lotteries[roundNumber].tickets[ticketToGiveUser] = msg.sender;
            ticketToGiveUser++;
        }

        lotteries[roundNumber].ticketsSold = safeAdd(lotteries[roundNumber].ticketsSold, numberOfTicketsForUser);

    }

    function ticketsOwnedByUser (address user) public constant returns (uint256) {
        return lotteries[roundNumber].ticketsPerUser[user];
    }

    function lookupPriorLottery (uint256 _roundNumber) public constant returns (uint256, uint256, address) {
        var ticketsSold = lotteries[_roundNumber].ticketsSold;
        var winningTicket = lotteries[_roundNumber].winningTicket;
        var winner = lotteries[_roundNumber].winner;
        return (ticketsSold, winningTicket, winner);
    }

    function __callback(bytes32 myid, string result) onlyOraclize {

        // This gets called once a day and signals the end of the round, unless the lottery has been paused (ie. stopped == true). This will be called first by the runInOneDay() function (which sets waiting == true and waits a day), followed immediately by the update() function which runs the Oraclize query to get a random number from random.org.

        if (stopped == true) {
            revert();
        }

        if (waiting == true) {

            update();

        } else {

        // waiting == false, so the update() function to generate a random number has been called. Time to determine a winner and transfer Ether.

        lotteries[roundNumber].finished = true;

        if (lotteries[roundNumber].ticketsSold > 0) {

        lotteries[roundNumber].winningTicket = parseInt(result); // 'result' is the random number generated by random.org

        lotteries[roundNumber].winner = lotteries[roundNumber].tickets[lotteries[roundNumber].winningTicket];

        lotteries[roundNumber].winner.transfer(lotteries[roundNumber].ticketsSold * 0.0093 ether); // 0.0093 Winner gets 93% of ticket sale revenue (ticket price of 0.01 ether * 0.93 * number of tickets sold)
        charity.transfer(lotteries[roundNumber].ticketsSold * 0.0005 ether); // Heifer International gets 5%
        tokenContract.transfer(lotteries[roundNumber].ticketsSold * 0.0001 ether); // E93 token holders get 1% - see eth93.com/crowdsale
        owner.transfer(lotteries[roundNumber].ticketsSold * 0.0001 ether); // eth93.com gets 1%

        }

        roundNumber++;

        runInOneDay();

        }

    }

    // gas for Oraclize. 400000 seems to be just enough, make it 500000 to be safe (can be changed later if necessary).
    uint256 gas = 500000;

    bool public waiting;

    bool public stopped;

    function runInOneDay() payable onlyOwner {

        // This waits for one day (86400 seconds) and then executes the __callback function, which will then execute the update() function (since the waiting variable will be set to true). Then a random number is generated, a winner is determined and the next round starts.

        waiting = true;
        oraclize_query(86400, "", "", gas);
    }

    function updateGas(uint256 _gas) onlyOwner {
        gas = _gas;
    }

    function stopGo() onlyOwner {

        // Just in case the lottery needs to be paused for some reason. The contract can still sell tickets in this case, but a winner won't be declared until stopGo() and update() are called again.

        if (stopped == false) {
            stopped = true;
        } else {
            stopped = false;
        }
    }

    function update() payable onlyOwner {

        // This queries random.org to generate a random number between 0 and the number of tickets sold for the round - 1, which is used to determine the winner. Our API key for random.org is encrypted and can only be read by the Oraclize engine.

        waiting = false;

        string memory part1 = "[URL] ['json(https://api.random.org/json-rpc/1/invoke).result.random.data.0', '\\n{\"jsonrpc\":\"2.0\",\"method\":\"generateIntegers\",\"params\":{\"apiKey\":${[decrypt] BNP9YOjVlFoCNaYBEVKgGqvSUXLrCFWNCXkoRPTnumiEM1+dNJkZFtnmpIP3CFHbUvy4uXaC8GF7xBwJtHu0LJAStZD/2pk5i7eh8jqyHWRLnDjVWZpxjVaIX+8rijblUp7CPBNRVoW0JS4TqGb0KL1XG+SZhcg=},\"n\":1,\"min\":0,\"max\":";

        string memory maxRandomNumber = uint2str(lotteries[roundNumber].ticketsSold - 1);

        string memory part2 = ",\"replacement\":true,\"base\":10${[identity] \"}\"},\"id\":1${[identity] \"}\"}']";

        string memory query = strConcat(part1, maxRandomNumber, part2);

        bytes32 rngId = oraclize_query("nested", query, gas);

    }

    function giveAllToCharity() onlyOwner {

        // Only call this if oraclize and random.org have some permanent problem and the round can't be completed, since no random number can be generated from oraclize or random.org. Then all the funds for the last lottery can go to Heifer International.

        charity.transfer(lotteries[roundNumber].ticketsSold * 0.01 ether);
        roundNumber++;
    }

    function depositFunds() payable {
        // Used to top up the contract balance without doing anything else - this is necessary to pay for Oraclize calls and transfer costs.
    }

}

}
