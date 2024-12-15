// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

contract Crowdfunding {
    struct Campaign {
        uint256 campaignId;
        address entrepreneur;
        string title;
        uint256 sharePrice;
        uint256 totalShares;
        uint256 currentShares;
        bool isActive;
        bool isCancelled;
        bool isCompleted;
        address[] backers;
        mapping(address => uint256) sharesPerBacker;
    }

    struct CampaignInfo {
        uint256 campaignId;
        address entrepreneur;
        string title;
        uint256 pledgeCost;
        uint256 pledgesNeeded;
        uint256 pledgesCount;
        bool fulfilled;
        bool cancelled;
    }

    address public owner; // Ιδιοκτήτης συμβολαίου
    uint256 public campaignFee; // Τέλος καμπάνιας (π.χ. 0.02 Ether)
    uint256 public totalFeesCollected; // Συνολικά συγκεντρωμένα fees
    uint256 private campaignCounter; // Αύξων αριθμός για καμπάνιες
    mapping(uint256 => Campaign) public campaigns; // Αποθήκευση καμπανιών
    uint256 public bannedCounter;
    mapping(address => bool) public bannedList; // Λίστα αποκλεισμένων
    address[] public bannedAddresses;
    mapping(address => uint256) public refunds; // Ποσά προς επιστροφή για επενδυτές
    bool isContractActive;

    // Events
    event CampaignCreated(
        uint256 campaignId,
        address entrepreneur,
        string title
    );
    event CampaignCancelled(
        uint256 campaignId,
        address entrepreneur,
        string title
    );
    event CampaignCompleted(
        uint256 campaignId,
        address entrepreneur,
        string title
    );
    event SharesPurchased(uint256 campaignId, address investor, uint256 shares);
    event InvestorRefunded(address investor, uint256 amount);
    event FeesWithdrawn(address owner, uint256 amount);

    // Modifiers
    modifier onlyOwner() {
        require(
            msg.sender == owner,
            "Only the contract owner can execute this"
        );
        _;
    }

    modifier activeContract() {
        require(isContractActive, "Contract is not active");
        _;
    }

    modifier notOwner() {
        require(
            msg.sender != owner,
            "The contract owner can't perform further actions"
        );
        _;
    }

    modifier notBanned() {
        require(!bannedList[msg.sender], "Address is banned");
        _;
    }

    modifier activeCampaign(uint256 campaignId) {
        require(campaigns[campaignId].isActive, "Campaign is not active");
        _;
    }

    modifier notCancelled(uint256 campaignId) {
        require(!campaigns[campaignId].isCancelled, "Campaign is cancelled");
        _;
    }

    modifier notCompleted(uint256 campaignId) {
        require(
            !campaigns[campaignId].isCompleted,
            "Campaign is already completed"
        );
        _;
    }

    modifier feeGiven() {
        require(msg.value == campaignFee, "Incorrect campaign fee");
        _;
    }

    modifier enoughShares(uint256 shares) {
        require(shares > 0, "Total shares must be greater than zero");
        _;
    }
    modifier campaignExists(uint256 campaignId) {
        require(
            campaignId > 0 && campaignId <= campaignCounter,
            "Invalid campaign ID"
        );
        _;
    }

    constructor(uint256 _campaignFee) {
        owner = msg.sender;
        campaignFee = _campaignFee;
        isContractActive = true;
    }

    // Functions
    // 1. Create the Campaign
    function createCampaign(
        string memory title,
        uint256 sharePrice,
        uint256 totalShares
    )
        public
        payable
        notOwner
        notBanned
        feeGiven
        enoughShares(totalShares)
        activeContract
    {
        Campaign storage newCampaign = campaigns[campaignCounter];
        newCampaign.campaignId = campaignCounter;
        newCampaign.entrepreneur = msg.sender;
        newCampaign.title = title;
        newCampaign.sharePrice = sharePrice;
        newCampaign.totalShares = totalShares;
        newCampaign.isActive = true;
        campaignCounter++;

        totalFeesCollected += campaignFee;

        emit CampaignCreated(campaignCounter, msg.sender, title);
    }

    // 2. Campaign Funding
    function campaignFunding(uint256 numberOfShares, uint256 campaignId)
        public
        payable
        notOwner
        notBanned
        activeCampaign(campaignId)
        notCancelled(campaignId)
        notCompleted(campaignId)
        activeContract
    {
        Campaign storage campaign = campaigns[campaignId];
        require(
            msg.sender != campaign.entrepreneur,
            "The entrepreneur can't fund"
        );

        uint256 totalCost = campaign.sharePrice * numberOfShares;

        // Checking if backer is paying enough eth for the number of shares he asked
        require(msg.value == totalCost, "Incorrect Wei value sent");

        campaign.currentShares += numberOfShares;
        campaign.sharesPerBacker[msg.sender] += numberOfShares;
        campaign.backers.push(msg.sender);

        emit SharesPurchased(campaignId, msg.sender, numberOfShares);
    }

    // 3. Cancel Campaign
    function cancelCampaign(uint256 campaignId)
        public
        activeCampaign(campaignId)
        notCompleted(campaignId)
        activeContract
    {
        Campaign storage campaign = campaigns[campaignId];
        require(
            msg.sender == campaign.entrepreneur || msg.sender == owner,
            "Only the entrepreneur or owner can cancel this campaign"
        );

        campaign.isActive = false;
        campaign.isCancelled = true;

        // Καταγραφή ποσών για επιστροφή στους επενδυτές
        for (uint256 i = 0; i < campaign.backers.length; i++) {
            address backer = campaign.backers[i];
            uint256 shares = campaign.sharesPerBacker[backer];
            uint256 refundAmount = shares * campaign.sharePrice;
            refunds[backer] += refundAmount;
        }

        emit CampaignCancelled(campaignId, msg.sender, campaign.title);
    }

    function refundInvestor(address investor) public {
        // Ensure the caller is either the owner or the investor themselves
        require(
            msg.sender == investor || msg.sender == owner,
            "Only the investor or the contract owner can initiate a refund"
        );

        // Retrieve the refund amount for the specified investor
        uint256 refundAmount = refunds[investor];
        require(refundAmount > 0, "No refund available for this investor");

        // Reset the refund amount for the investor
        refunds[investor] = 0;

        // Transfer the refund amount to the specified investor
        payable(investor).transfer(refundAmount);

        // Emit an event for logging purposes
        emit InvestorRefunded(investor, refundAmount);
    }

    // 5. Campaign Completion
    function completeCampaign(uint256 campaignId)
        public
        activeCampaign(campaignId)
        notCancelled(campaignId)
        activeContract
    {
        Campaign storage campaign = campaigns[campaignId];
        require(
            msg.sender == campaign.entrepreneur || msg.sender == owner,
            "Only the entrepreneur or owner can complete this campaign"
        );
        require(
            campaign.currentShares >= campaign.totalShares,
            "Campaign does not have enough shares"
        );

        uint256 entrepreneurPayout = (address(this).balance * 80) / 100;
        payable(campaign.entrepreneur).transfer(entrepreneurPayout);

        totalFeesCollected = (address(this).balance * 20) / 100;

        campaign.isActive = false;
        campaign.isCompleted = true;

        emit CampaignCompleted(campaignId, msg.sender, campaign.title);
    }

    // 6. Other functionality
    function withdrawFees() public onlyOwner activeContract {
        uint256 amount = totalFeesCollected;
        totalFeesCollected = 0;

        payable(owner).transfer(amount);
        uint256 remaining = address(this).balance;
        emit FeesWithdrawn(owner, amount + remaining);
    }

    function getActiveCount() public view returns (uint256) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < campaignCounter; i++) {
            if (!campaigns[i].isCompleted && !campaigns[i].isCancelled) {
                activeCount++;
            }
        }
        return activeCount;
    }

    // 7. Getters
    // Active Campaigns
    function getActiveCampaigns() public view returns (CampaignInfo[] memory) {
        uint256 activeCount = 0;

        // Count active campaigns
        for (uint256 i = 0; i < campaignCounter; i++) {
            if (!campaigns[i].isCompleted && !campaigns[i].isCancelled) {
                activeCount++;
            }
        }

        // Create an array in memory for the results
        CampaignInfo[] memory activeCampaigns = new CampaignInfo[](activeCount);
        uint256 index = 0;

        // Add active campaigns to the result
        for (uint256 i = 0; i < campaignCounter; i++) {
            if (!campaigns[i].isCompleted && !campaigns[i].isCancelled) {
                activeCampaigns[index] = CampaignInfo(
                    campaigns[i].campaignId,
                    campaigns[i].entrepreneur,
                    campaigns[i].title,
                    campaigns[i].sharePrice,
                    campaigns[i].totalShares - campaigns[i].currentShares,
                    campaigns[i].currentShares,
                    campaigns[i].isCompleted,
                    campaigns[i].isCancelled
                );
                index++;
            }
        }

        return activeCampaigns;
    }

    // Completed campaigns
    function getCompletedCampaigns()
        public
        view
        returns (CampaignInfo[] memory)
    {
        uint256 activeCount = 0;

        // Count completed campaigns
        for (uint256 i = 0; i < campaignCounter; i++) {
            if (campaigns[i].isCompleted && !campaigns[i].isCancelled) {
                activeCount++;
            }
        }

        // Create an array in memory for the results
        CampaignInfo[] memory completedCampaigns = new CampaignInfo[](
            activeCount
        );
        uint256 index = 0;

        // Add completed campaigns to the result
        for (uint256 i = 0; i < campaignCounter; i++) {
            if (campaigns[i].isCompleted && !campaigns[i].isCancelled) {
                completedCampaigns[index] = CampaignInfo(
                    campaigns[i].campaignId,
                    campaigns[i].entrepreneur,
                    campaigns[i].title,
                    campaigns[i].sharePrice,
                    campaigns[i].totalShares - campaigns[i].currentShares,
                    campaigns[i].currentShares,
                    campaigns[i].isCompleted,
                    campaigns[i].isCancelled
                );
                index++;
            }
        }

        return completedCampaigns;
    }

    // Cancelled campaigns
    function getCancelledCampaigns()
        public
        view
        returns (CampaignInfo[] memory)
    {
        uint256 cancelledCount = 0;

        // Count cancelled campaigns
        for (uint256 i = 0; i < campaignCounter; i++) {
            if (campaigns[i].isCancelled) {
                cancelledCount++;
            }
        }

        // Create an array in memory for the results
        CampaignInfo[] memory cancelledCampaigns = new CampaignInfo[](
            cancelledCount
        );
        uint256 index = 0;

        // Add cancelled campaigns to the result
        for (uint256 i = 0; i < campaignCounter; i++) {
            if (campaigns[i].isCancelled) {
                cancelledCampaigns[index] = CampaignInfo(
                    campaigns[i].campaignId,
                    campaigns[i].entrepreneur,
                    campaigns[i].title,
                    campaigns[i].sharePrice,
                    campaigns[i].totalShares,
                    campaigns[i].currentShares,
                    campaigns[i].isCompleted,
                    campaigns[i].isCancelled
                );
                index++;
            }
        }

        return cancelledCampaigns;
    }

    // Fees
    function getTotalFees() public view returns (uint256 totalFees) {
        uint256 campaignCreationFees = campaignCounter * campaignFee; // Flat fees for all campaigns
        uint256 completionFees = 0;

        // Calculate 20% fees from completed campaigns
        for (uint256 i = 0; i < campaignCounter; i++) {
            if (campaigns[i].isCompleted) {
                uint256 campaignFunds = campaigns[i].totalShares *
                    campaigns[i].sharePrice;
                completionFees += (campaignFunds * 20) / 100; // 20% fee
            }
        }

        // Total fees are the sum of flat and completion fees
        totalFees = campaignCreationFees + completionFees;
    }

    // Banned Investors
    function getBannedInvestors() public view returns (address[] memory) {
        return bannedAddresses;
    }

    // Info about campaign's investors
    function getInvestorsAndShares(uint256 campaignId)
        public
        view
        campaignExists(campaignId)
        returns (address[] memory investors, uint256[] memory shares)
    {
        Campaign storage campaign = campaigns[campaignId];

        // Αποθήκευσε τους επενδυτές και τις μετοχές τους
        uint256 investorCount = campaign.backers.length;
        investors = new address[](investorCount);
        shares = new uint256[](investorCount);

        for (uint256 i = 0; i < investorCount; i++) {
            address backer = campaign.backers[i];
            investors[i] = backer;
            shares[i] = campaign.sharesPerBacker[backer];
        }
    }

    // Add an investor in the banned list
    function banInvestor(address investor) public onlyOwner notBanned {
        // Προσθήκη στη λίστα banned
        bannedList[investor] = true;
        bannedAddresses.push(investor);
        bannedCounter++;
    }

    // Change contract owner
    function changeOwner(address newOwner) public onlyOwner {
        require(newOwner != address(0), "New owner cannot be the zero address");
        owner = newOwner;
    }

    // Destroy Contract
    function destroyContract() public onlyOwner {
        for (uint256 i = 0; i < campaignCounter; i++) {
            Campaign storage campaign = campaigns[i];

            // Skip already cancelled or completed campaigns
            if (campaign.isCancelled || campaign.isCompleted) {
                continue;
            }

            campaign.isActive = false;
            campaign.isCancelled = true;

            // Record refunds for all investors in the campaign
            for (uint256 j = 0; j < campaign.backers.length; j++) {
                address backer = campaign.backers[j];
                uint256 shares = campaign.sharesPerBacker[backer];
                uint256 refundAmount = shares * campaign.sharePrice;
                refunds[backer] += refundAmount;
            }
        }
    }
}
