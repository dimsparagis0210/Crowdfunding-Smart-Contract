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

    // 1000000000000000000 wei = 1 eth

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
    uint256 public campaignFee; // Τέλος καμπάνιας
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
        totalFeesCollected = 0;
    }

    // Συναρτήσεις
    // 1. Δημιουργία καμπάνιας
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
        // Δημιουργία καινούριας καμπάνιας και ανανέωση των ιδιοτήτων της
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

    // 2. Χρηματοδότηση καμπάνιας
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
        // Εύρεση καμπάνιας με βάση το campaignId στο mapping campaigns
        Campaign storage campaign = campaigns[campaignId];
        require(
            msg.sender != campaign.entrepreneur,
            "The entrepreneur can't fund"
        );

        uint256 totalCost = campaign.sharePrice * numberOfShares;

        require(msg.value == totalCost, "Incorrect Wei value sent");

        // Αύξηση του αριθμού των αγορασμένων μετοχών και ανανέωση των δομών δεδομένων που αφορούν τους επενδυτές
        campaign.currentShares += numberOfShares;
        if (campaign.sharesPerBacker[msg.sender] == 0) {
            campaign.backers.push(msg.sender);
        }
        campaign.sharesPerBacker[msg.sender] += numberOfShares;

        emit SharesPurchased(campaignId, msg.sender, numberOfShares);
    }

    // 3. Ακύρωση καμπάνιας
    function cancelCampaign(uint256 campaignId)
        public
        activeCampaign(campaignId)
        notCompleted(campaignId)
        activeContract
    {
        // Εύρεση καμπάνιας με βάση το campaignId στο mapping campaigns
        Campaign storage campaign = campaigns[campaignId];
        require(
            msg.sender == campaign.entrepreneur || msg.sender == owner,
            "Only the entrepreneur or owner can cancel this campaign"
        );

        // Απενεργοποίηση και ακύρωση καμπάνιας
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

    // Αποζημίωση επενδυτή
    function refundInvestor(address investor) public notBanned {
        // Εύρεση ποσού αποζημίωσης για τον επενδυτή
        uint256 refundAmount = refunds[investor];
        require(refundAmount > 0, "No refund available for this investor");

        // Επαναφορά του ποσού αποζημίωσης στο 0
        refunds[investor] = 0;

        // Μεταφορά των χρημάτων στον επενδυτή
        payable(investor).transfer(refundAmount);

        emit InvestorRefunded(investor, refundAmount);
    }

    // 5. Ολοκλήρωση καμπάνιας
    function completeCampaign(uint256 campaignId)
        public
        activeCampaign(campaignId)
        notCancelled(campaignId)
    {
        // Εύρεση καμπάνιας με βάση το campaignId στο mapping campaigns
        Campaign storage campaign = campaigns[campaignId];

        require(
            msg.sender == campaign.entrepreneur || msg.sender == owner,
            "Only the entrepreneur or owner can complete this campaign"
        );
        require(
            campaign.currentShares == campaign.totalShares,
            "Campaign does not have enough shares"
        );

        // Υπολογισμός αμοιβής επιχειρηματία για την ολοκλήρωση της συγκεκριμένης καμπάνιας
        uint256 campaignBalance = campaign.currentShares * campaign.sharePrice;
        uint256 entrepreneurPayout = (campaignBalance * 80) / 100;

        // Μεταφορά της αμοιβής στον επενδυτή
        payable(campaign.entrepreneur).transfer(entrepreneurPayout);

        // Μεταφορά του υπόλοιπου 20% στα τέλη του συμβολαίου
        uint256 fees = campaignBalance - entrepreneurPayout;
        totalFeesCollected += fees;

        // Απενεργοποίηση και ολοκλήρωση καμπάνιας
        campaign.isActive = false;
        campaign.isCompleted = true;

        emit CampaignCompleted(campaignId, msg.sender, campaign.title);
    }

    // 6. Απόσυρση κρατήσεων
    function withdrawFees() public onlyOwner activeContract {
        uint256 amount = totalFeesCollected;

        // Επαναφορά της global μεταβλητής για τις κρατήσεις
        totalFeesCollected = 0;

        // Μεταφορά των κρατήσεων στον ιδιοκτήτη του συμβολαίου
        payable(owner).transfer(amount);
        uint256 remaining = address(this).balance;

        emit FeesWithdrawn(owner, amount + remaining);
    }

    // 7. Getters
    // Ενεργές καμπάνιες
    function getActiveCampaigns()
        public
        view
        activeContract
        returns (CampaignInfo[] memory)
    {
        uint256 activeCount = 0;

        // Μέτρηση των ενεργών καμπάνιων
        for (uint256 i = 0; i < campaignCounter; i++) {
            if (!campaigns[i].isCompleted && !campaigns[i].isCancelled) {
                activeCount++;
            }
        }

        // Δημιουργία array για αποθήκευση των ενεργών καμπάνιων
        CampaignInfo[] memory activeCampaigns = new CampaignInfo[](activeCount);
        uint256 index = 0;

        // Προσθήκη ενεργών καμπάνιων στο array
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

    // Ολοκληρωμένες καμπάνιες
    function getCompletedCampaigns()
        public
        view
        activeContract
        returns (CampaignInfo[] memory)
    {
        uint256 activeCount = 0;

        // Μέτρηση των ολοκληρωμένων καμπάνιων
        for (uint256 i = 0; i < campaignCounter; i++) {
            if (campaigns[i].isCompleted && !campaigns[i].isCancelled) {
                activeCount++;
            }
        }

        // Δημιουργία array για αποθήκευση των ολοκληρωμένων καμπάνιων
        CampaignInfo[] memory completedCampaigns = new CampaignInfo[](
            activeCount
        );
        uint256 index = 0;

        // Προσθήκη ολοκληρωμένων καμπάνιων στο array
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

    // Ακυρωμένες καμπάνιες
    function getCancelledCampaigns()
        public
        view
        activeContract
        returns (CampaignInfo[] memory)
    {
        uint256 cancelledCount = 0;

        // Μέτρηση των ακυρωμένων καμπάνιων
        for (uint256 i = 0; i < campaignCounter; i++) {
            if (campaigns[i].isCancelled) {
                cancelledCount++;
            }
        }

        // Δημιουργία array για αποθήκευση των ακυρωμένων καμπάνιων
        CampaignInfo[] memory cancelledCampaigns = new CampaignInfo[](
            cancelledCount
        );
        uint256 index = 0;

        // Προσθήκη ακυρωμένων καμπάνιων στο array
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

    // Πληροφορίες για τους επενδυτές μιας καμπάνιας
    function getInvestorsAndShares(uint256 campaignId)
        public
        view
        activeContract
        campaignExists(campaignId)
        returns (address[] memory investors, uint256[] memory shares)
    {
        // Εύρεση καμπάνιας με βάση το campaignId στο mapping campaigns
        Campaign storage campaign = campaigns[campaignId];

        // Αποθήκευση των επενδυτών και των μετοχών τους
        uint256 investorCount = campaign.backers.length;
        investors = new address[](investorCount);
        shares = new uint256[](investorCount);

        // Ενημέρωση των δομών δεδομένων εξόδου
        for (uint256 i = 0; i < investorCount; i++) {
            address backer = campaign.backers[i];
            investors[i] = backer;
            shares[i] = campaign.sharesPerBacker[backer];
        }
    }

    // Πληροφορίες για τις επενδύσεις ενός επενσυτή
    function getInvestmentsByInvestor(address investor)
        public
        view
        returns (uint256[] memory campaignIds, uint256[] memory shares)
    {
        uint256 investmentCount = 0;

        // Μέτρηση του αριθμού επενδύσεων ενός επενδυτή
        for (uint256 i = 0; i < campaignCounter; i++) {
            if (campaigns[i].sharesPerBacker[investor] > 0) {
                investmentCount++;
            }
        }

        // Δημιουργία arrays για αποθήκευση των αποτελεσμάτων
        campaignIds = new uint256[](investmentCount);
        shares = new uint256[](investmentCount);

        // Εύρεση των αριθμών μετοχών που κατέχει ο επενδυτής για κάθε καμπάνια
        uint256 index = 0;
        for (uint256 i = 0; i < campaignCounter; i++) {
            uint256 investorShares = campaigns[i].sharesPerBacker[investor];
            if (investorShares > 0) {
                campaignIds[index] = i;
                shares[index] = investorShares;
                index++;
            }
        }

        return (campaignIds, shares);
    }

    // Αποκλεισμός επενδυτή
    function banInvestor(address investor)
        public
        activeContract
        onlyOwner
        notBanned
    {
        // Προσθήκη στη λίστα banned
        bannedList[investor] = true;
        bannedAddresses.push(investor);
        bannedCounter++;
    }

    // Αλλαγή ιδιοκτήτη συμβολαίου
    function changeOwner(address newOwner) public onlyOwner activeContract {
        require(newOwner != address(0), "New owner cannot be the zero address");
        owner = newOwner;
    }

    // Καταστροφή συμβολαίου
    function destroyContract() public onlyOwner activeContract {
        // Ακύρωση ενεργών καμπάνιων
        for (uint256 i = 0; i < campaignCounter; i++) {
            // Εύρεση καμπάνιας με βάση το campaignId στο mapping campaigns
            Campaign storage campaign = campaigns[i];

            // Προσπέραση των ολοκληρωμένων και ακυρωμένων καμπάνιων
            if (campaign.isCancelled || campaign.isCompleted) {
                continue;
            }

            // Απενεργοποίηση και ακύρωση της καμπάνιας
            campaign.isActive = false;
            campaign.isCancelled = true;

            // Ανανέωση της δομής refunds για μελλοντική αποζημείωση επενδυτών
            for (uint256 j = 0; j < campaign.backers.length; j++) {
                address backer = campaign.backers[j];
                uint256 shares = campaign.sharesPerBacker[backer];
                uint256 refundAmount = shares * campaign.sharePrice;
                refunds[backer] += refundAmount;
            }
        }

        // Ανανέωση σφαιρικής μεταβλητής
        isContractActive = false;
    }
}
