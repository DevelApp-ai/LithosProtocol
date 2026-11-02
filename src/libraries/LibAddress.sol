// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

/// @title LibAddress
/// @notice Library for address operations and validations
/// @dev Provides utilities for working with Ethereum addresses
/// @author LithosProtocol Team
library LibAddress {
    // ====================== CONSTANTS ======================

    /// @dev Zero address
    address internal constant ADDRESS_ZERO = address(0);

    /// @dev Sentinel address for the end of a linked list
    address internal constant SENTINEL_ADDRESS = address(1);

    /// @dev EIP-1967 Proxy implementation slot
    bytes32 internal constant IMPLEMENTATION_SLOT = 
        bytes32(uint256(keccak256('eip1967.proxy.implementation')) - 1);

    /// @dev EIP-1967 Proxy admin slot
    bytes32 internal constant ADMIN_SLOT = 
        bytes32(uint256(keccak256('eip1967.proxy.admin')) - 1);

    // ====================== VALIDATION ======================

    /// @notice Checks if an address is the zero address
    /// @param addr The address to check
    /// @return Whether the address is zero
    function isZero(address addr) internal pure returns (bool) {
        return addr == ADDRESS_ZERO;
    }

    /// @notice Checks if an address is not the zero address
    /// @param addr The address to check
    /// @return Whether the address is not zero
    function isNotZero(address addr) internal pure returns (bool) {
        return addr != ADDRESS_ZERO;
    }

    /// @notice Validates that an address is not zero
    /// @dev Reverts if the address is zero
    /// @param addr The address to validate
    function requireNotZero(address addr) internal pure {
        require(isNotZero(addr), "LibAddress: address cannot be zero");
    }

    /// @notice Validates that an address is a contract
    /// @dev Reverts if the address is not a contract
    /// @param addr The address to validate
    function requireIsContract(address addr) internal view {
        require(isContract(addr), "LibAddress: address is not a contract");
    }

    /// @notice Validates that an address is not a contract (EOA)
    /// @dev Reverts if the address is a contract
    /// @param addr The address to validate
    function requireIsEOA(address addr) internal view {
        require(isEOA(addr), "LibAddress: address is a contract");
    }

    /// @notice Checks if an address is a contract
    /// @dev Uses extcodesize which returns > 0 for contracts
    /// @param addr The address to check
    /// @return Whether the address is a contract
    function isContract(address addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }

    /// @notice Checks if an address is an EOA (Externally Owned Account)
    /// @param addr The address to check
    /// @return Whether the address is an EOA
    function isEOA(address addr) internal view returns (bool) {
        return !isContract(addr);
    }

    // ====================== COMPARISON ======================

    /// @notice Checks if two addresses are equal
    /// @param a First address
    /// @param b Second address
    /// @return Whether the addresses are equal
    function equal(address a, address b) internal pure returns (bool) {
        return a == b;
    }

    /// @notice Checks if two addresses are not equal
    /// @param a First address
    /// @param b Second address
    /// @return Whether the addresses are not equal
    function notEqual(address a, address b) internal pure returns (bool) {
        return a != b;
    }

    /// @notice Checks if an address is one of multiple addresses
    /// @param addr The address to check
    /// @param addresses The array of addresses to check against
    /// @return Whether the address is in the array
    function isIn(address addr, address[] memory addresses) internal pure returns (bool) {
        for (uint256 i = 0; i < addresses.length; i++) {
            if (equal(addr, addresses[i])) {
                return true;
            }
        }
        return false;
    }

    /// @notice Checks if all addresses in an array are unique
    /// @param addresses The array of addresses to check
    /// @return Whether all addresses are unique
    function areUnique(address[] memory addresses) internal pure returns (bool) {
        for (uint256 i = 0; i < addresses.length; i++) {
            for (uint256 j = i + 1; j < addresses.length; j++) {
                if (equal(addresses[i], addresses[j])) {
                    return false;
                }
            }
        }
        return true;
    }

    /// @notice Checks if any address in an array is zero
    /// @param addresses The array of addresses to check
    /// @return Whether any address is zero
    function hasZero(address[] memory addresses) internal pure returns (bool) {
        for (uint256 i = 0; i < addresses.length; i++) {
            if (isZero(addresses[i])) {
                return true;
            }
        }
        return false;
    }

    /// @notice Checks if all addresses in an array are non-zero
    /// @param addresses The array of addresses to check
    /// @return Whether all addresses are non-zero
    function allNonZero(address[] memory addresses) internal pure returns (bool) {
        return !hasZero(addresses);
    }

    // ====================== SORTING ======================

    /// @notice Sorts an array of addresses in ascending order
    /// @dev Uses bubble sort (not the most efficient but simple)
    /// @param addresses The array of addresses to sort
    /// @return The sorted array
    function sortAscending(address[] memory addresses) internal pure returns (address[] memory) {
        address[] memory sorted = copyArray(addresses);
        _bubbleSortAscending(sorted);
        return sorted;
    }

    /// @notice Sorts an array of addresses in descending order
    /// @dev Uses bubble sort (not the most efficient but simple)
    /// @param addresses The array of addresses to sort
    /// @return The sorted array
    function sortDescending(address[] memory addresses) internal pure returns (address[] memory) {
        address[] memory sorted = copyArray(addresses);
        _bubbleSortDescending(sorted);
        return sorted;
    }

    /// @notice Internal bubble sort for ascending order
    /// @param addresses The array to sort
    function _bubbleSortAscending(address[] memory addresses) internal pure {
        for (uint256 i = 0; i < addresses.length - 1; i++) {
            for (uint256 j = 0; j < addresses.length - i - 1; j++) {
                if (uint256(uint160(addresses[j])) > uint256(uint160(addresses[j + 1]))) {
                    (addresses[j], addresses[j + 1]) = (addresses[j + 1], addresses[j]);
                }
            }
        }
    }

    /// @notice Internal bubble sort for descending order
    /// @param addresses The array to sort
    function _bubbleSortDescending(address[] memory addresses) internal pure {
        for (uint256 i = 0; i < addresses.length - 1; i++) {
            for (uint256 j = 0; j < addresses.length - i - 1; j++) {
                if (uint256(uint160(addresses[j])) < uint256(uint160(addresses[j + 1]))) {
                    (addresses[j], addresses[j + 1]) = (addresses[j + 1], addresses[j]);
                }
            }
        }
    }

    // ====================== ARRAY OPERATIONS ======================

    /// @notice Copies an array of addresses
    /// @param addresses The array to copy
    /// @return The copied array
    function copyArray(address[] memory addresses) internal pure returns (address[] memory) {
        address[] memory copy = new address[](addresses.length);
        for (uint256 i = 0; i < addresses.length; i++) {
            copy[i] = addresses[i];
        }
        return copy;
    }

    /// @notice Concatenates two arrays of addresses
    /// @param a First array
    /// @param b Second array
    /// @return The concatenated array
    function concat(
        address[] memory a,
        address[] memory b
    ) internal pure returns (address[] memory) {
        address[] memory result = new address[](a.length + b.length);
        for (uint256 i = 0; i < a.length; i++) {
            result[i] = a[i];
        }
        for (uint256 i = 0; i < b.length; i++) {
            result[a.length + i] = b[i];
        }
        return result;
    }

    /// @notice Removes an address from an array
    /// @param addresses The array to remove from
    /// @param addr The address to remove
    /// @return The array with the address removed
    function remove(
        address[] memory addresses,
        address addr
    ) internal pure returns (address[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < addresses.length; i++) {
            if (!equal(addresses[i], addr)) {
                count++;
            }
        }

        address[] memory result = new address[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < addresses.length; i++) {
            if (!equal(addresses[i], addr)) {
                result[index] = addresses[i];
                index++;
            }
        }
        return result;
    }

    /// @notice Removes duplicates from an array of addresses
    /// @param addresses The array to deduplicate
    /// @return The array with duplicates removed
    function unique(address[] memory addresses) internal pure returns (address[] memory) {
        address[] memory result = new address[](addresses.length);
        uint256 count = 0;

        for (uint256 i = 0; i < addresses.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < count; j++) {
                if (equal(addresses[i], result[j])) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                result[count] = addresses[i];
                count++;
            }
        }

        address[] memory finalResult = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            finalResult[i] = result[i];
        }
        return finalResult;
    }

    /// @notice Checks if two arrays of addresses are equal
    /// @param a First array
    /// @param b Second array
    /// @return Whether the arrays are equal
    function arraysEqual(
        address[] memory a,
        address[] memory b
    ) internal pure returns (bool) {
        if (a.length != b.length) {
            return false;
        }
        for (uint256 i = 0; i < a.length; i++) {
            if (!equal(a[i], b[i])) {
                return false;
            }
        }
        return true;
    }

    /// @notice Gets the index of an address in an array
    /// @param addresses The array to search
    /// @param addr The address to find
    /// @return The index of the address, or -1 if not found
    function indexOf(
        address[] memory addresses,
        address addr
    ) internal pure returns (int256) {
        for (uint256 i = 0; i < addresses.length; i++) {
            if (equal(addresses[i], addr)) {
                return int256(i);
            }
        }
        return -1;
    }

    /// @notice Checks if an array contains an address
    /// @param addresses The array to search
    /// @param addr The address to find
    /// @return Whether the address is in the array
    function contains(
        address[] memory addresses,
        address addr
    ) internal pure returns (bool) {
        return indexOf(addresses, addr) >= 0;
    }

    /// @notice Gets the first address from an array
    /// @param addresses The array
    /// @return The first address
    function first(address[] memory addresses) internal pure returns (address) {
        require(addresses.length > 0, "LibAddress: array is empty");
        return addresses[0];
    }

    /// @notice Gets the last address from an array
    /// @param addresses The array
    /// @return The last address
    function last(address[] memory addresses) internal pure returns (address) {
        require(addresses.length > 0, "LibAddress: array is empty");
        return addresses[addresses.length - 1];
    }

    /// @notice Gets a slice of an array
    /// @param addresses The array to slice
    /// @param start The starting index
    /// @param length The length of the slice
    /// @return The sliced array
    function slice(
        address[] memory addresses,
        uint256 start,
        uint256 length
    ) internal pure returns (address[] memory) {
        require(
            start + length <= addresses.length,
            "LibAddress: slice out of bounds"
        );

        address[] memory result = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = addresses[start + i];
        }
        return result;
    }

    // ====================== PROXY OPERATIONS ======================

    // ====================== ADDRESS GENERATION ======================

    /// @notice Creates a deterministic address from a seed
    /// @dev Uses create2 opcode to generate a deterministic address
    /// @param seed The seed for address generation
    /// @return The deterministic address
    function deterministicAddress(bytes32 seed) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(seed)))));
    }

    /// @notice Creates a deterministic address from a seed and salt
    /// @dev Uses create2 opcode to generate a deterministic address
    /// @param seed The seed for address generation
    /// @param salt The salt for address generation
    /// @return The deterministic address
    function deterministicAddress(
        bytes32 seed,
        bytes32 salt
    ) internal pure returns (address) {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(seed, salt)
                    )
                )
            )
        );
    }

    // ====================== ADDRESS FORMATTING ======================

    /// @notice Converts an address to a string (hex format)
    /// @dev Returns the address as a hex string (e.g., "0x123...")
    /// @param addr The address to convert
    /// @return The address as a hex string
    function toString(address addr) internal pure returns (string memory) {
        bytes32 temp = bytes32(uint256(uint160(addr)));
        bytes memory buffer = abi.encodePacked(
            "0x",
            _toHexString(uint8(uint256(temp >> 120))),
            _toHexString(uint8(uint256(temp >> 112))),
            _toHexString(uint8(uint256(temp >> 104))),
            _toHexString(uint8(uint256(temp >> 96))),
            _toHexString(uint8(uint256(temp >> 88))),
            _toHexString(uint8(uint256(temp >> 80))),
            _toHexString(uint8(uint256(temp >> 72))),
            _toHexString(uint8(uint256(temp >> 64))),
            _toHexString(uint8(uint256(temp >> 56))),
            _toHexString(uint8(uint256(temp >> 48))),
            _toHexString(uint8(uint256(temp >> 40))),
            _toHexString(uint8(uint256(temp >> 32))),
            _toHexString(uint8(uint256(temp >> 24))),
            _toHexString(uint8(uint256(temp >> 16))),
            _toHexString(uint8(uint256(temp >> 8))),
            _toHexString(uint8(uint256(temp)))
        );
        return string(buffer);
    }

    /// @notice Converts a byte to a hex string
    /// @dev Internal helper function
    /// @param b The byte to convert
    /// @return The byte as a hex string
    function _toHexString(uint8 b) internal pure returns (bytes memory) {
        if (b < 16) {
            return abi.encodePacked((b < 10) ? bytes1(uint8(48 + b)) : bytes1(uint8(87 + b)));
        }
        return abi.encodePacked(
            (b / 16 < 10) ? bytes1(uint8(48 + b / 16)) : bytes1(uint8(87 + b / 16)),
            (b % 16 < 10) ? bytes1(uint8(48 + b % 16)) : bytes1(uint8(87 + b % 16))
        );
    }

    /// @notice Converts a string to an address
    /// @dev Parses a hex string (e.g., "0x123...") to an address
    /// @param str The string to convert
    /// @return The address
    function toAddress(string memory str) internal pure returns (address) {
        require(
            bytes(str).length == 42 &&
                bytes(str)[0] == '0' &&
                bytes(str)[1] == 'x',
            "LibAddress: invalid address string"
        );

        address addr;
        assembly {
            addr := mload(add(str, 2))
        }
        return addr;
    }

    // ====================== ADDRESS VALIDATION ======================

    /// @notice Validates an address checksum
    /// @dev Checks if the address has a valid EIP-55 checksum
    /// @param addr The address to validate
    /// @return Whether the address has a valid checksum
    function isValidChecksum(address addr) internal pure returns (bool) {
        bytes32 temp = bytes32(uint256(uint160(addr)));
        bytes memory addressBytes = abi.encodePacked(
            _toHexString(uint8(uint256(temp >> 120))),
            _toHexString(uint8(uint256(temp >> 112))),
            _toHexString(uint8(uint256(temp >> 104))),
            _toHexString(uint8(uint256(temp >> 96))),
            _toHexString(uint8(uint256(temp >> 88))),
            _toHexString(uint8(uint256(temp >> 80))),
            _toHexString(uint8(uint256(temp >> 72))),
            _toHexString(uint8(uint256(temp >> 64))),
            _toHexString(uint8(uint256(temp >> 56))),
            _toHexString(uint8(uint256(temp >> 48))),
            _toHexString(uint8(uint256(temp >> 40))),
            _toHexString(uint8(uint256(temp >> 32))),
            _toHexString(uint8(uint256(temp >> 24))),
            _toHexString(uint8(uint256(temp >> 16))),
            _toHexString(uint8(uint256(temp >> 8))),
            _toHexString(uint8(uint256(temp)))
        );

        bytes32 hash = keccak256(addressBytes);
        for (uint256 i = 0; i < 20; i++) {
            bytes1 char = addressBytes[i + 2];
            if (char >= 'A' && char <= 'F') {
                // Uppercase letter
                if ((uint256(hash >> (196 - i * 4)) & 0x0F) >= 8) {
                    return false;
                }
            } else if (char >= 'a' && char <= 'f') {
                // Lowercase letter
                if ((uint256(hash >> (196 - i * 4)) & 0x0F) < 8) {
                    return false;
                }
            }
        }
        return true;
    }

    /// @notice Converts an address to a checksum address
    /// @dev Returns the address with EIP-55 checksum
    /// @param addr The address to convert
    /// @return The checksum address as a string
    function toChecksumAddress(
        address addr
    ) internal pure returns (string memory) {
        bytes32 temp = bytes32(uint256(uint160(addr)));
        bytes memory addressBytes = abi.encodePacked(
            "0x",
            _toHexString(uint8(uint256(temp >> 120))),
            _toHexString(uint8(uint256(temp >> 112))),
            _toHexString(uint8(uint256(temp >> 104))),
            _toHexString(uint8(uint256(temp >> 96))),
            _toHexString(uint8(uint256(temp >> 88))),
            _toHexString(uint8(uint256(temp >> 80))),
            _toHexString(uint8(uint256(temp >> 72))),
            _toHexString(uint8(uint256(temp >> 64))),
            _toHexString(uint8(uint256(temp >> 56))),
            _toHexString(uint8(uint256(temp >> 48))),
            _toHexString(uint8(uint256(temp >> 40))),
            _toHexString(uint8(uint256(temp >> 32))),
            _toHexString(uint8(uint256(temp >> 24))),
            _toHexString(uint8(uint256(temp >> 16))),
            _toHexString(uint8(uint256(temp >> 8))),
            _toHexString(uint8(uint256(temp)))
        );

        bytes32 hash = keccak256(addressBytes);
        bytes memory checksumAddress = new bytes(42);
        checksumAddress[0] = '0';
        checksumAddress[1] = 'x';

        for (uint256 i = 0; i < 20; i++) {
            bytes1 char = addressBytes[i + 2];
            uint8 nibble = uint8(uint256(hash >> (196 - i * 4)) & 0x0F);

            if (char >= '0' && char <= '9') {
                checksumAddress[i + 2] = char;
            } else if (char >= 'A' && char <= 'F') {
                checksumAddress[i + 2] = (nibble >= 8) ? char : toLowerCase(char);
            } else if (char >= 'a' && char <= 'f') {
                checksumAddress[i + 2] = (nibble < 8) ? toUpperCase(char) : char;
            }
        }

        return string(checksumAddress);
    }

    /// @notice Converts a character to lowercase
    /// @dev Internal helper function
    /// @param char The character to convert
    /// @return The lowercase character
    function toLowerCase(bytes1 char) internal pure returns (bytes1) {
        if (char >= 'A' && char <= 'Z') {
            return bytes1(uint8(char) + 32);
        }
        return char;
    }

    /// @notice Converts a character to uppercase
    /// @dev Internal helper function
    /// @param char The character to convert
    /// @return The uppercase character
    function toUpperCase(bytes1 char) internal pure returns (bytes1) {
        if (char >= 'a' && char <= 'z') {
            return bytes1(uint8(char) - 32);
        }
        return char;
    }
}
