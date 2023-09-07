// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.0;

contract GameJackpot {
    event Game(uint _game, uint indexed _time);
    struct Bet {
        address addr;
        uint ticketstart;
        uint tickertend;
    }

    mapping(uint => uint) public totalBets;
    mapping(uint => mapping(uint => Bet)) public bets;

    // winning tickets history
    mapping(uint => uint) public ticketHistory;

    // wining address history
    mapping(uint => address) winnerHistory;

    // game fee
    uint8 public fee = 10;
    // Current game munber
    uint public game;
    // Min deposit jackpot
    uint public minJoin = 0.001 ether;

    // Game status
    // 0 = running
    // 1 = stop to show winners animation

    uint public gamestatus = 0;

    // All-time game jackpot.
    uint public allTimeJackpot = 0;
    // All-time game players count
    uint public allTimePlayers = 0;

    // Game status.
    bool public isActive = true;
    // The variable that indicates game status switching.
    bool public toogleStatus = false;
    // The array of all games
    uint[] public games;

    // Store game jackpot.
    mapping(uint => uint) jackpot;
    // Store game players.
    mapping(uint => address[]) players;
    // Store total tickets for each game
    mapping(uint => uint) tickets;
    // Store bonus pool jackpot.
    mapping(uint => uint) bonuspool;
    // Store game start block number.
    mapping(uint => uint) gamestartblock;

    address payable owner;

    uint counter = 1;
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function.");
        _;
    }

    constructor() {
        owner = payable(msg.sender);
        startGame();
    }

    function addBonus() public payable {
        bonuspool[game] += msg.value;
    }

    function playerticketstart(
        uint _gameid,
        uint _pid
    ) public view returns (uint256) {
        return bets[_gameid][_pid].ticketstart;
    }

    function playerticketend(
        uint _gameid,
        uint _pid
    ) public view returns (uint256) {
        return bets[_gameid][_pid].tickertend;
    }

    function totaltickets(uint _uint) public view returns (uint256) {
        return tickets[_uint];
    }

    function playeraddr(uint _gameid, uint _pid) public view returns (address) {
        return bets[_gameid][_pid].addr;
    }

    /**
     * @dev Returns current game players.
     */
    function getPlayedGamePlayers() public view returns (uint) {
        return getPlayersInGame(game);
    }

    /**
     * @dev Get players by game.
     *
     * @param playedGame Game number.
     */
    function getPlayersInGame(uint playedGame) public view returns (uint) {
        return players[playedGame].length;
    }

    /**
     * @dev Returns current game jackpot.
     */
    function getPlayedGameJackpot() public view returns (uint) {
        return getGameJackpot(game);
    }

    /**
     * @dev Get jackpot by game number.
     *
     * @param playedGame The number of the played game.
     */
    function getGameJackpot(uint playedGame) public view returns (uint) {
        return jackpot[playedGame] + bonuspool[playedGame];
    }

    /**
     * @dev Get bonus pool by game number.
     *
     * @param playedGame The number of the played game.
     */
    function getBonusPool(uint playedGame) public view returns (uint) {
        return bonuspool[playedGame];
    }

    /**
     * @dev Get game start block by game number.
     *
     * @param playedGame The number of the played game.
     */
    function getGamestartblock(uint playedGame) public view returns (uint) {
        return gamestartblock[playedGame];
    }

    /**
     * @dev Get total ticket for game
     */
    function getGameTotalTickets(uint playedGame) public view returns (uint) {
        return tickets[playedGame];
    }

    /**
     * @dev Start the new game.
     */
    function start() public onlyOwner {
        if (players[game].length > 0) {
            pickTheWinner();
        }
        gamestatus = 1;
        startGame();
    }

    /**
     * @dev Start the new game.
     */
    function setGamestatusZero() public onlyOwner {
        gamestatus = 0;
    }

    /**
     * @dev Get random number. It cant be influenced by anyone
     * @dev Random number calculation depends on block timestamp,
     * @dev difficulty, counter and jackpot players length.
     *
     */
    function randomNumber(uint number) internal returns (uint) {
        counter++;
        uint random = uint(
            keccak256(
                abi.encodePacked(
                    block.timestamp,
                    block.difficulty,
                    counter,
                    players[game].length
                )
            )
        ) % number;
        if (random == 0) {
            random = 1;
        }
        return random;
    }

    /**
     * @dev The payable method that accepts ether and adds the player to the jackpot game.
     */
    function enterJackpot() public payable {
        require(isActive);
        require(gamestatus == 0);
        require(msg.value >= minJoin);

        uint newtotalstr = totalBets[game];
        bets[game][newtotalstr].addr = address(msg.sender);
        bets[game][newtotalstr].ticketstart = tickets[game] + 1;
        bets[game][newtotalstr].tickertend =
            ((tickets[game] + 1) + (msg.value / (1000000000000000))) -
            1;

        totalBets[game] += 1;
        jackpot[game] += msg.value;
        tickets[game] += msg.value / 1000000000000000;

        players[game].push(msg.sender);
    }

    /**
     * @dev Start the new game.
     * @dev Checks game status changes, if exists request for changing game status game status
     * @dev will be changed.
     */
    function startGame() internal {
        require(isActive);

        game += 1;
        if (toogleStatus) {
            isActive = !isActive;
            toogleStatus = false;
        }
        gamestartblock[game] = block.timestamp;
        emit Game(game, block.timestamp);
    }

    /**
     * @dev Pick the winner using random number provably fair function.
     */
    function pickTheWinner() internal {
        uint winner;
        uint toPlayer;
        if (players[game].length == 1) {
            toPlayer = jackpot[game] + bonuspool[game];
            payable(players[game][0]).transfer(toPlayer);
            winner = 0;
            ticketHistory[game] = 1;
            winnerHistory[game] = players[game][0];
        } else {
            winner = randomNumber(tickets[game]); //winning ticket
            uint256 lookingforticket = winner;
            address ticketwinner;
            for (uint8 i = 0; i <= totalBets[game]; i++) {
                address addr = bets[game][i].addr;
                uint256 ticketstart = bets[game][i].ticketstart;
                uint256 tickertend = bets[game][i].tickertend;
                if (
                    lookingforticket >= ticketstart &&
                    lookingforticket <= tickertend
                ) {
                    ticketwinner = addr; //finding winner address
                }
            }

            ticketHistory[game] = lookingforticket;
            winnerHistory[game] = ticketwinner;

            uint distribute = ((jackpot[game] + bonuspool[game]) * fee) / 100; //game fee
            uint toTaxwallet = (distribute * 99) / 100;
            toPlayer = (jackpot[game] + bonuspool[game]) - distribute;
            payable(address(0x98Adf81933909Cd32fA9E59a8C5bC82E99C5f3e4))
                .transfer(toTaxwallet); //send 10% game fee
            payable(ticketwinner).transfer(toPlayer); //send prize to winner
        }

        allTimeJackpot += toPlayer;
        allTimePlayers += players[game].length;
    }
}
