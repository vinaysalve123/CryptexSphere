// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title CryptexSphere
 * @notice Minimal puzzle vault ("crytex") where creators fund ETH rewards and solvers submit answers (preimage) to claim them.
 * @dev Gas-conscious; stores answer hashes, optional hint data, expiry. Core functions: createPuzzle, solvePuzzle, withdrawExpired.
 */
contract CryptexSphere {
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    struct Puzzle {
        bytes32 answerHash;
        address creator;
        uint256 reward;
        bool solved;
        address solver;
        uint256 expiresAt;
        bytes hint;
    }

    Puzzle[] public puzzles;

    event PuzzleCreated(uint256 indexed id, address indexed creator, uint256 reward, uint256 expiresAt);
    event PuzzleSolved(uint256 indexed id, address indexed solver, uint256 reward);
    event PuzzleWithdrawn(uint256 indexed id, address indexed creator, uint256 amount);

    /// @notice Create a new puzzle by providing the keccak256(answer) and funding a reward.
    /// @param answerHash keccak256 hash of the answer (preimage).
    /// @param durationSeconds lifetime of the puzzle in seconds.
    /// @param hint optional hint bytes (off-chain frontend can render).
    function createPuzzle(bytes32 answerHash, uint256 durationSeconds, bytes calldata hint) external payable returns (uint256 id) {
        require(msg.value > 0, "Reward required");
        require(durationSeconds > 0, "Duration required");

        id = puzzles.length;
        puzzles.push(Puzzle({
            answerHash: answerHash,
            creator: msg.sender,
            reward: msg.value,
            solved: false,
            solver: address(0),
            expiresAt: block.timestamp + durationSeconds,
            hint: hint
        }));

        emit PuzzleCreated(id, msg.sender, msg.value, block.timestamp + durationSeconds);
    }

    /// @notice Attempt to solve a puzzle by providing the plaintext answer.
    /// @dev If correct, transfers the reward to the solver and marks puzzle solved.
    function solvePuzzle(uint256 id, string calldata answer) external {
        require(id < puzzles.length, "Invalid id");
        Puzzle storage p = puzzles[id];
        require(!p.solved, "Already solved");
        require(block.timestamp <= p.expiresAt, "Expired");

        if (keccak256(bytes(answer)) == p.answerHash) {
            p.solved = true;
            p.solver = msg.sender;
            uint256 reward = p.reward;
            p.reward = 0;

            (bool sent, ) = payable(msg.sender).call{value: reward}("");
            require(sent, "Transfer failed");

            emit PuzzleSolved(id, msg.sender, reward);
        } else {
            revert("Incorrect answer");
        }
    }

    /// @notice Creator withdraws reward if puzzle expired unsolved.
    function withdrawExpired(uint256 id) external {
        require(id < puzzles.length, "Invalid id");
        Puzzle storage p = puzzles[id];
        require(!p.solved, "Already solved");
        require(block.timestamp > p.expiresAt, "Not expired");
        require(msg.sender == p.creator, "Only creator");

        uint256 amount = p.reward;
        p.reward = 0;

        (bool sent, ) = payable(p.creator).call{value: amount}("");
        require(sent, "Withdraw failed");

        emit PuzzleWithdrawn(id, p.creator, amount);
    }

    /// @notice Helper: fetch basic puzzle metadata.
    function getPuzzle(uint256 id) external view returns (
        bytes32 answerHash,
        address creator,
        uint256 reward,
        bool solved,
        address solver,
        uint256 expiresAt,
        bytes memory hint
    ) {
        require(id < puzzles.length, "Invalid id");
        Puzzle storage p = puzzles[id];
        return (p.answerHash, p.creator, p.reward, p.solved, p.solver, p.expiresAt, p.hint);
    }
}
