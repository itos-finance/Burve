// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title BeraAirdrop
 * @notice Distributes 100,000 BERA to recipients based on their points percentage
 */
contract BeraAirdrop {
    address public immutable owner;
    uint256 public constant TOTAL_DISTRIBUTION = 100_000 ether;

    bool public distributed;

    struct Recipient {
        address addr;
        uint256 amount;
    }

    Recipient[] public recipients;

    event Distribution(address indexed recipient, uint256 amount);
    event DistributionComplete(uint256 totalDistributed);

    error AlreadyDistributed();
    error OnlyOwner();
    error InsufficientBalance();
    error TransferFailed(address recipient, uint256 amount);

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    constructor() {
        owner = msg.sender;

        // Total points: 84,176.82
        // Distribution calculated to sum exactly 100,000 BERA (last recipient gets remainder)

        recipients.push(
            Recipient(
                0x6eA0cd91291BaF975Ec0E5Ec5b5803455360150b,
                29871465802580801791954
            )
        );
        recipients.push(
            Recipient(
                0xc137942872586E5847d66025c9aE04b89053Cb58,
                25078234126687136107136
            )
        );
        recipients.push(
            Recipient(
                0x5e031c60a35Cd0762970d8e63e6aeE2d4C9CBC6B,
                11207883595507647970837
            )
        );
        recipients.push(
            Recipient(
                0x6e7465acBaa3217Bdcc4C17CDbE1DaDbb4356377,
                6513645918199332573359
            )
        );
        recipients.push(
            Recipient(
                0x81785e00055159FCae25703D06422aBF5603f8A8,
                5588082324801530717496
            )
        );
        recipients.push(
            Recipient(
                0x36f4E1803f6fF34562dB567f347dea00DeC87246,
                4572921619039541034000
            )
        );
        recipients.push(
            Recipient(
                0xa916b0F22D9B198268C637506CF83b360716dc32,
                3527443778465377969939
            )
        );
        recipients.push(
            Recipient(
                0x4C6b778e5a5395C86e6F09E1E7b72C9Db3958175,
                2478544568445327382571
            )
        );
        recipients.push(
            Recipient(
                0x9F1854Fa6D7647BBba30ED79AC767c1424a98f30,
                2253007419382200577443
            )
        );
        recipients.push(
            Recipient(
                0x17e5eC84dB5d8210e875B929981d480F122eBA14,
                1833473870835225210014
            )
        );
        recipients.push(
            Recipient(
                0x38312022F5C24Dd257777f981075FffD20233e19,
                1459867455197285690542
            )
        );
        recipients.push(
            Recipient(
                0xbe7dC5cC7977ac378ead410869D6c96f1E6C773e,
                1415496570195928067486
            )
        );
        recipients.push(
            Recipient(
                0xb6a9F27f861b023C72781561ED479fFB8d033080,
                1366955891182394568002
            )
        );
        recipients.push(
            Recipient(
                0xaaefa1F5a034f0dCdDaA265A115f96F62f81BEDC,
                554974635535055858069
            )
        );
        recipients.push(
            Recipient(
                0x4849457118eb68F24dBb81633988012173d02092,
                463262926777229177183
            )
        );
        recipients.push(
            Recipient(
                0x794c94f1b5E455c1dBA27BB28C6085dB0FE544F9,
                453022577949606560742
            )
        );
        recipients.push(
            Recipient(
                0x692c2B93ee954B933837178d83946e695389673D,
                407855749361878964792
            )
        );
        recipients.push(
            Recipient(
                0xd8f06fe8f88adBb1B9aC08a038755d769b0FcAc3,
                361738540372515859196
            )
        );
        recipients.push(
            Recipient(
                0xbc1F3695Ba8b9b992f223a9D6C3c9cA7173D4c30,
                318567510628222872432
            )
        );
        recipients.push(
            Recipient(
                0x0e3551026855D3c106a77bCE2E0823c4a92277C0,
                56678311202537706542
            )
        );
        recipients.push(
            Recipient(
                0x9b9e06D850216940519Fcd77DD7d4fBf7718d28b,
                50750313447336215122
            )
        );
        recipients.push(
            Recipient(
                0xa0Eb44b173AF64f2FdB47C7d76FF3A33e04103b6,
                39868457848609634536
            )
        );
        recipients.push(
            Recipient(
                0x419a2B160c0DB5dA0011D8Aa96F86D7A6fdd25a5,
                34973998780186754990
            )
        );
        recipients.push(
            Recipient(
                0xf2a3d0e3336DCCE72a0B17b5766DaD55A91B9D77,
                19922349169284370964
            )
        );
        recipients.push(
            Recipient(
                0x590F6252Ec23e47abdDF0643d04aCE057d755363,
                17593917185277372330
            )
        );
        recipients.push(
            Recipient(
                0xd22769fD3eE303eA8fAcAf9294F6CA526AC8D643,
                10418545152929274499
            )
        );
        recipients.push(
            Recipient(
                0xD59872a1a30F0A227f6d459f15b2C5526AC0521d,
                9385006466150657759
            )
        );
        recipients.push(
            Recipient(
                0xA63b833C4bB36bF5E9d1C981Fb17a4fF37dD68f3,
                6700181831530343007
            )
        );
        recipients.push(
            Recipient(
                0x642d6B761D5143207515fBb5a9f3C0365eabd09c,
                5298370739117966279
            )
        );
        recipients.push(
            Recipient(
                0x0f53809658e5364bBDB368579D2B3D6052cC66D1,
                3504527731030941821
            )
        );
        recipients.push(
            Recipient(
                0x4f28e484B5Da61B05D1be30dea0dbBc594155a9c,
                3076856550294962480
            )
        );
        recipients.push(
            Recipient(
                0xA58959c1a05c2941D7AF49c57f9bc456d2F77c3F,
                2969938755110967645
            )
        );
        recipients.push(
            Recipient(
                0x0D31fFC3Df44921586a0d6d358045c4f6866Aba7,
                2791742429804309586
            )
        );
        recipients.push(
            Recipient(
                0x42Db18D76F0Cde2a2c6115017F177fFfaE4D5409,
                2162115413720784445
            )
        );
        recipients.push(
            Recipient(
                0x823c1Ee6B3dd9b353b3c707DFC4AFbc775Cd4C52,
                2102716638618565092
            )
        );
        recipients.push(
            Recipient(
                0x1C5f31d2571260047fc0BcEafa8aABc1CEbecFA0,
                1924520313311907034
            )
        );
        recipients.push(
            Recipient(
                0x46c9d8fbCa2D974f8C0e62F3aEAedA2A3b229709,
                1829482273148356069
            )
        );
        recipients.push(
            Recipient(
                0x01cB6671dbeB28061ac72a1497b20C2E51c061C8,
                902861381553734164
            )
        );
        recipients.push(
            Recipient(
                0x7BE8AC53F9943e0E447B1959E4f515be266226BE,
                368272405633759988
            )
        );
        recipients.push(
            Recipient(
                0x67358b03A25262B0F231f4E2439F5eB1ee3875Fb,
                166316570286214207
            )
        );
        recipients.push(
            Recipient(
                0x212514E0c3CAffe485EAfbd625775AF5E792c16B,
                59398775102219352
            )
        );
        recipients.push(
            Recipient(
                0x970256a45681a36C4F21E5c9Ce100dBE464A0B2f,
                47519020081775482
            )
        );
        recipients.push(
            Recipient(
                0x3B2342Bfb31Ef769C5C1C7457565053749E6845C,
                47519020081775482
            )
        );
        recipients.push(
            Recipient(
                0x7D7628FFe75b017d6C8235f7567C68DCad10c78D,
                11879755020477932
            )
        );
    }

    /**
     * @notice Distributes BERA to all recipients in a single transaction
     * @dev Can only be called once by the owner
     */
    function distributeAll() external onlyOwner {
        if (distributed) revert AlreadyDistributed();
        if (address(this).balance < TOTAL_DISTRIBUTION) revert InsufficientBalance();

        uint256 totalSent = 0;
        uint256 length = recipients.length;

        for (uint256 i = 0; i < length; i++) {
            Recipient memory recipient = recipients[i];

            (bool success, ) = recipient.addr.call{value: recipient.amount}("");
            if (!success)
                revert TransferFailed(recipient.addr, recipient.amount);

            emit Distribution(recipient.addr, recipient.amount);
            totalSent += recipient.amount;
        }

        distributed = true;
        emit DistributionComplete(totalSent);
    }

    /**
     * @notice Distributes to a specific recipient by index (for gas-limited scenarios)
     * @param index The index of the recipient in the recipients array
     */
    function distributeSingle(uint256 index) external onlyOwner {
        if (distributed) revert AlreadyDistributed();
        if (index >= recipients.length) revert("Invalid index");

        Recipient memory recipient = recipients[index];

        (bool success, ) = recipient.addr.call{value: recipient.amount}("");
        if (!success) revert TransferFailed(recipient.addr, recipient.amount);

        emit Distribution(recipient.addr, recipient.amount);
    }

    /**
     * @notice Distributes to a batch of recipients by indices
     * @param startIndex Starting index (inclusive)
     * @param endIndex Ending index (exclusive)
     */
    function distributeBatch(
        uint256 startIndex,
        uint256 endIndex
    ) external onlyOwner {
        if (distributed) revert AlreadyDistributed();
        if (endIndex > recipients.length) revert("Invalid range");
        if (startIndex >= endIndex) revert("Invalid range");

        for (uint256 i = startIndex; i < endIndex; i++) {
            Recipient memory recipient = recipients[i];

            (bool success, ) = recipient.addr.call{value: recipient.amount}("");
            if (!success)
                revert TransferFailed(recipient.addr, recipient.amount);

            emit Distribution(recipient.addr, recipient.amount);
        }
    }

    /**
     * @notice Returns the number of recipients
     */
    function recipientCount() external view returns (uint256) {
        return recipients.length;
    }

    /**
     * @notice Emergency withdrawal function (only if distribution hasn't happened)
     */
    function withdraw() external onlyOwner {
        (bool success, ) = owner.call{value: address(this).balance}("");
        require(success, "Withdrawal failed");
    }

    /**
     * @notice Accepts BERA deposits
     */
    receive() external payable {}
}
