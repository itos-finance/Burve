#!/usr/bin/env python3
"""
Calculate proper EIP-55 checksummed addresses.
"""
from hashlib import sha3_256
import hashlib

def keccak256(data):
    """Calculate Keccak-256 hash."""
    import sha3
    return sha3.keccak_256(data).hexdigest()

def to_checksum_address(address):
    """Convert address to EIP-55 checksummed format."""
    # Remove 0x prefix if present
    address = address.lower().replace('0x', '')

    # Hash the lowercase address
    hash_bytes = bytes.fromhex(address)
    # Use keccak
    try:
        import sha3
        hash_str = sha3.keccak_256(address.encode()).hexdigest()
    except ImportError:
        # Fallback - just return with 0x prefix
        print("Warning: sha3 not installed, install with: pip install pysha3")
        return '0x' + address

    # Build checksummed address
    checksum_address = '0x'
    for i, char in enumerate(address):
        if char in '0123456789':
            checksum_address += char
        else:
            # If the corresponding hex digit is >= 8, uppercase the letter
            if int(hash_str[i], 16) >= 8:
                checksum_address += char.upper()
            else:
                checksum_address += char.lower()

    return checksum_address

# Addresses from the table
addresses = [
    '0x6ea0cd91291baf975ec0e5ec5b5803455360150b',
    '0xc137942872586e5847d66025c9ae04b89053cb58',
    '0x5e031c60a35cd0762970d8e63e6aee2d4c9cbc6b',
    '0x6e7465acBaa3217Bdcc4C17CDbE1DaDbb4356377',
    '0x81785e00055159fcae25703d06422abf5603f8a8',
    '0x36f4e1803f6ff34562db567f347dea00dec87246',
    '0xa916b0f22d9b198268c637506cf83b360716dc32',
    '0x4c6b778e5a5395c86e6f09e1e7b72c9db3958175',
    '0x9f1854fa6d7647bbba30ed79ac767c1424a98f30',
    '0x17e5ec84db5d8210e875b929981d480f122eba14',
    '0x38312022f5c24dd257777f981075fffd20233e19',
    '0xbe7dc5cc7977ac378ead410869d6c96f1e6c773e',
    '0xb6a9f27f861b023c72781561ed479ffb8d033080',
    '0xaaefa1f5a034f0dcddaa265a115f96f62f81bedc',
    '0x4849457118eb68f24dbb81633988012173d02092',
    '0x794c94f1b5e455c1dba27bb28c6085db0fe544f9',
    '0x692c2b93ee954b933837178d83946e695389673d',
    '0xd8f06fe8f88adbb1b9ac08a038755d769b0fcac3',
    '0xbc1f3695ba8b9b992f223a9d6c3c9ca7173d4c30',
    '0x0e3551026855d3c106a77bce2e0823c4a92277c0',
    '0x9b9e06d850216940519fcd77dd7d4fbf7718d28b',
    '0xa0eb44b173af64f2fdb47c7d76ff3a33e04103b6',
    '0x419a2b160c0db5da0011d8aa96f86d7a6fdd25a5',
    '0xf2a3d0e3336dcce72a0b17b5766dad55a91b9d77',
    '0x590f6252ec23e47abddf0643d04ace057d755363',
    '0xd22769fd3ee303ea8facaf9294f6ca526ac8d643',
    '0xd59872a1a30f0a227f6d459f15b2c5526ac0521d',
    '0xa63b833c4bb36bf5e9d1c981fb17a4ff37dd68f3',
    '0x642d6b761d5143207515fbb5a9f3c0365eabd09c',
    '0x0f53809658e5364bbdb368579d2b3d6052cc66d1',
    '0x4f28e484b5da61b05d1be30dea0dbbc594155a9c',
    '0xa58959c1a05c2941d7af49c57f9bc456d2f77c3f',
    '0x0d31ffc3df44921586a0d6d358045c4f6866aba7',
    '0x42db18d76f0cde2a2c6115017f177fffae4d5409',
    '0x823c1ee6b3dd9b353b3c707dfc4afbc775cd4c52',
    '0x1c5f31d2571260047fc0bceafa8aabc1cebecfa0',
    '0x46c9d8fbca2d974f8c0e62f3aeaeda2a3b229709',
    '0x01cb6671dbeb28061ac72a1497b20c2e51c061c8',
    '0x7be8ac53f9943e0e447b1959e4f515be266226be',
    '0x67358b03a25262b0f231f4e2439f5eb1ee3875fb',
    '0x212514e0c3caffe485eafbd625775af5e792c16b',
    '0x970256a45681a36c4f21e5c9ce100dbe464a0b2f',
    '0x3b2342bfb31ef769c5c1c7457565053749e6845c',
    '0x7d7628ffe75b017d6c8235f7567c68dcad10c78d',
]

print("Checksummed addresses:")
for addr in addresses:
    checksum_addr = to_checksum_address(addr)
    print(f"'{checksum_addr}',")
