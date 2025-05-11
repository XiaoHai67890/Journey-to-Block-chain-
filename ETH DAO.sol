// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract OpenSourceDAO {
    // 防止溢出的数学运算库（Solidity 0.8+ 默认检查溢出，但保留以提高可读性）
    using SafeMath for uint256;

    // 可调整的参数
    uint256 public minStake;           // 加入DAO的最低质押金额
    uint256 public challengePeriod;    // 里程碑挑战期（秒）
    uint256 public votingPeriod;       // 投票期（秒）

    // 枚举类型
    enum ProposalType { Project, Governance }  // 提案类型：项目或治理
    enum Parameter { MinStake, ChallengePeriod, VotingPeriod }  // 可治理的参数

    // 数据结构
    struct Proposal {
        uint256 id;                // 提案ID
        ProposalType proposalType; // 提案类型
        address proposer;          // 提案发起者
        string description;        // 提案描述
        uint256[] milestoneFunds;  // 每个里程碑的资金量
        uint256 totalFunding;      // 总资金需求
        uint256 startTime;         // 投票开始时间
        uint256 endTime;           // 投票结束时间
        bool executed;             // 是否已执行
        uint256 votesFor;          // 支持票的投票力
        uint256 votesAgainst;      // 反对票的投票力
        mapping(address => bool) voted;  // 记录投票者
        Parameter param;           // 治理提案参数（仅治理提案适用）
        uint256 value;             // 治理提案新值（仅治理提案适用）
    }

    struct Milestone {
        uint256 proposalId;        // 所属提案ID
        uint256 milestoneId;       // 里程碑ID
        bool claimed;              // 是否已认领
        bool approved;             // 是否已通过
        uint256 claimTime;         // 认领时间
        bool disputed;             // 是否被争议
        uint256 votingEnd;         // 争议投票结束时间
        uint256 votesFor;          // 支持票的投票力
        uint256 votesAgainst;      // 反对票的投票力
        mapping(address => bool) voted;     // 记录投票者
        mapping(address => bool) voteChoice; // 记录投票选择（true为支持）
        address[] voters;          // 投票者列表
    }

    // 状态变量
    mapping(address => uint256) public stakes;       // 成员质押金额
    mapping(address => uint256) public reputation;   // 成员声誉分数（0-100）
    mapping(uint256 => Proposal) public proposals;   // 提案映射
    mapping(uint256 => mapping(uint256 => Milestone)) public milestones; // 里程碑映射
    uint256 public nextProposalId = 1;               // 下一个提案ID
    uint256 public treasuryBalance;                  // 金库余额

    // 事件
    event JoinedDAO(address indexed member, uint256 amount);
    event LeftDAO(address indexed member, uint256 amount);
    event ProposalSubmitted(uint256 indexed proposalId, ProposalType proposalType, address indexed proposer);
    event VotedOnProposal(uint256 indexed proposalId, address indexed voter, bool support);
    event MilestoneClaimed(uint256 indexed proposalId, uint256 indexed milestoneId);
    event MilestoneDisputed(uint256 indexed proposalId, uint256 indexed milestoneId);
    event VotedOnMilestone(uint256 indexed proposalId, uint256 indexed milestoneId, address indexed voter, bool approve);
    event MilestoneApproved(uint256 indexed proposalId, uint256 indexed milestoneId);
    event FundsReleased(uint256 indexed proposalId, uint256 indexed milestoneId, uint256 amount);
    event GovernanceProposalExecuted(uint256 indexed proposalId, Parameter parameter, uint256 value);

    // 修饰符
    modifier onlyMember {
        require(stakes[msg.sender] >= minStake, "Not a member");
        _;
    }

    // 构造函数
    constructor(uint256 _minStake, uint256 _challengePeriod, uint256 _votingPeriod) {
        minStake = _minStake;
        challengePeriod = _challengePeriod;
        votingPeriod = _votingPeriod;
    }

    function joinDAO() public payable {
        require(msg.value >= minStake, "Insufficient stake");
        stakes[msg.sender] = stakes[msg.sender].add(msg.value);
        emit JoinedDAO(msg.sende/ 加入DAO
    funcr, msg.value);
    }

    // 离开DAO
    function leaveDAO() public {
        uint256 stake = stakes[msg.sender];
        require(stake > 0, "Not a member");
        stakes[msg.sender] = 0;
        payable(msg.sender).transfer(stake);
        emit LeftDAO(msg.sender, stake);
    }

    // 提交项目提案
    function submitProposal(string memory description, uint256[] memory milestoneFunds) public onlyMember {
        require(milestoneFunds.length > 0, "No milestones");
        uint256 totalFunding = 0;
        for (uint256 i = 0; i < milestoneFunds.length; i++) {
            totalFunding = totalFunding.add(milestoneFunds[i]);
        }
        require(treasuryBalance >= totalFunding, "Insufficient treasury");

        uint256 proposalId = nextProposalId++;
        Proposal storage p = proposals[proposalId];
        p.id = proposalId;
        p.proposalType = ProposalType.Project;
        p.proposer = msg.sender;
        p.description = description;
        p.milestoneFunds = milestoneFunds;
        p.totalFunding = totalFunding;
        p.startTime = block.timestamp;
        p.endTime = block.timestamp + votingPeriod;
        p.executed = false;

        for (uint256 i = 0; i < milestoneFunds.length; i++) {
            milestones[proposalId][i] = Milestone(proposalId, i, false, false, 0, false, 0, 0, 0, new address[](0));
        }
        emit ProposalSubmitted(proposalId, ProposalType.Project, msg.sender);
    }

    // 提交治理提案
    function submitGovernanceProposal(Parameter param, uint256 value) public onlyMember {
        uint256 proposalId = nextProposalId++;
        Proposal storage p = proposals[proposalId];
        p.id = proposalId;
        p.proposalType = ProposalType.Governance;
        p.proposer = msg.sender;
        p.description = "Governance update";
        p.startTime = block.timestamp;
        p.endTime = block.timestamp + votingPeriod;
        p.executed = false;
        p.param = param;
        p.value = value;
        emit ProposalSubmitted(proposalId, ProposalType.Governance, msg.sender);
    }

    // 计算投票力
    function calculateVotingPower(address member) public view returns (uint256) {
        uint256 stake = stakes[member];
        uint256 rep = reputation[member];
        return stake.mul(100 + rep).div(100);
    }

    // 对提案投票
    function voteOnProposal(uint256 proposalId, bool support) public onlyMember {
        Proposal storage p = proposals[proposalId];
        require(block.timestamp >= p.startTime && block.timestamp < p.endTime, "Voting not active");
        require(!p.voted[msg.sender], "Already voted");
        uint256 votingPower = calculateVotingPower(msg.sender);
        if (support) {
            p.votesFor = p.votesFor.add(votingPower);
        } else {
            p.votesAgainst = p.votesAgainst.add(votingPower);
        }
        p.voted[msg.sender] = true;
        emit VotedOnProposal(proposalId, msg.sender, support);
    }

    // 执行提案
    function executeProposal(uint256 proposalId) public {
        Proposal storage p = proposals[proposalId];
        require(block.timestamp >= p.endTime, "Voting still active");
        require(!p.executed, "Already executed");
        p.executed = true;
        if (p.votesFor > p.votesAgainst) {
            if (p.proposalType == ProposalType.Project) {
                treasuryBalance = treasuryBalance.sub(p.totalFunding);
            } else if (p.proposalType == ProposalType.Governance) {
                setParameter(p.param, p.value);
                emit GovernanceProposalExecuted(proposalId, p.param, p.value);
            }
        }
    }

    // 设置治理参数
    function setParameter(Parameter param, uint256 value) internal {
        if (param == Parameter.MinStake) {
            minStake = value;
        } else if (param == Parameter.ChallengePeriod) {
            challengePeriod = value;
        } else if (param == Parameter.VotingPeriod) {
            votingPeriod = value;
        }
    }

    // 认领里程碑
    function claimMilestone(uint256 proposalId, uint256 milestoneId) public {
        Proposal storage p = proposals[proposalId];
        require(p.proposer == msg.sender, "Only proposer");
        require(p.executed && p.votesFor > p.votesAgainst, "Proposal not approved");
        if (milestoneId > 0) {
            require(milestones[proposalId][milestoneId - 1].approved, "Previous milestone not approved");
        }
        Milestone storage m = milestones[proposalId][milestoneId];
        require(!m.claimed, "Already claimed");
        m.claimed = true;
        m.claimTime = block.timestamp;
        emit MilestoneClaimed(proposalId, milestoneId);
    }

    // 争议里程碑
    function disputeMilestone(uint256 proposalId, uint256 milestoneId) public onlyMember {
        Milestone storage m = milestones[proposalId][milestoneId];
        require(m.claimed, "Not claimed");
        require(block.timestamp < m.claimTime + challengePeriod, "Challenge period over");
        m.disputed = true;
        m.votingEnd = block.timestamp + votingPeriod;
        emit MilestoneDisputed(proposalId, milestoneId);
    }

    // 对里程碑投票
    function voteOnMilestone(uint256 proposalId, uint256 milestoneId, bool approve) public onlyMember {
        Milestone storage m = milestones[proposalId][milestoneId];
        require(m.disputed && block.timestamp < m.votingEnd, "Voting not active");
        require(!m.voted[msg.sender], "Already voted");
        uint256 votingPower = calculateVotingPower(msg.sender);
        if (approve) {
            m.votesFor = m.votesFor.add(votingPower);
        } else {
            m.votesAgainst = m.votesAgainst.add(votingPower);
        }
        m.voted[msg.sender] = true;
        m.voteChoice[msg.sender] = approve;
        m.voters.push(msg.sender);
        emit VotedOnMilestone(proposalId, milestoneId, msg.sender, approve);
    }

    // 结算里程碑
    function finalizeMilestone(uint256 proposalId, uint256 milestoneId) public {
        Milestone storage m = milestones[proposalId][milestoneId];
        require(m.claimed && !m.approved, "Not claimable or already approved");
        Proposal storage p = proposals[proposalId];
        uint256 amount = p.milestoneFunds[milestoneId];

        if (!m.disputed) {
            require(block.timestamp >= m.claimTime + challengePeriod, "Challenge period not over");
            m.approved = true;
            require(address(this).balance >= amount, "Insufficient funds");
            payable(p.proposer).transfer(amount);
            if (reputation[p.proposer].add(5) > 100) {
                reputation[p.proposer] = 100;
            } else {
                reputation[p.proposer] = reputation[p.proposer].add(5);
            }
            emit MilestoneApproved(proposalId, milestoneId);
            emit FundsReleased(proposalId, milestoneId, amount);
        } else {
            require(block.timestamp >= m.votingEnd, "Voting still active");
            if (m.votesFor > m.votesAgainst) {
                m.approved = true;
                require(address(this).balance >= amount, "Insufficient funds");
                payable(p.proposer).transfer(amount);
                if (reputation[p.proposer].add(5) > 100) {
                    reputation[p.proposer] = 100;
                } else {
                    reputation[p.proposer] = reputation[p.proposer].add(5);
                }
                emit MilestoneApproved(proposalId, milestoneId);
                emit FundsReleased(proposalId, milestoneId, amount);
            } else {
                treasuryBalance = treasuryBalance.add(amount);
            }
            // 更新投票者的声誉
            for (uint256 i = 0; i < m.voters.length; i++) {
                address voter = m.voters[i];
                if ((m.approved && m.voteChoice[voter]) || (!m.approved && !m.voteChoice[voter])) {
                    if (reputation[voter] < 100) reputation[voter] = reputation[voter].add(1);
                } else {
                    if (reputation[voter] > 0) reputation[voter] = reputation[voter].sub(1);
                }
            }
        }
    }

    // 向金库捐款
    function donateToTreasury() public payable {
        treasuryBalance = treasuryBalance.add(msg.value);
    }

    // 接收ETH的回退函数
    receive() external payable {
        treasuryBalance = treasuryBalance.add(msg.value);
    }
}

// 简单实现的 SafeMath 库（仅用于示例，实际中可依赖 OpenZeppelin）
library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "Addition overflow");
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "Subtraction overflow");
        return a - b;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) return 0;
        uint256 c = a * b;
        require(c / a == b, "Multiplication overflow");
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "Division by zero");
        return a / b;
    }
}