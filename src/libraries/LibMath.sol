// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

/// @title LibMath
/// @notice Library for mathematical operations
/// @dev Provides safe math operations, percentage calculations, and other math utilities
/// @author LithosProtocol Team
library LibMath {
    // ====================== CONSTANTS ======================

    /// @dev Maximum value for a uint256 (2^256 - 1)
    uint256 internal constant MAX_UINT256 = 2**256 - 1;

    /// @dev Maximum value for a uint128 (2^128 - 1)
    uint128 internal constant MAX_UINT128 = 2**128 - 1;

    /// @dev Maximum value for a uint64 (2^64 - 1)
    uint64 internal constant MAX_UINT64 = 2**64 - 1;

    /// @dev Maximum value for a uint32 (2^32 - 1)
    uint32 internal constant MAX_UINT32 = 2**32 - 1;

    /// @dev Maximum value for a uint16 (2^16 - 1)
    uint16 internal constant MAX_UINT16 = 2**16 - 1;

    /// @dev Maximum value for a uint8 (2^8 - 1)
    uint8 internal constant MAX_UINT8 = 2**8 - 1;

    // ====================== SAFE MATH ======================

    /// @notice Adds two uint256 numbers with overflow check
    /// @param a First number
    /// @param b Second number
    /// @return Sum of a and b
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        require(a <= MAX_UINT256 - b, "LibMath: addition overflow");
        return a + b;
    }

    /// @notice Subtracts two uint256 numbers with underflow check
    /// @param a First number
    /// @param b Second number
    /// @return Difference of a and b
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "LibMath: subtraction underflow");
        return a - b;
    }

    /// @notice Multiplies two uint256 numbers with overflow check
    /// @param a First number
    /// @param b Second number
    /// @return Product of a and b
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) {
            return 0;
        }
        require(a <= MAX_UINT256 / b, "LibMath: multiplication overflow");
        return a * b;
    }

    /// @notice Divides two uint256 numbers with division by zero check
    /// @param a Numerator
    /// @param b Denominator
    /// @return Quotient of a divided by b
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "LibMath: division by zero");
        return a / b;
    }

    /// @notice Calculates a modulo b with division by zero check
    /// @param a Numerator
    /// @param b Denominator
    /// @return Remainder of a divided by b
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "LibMath: modulo by zero");
        return a % b;
    }

    // ====================== PERCENTAGE CALCULATIONS ======================

    /// @notice Calculates a percentage of a value
    /// @dev Uses 10000 as the base for percentage (e.g., 50% = 5000, 100% = 10000)
    /// @param value The base value
    /// @param percentage The percentage (1-10000 for 0.01%-100%)
    /// @return The percentage of the value
    function percentageOf(
        uint256 value,
        uint256 percentage
    ) internal pure returns (uint256) {
        return (value * percentage) / 10000;
    }

    /// @notice Calculates a percentage of a value with rounding
    /// @dev Uses 10000 as the base for percentage (e.g., 50% = 5000, 100% = 10000)
    /// @param value The base value
    /// @param percentage The percentage (1-10000 for 0.01%-100%)
    /// @return The percentage of the value with rounding
    function percentageOfRounded(
        uint256 value,
        uint256 percentage
    ) internal pure returns (uint256) {
        uint256 result = (value * percentage) / 10000;
        uint256 remainder = (value * percentage) % 10000;
        if (remainder >= 5000) {
            result += 1;
        }
        return result;
    }

    /// @notice Calculates the percentage that one value is of another
    /// @dev Uses 10000 as the base for percentage
    /// @param part The part value
    /// @param whole The whole value
    /// @return The percentage (1-10000 for 0.01%-100%)
    function percentage(
        uint256 part,
        uint256 whole
    ) internal pure returns (uint256) {
        require(whole != 0, "LibMath: percentage of zero");
        return (part * 10000) / whole;
    }

    /// @notice Adds a percentage to a value
    /// @dev Uses 10000 as the base for percentage
    /// @param value The base value
    /// @param percentage The percentage to add (1-10000 for 0.01%-100%)
    /// @return The value with the percentage added
    function addPercentage(
        uint256 value,
        uint256 percentage
    ) internal pure returns (uint256) {
        return value + percentageOf(value, percentage);
    }

    /// @notice Subtracts a percentage from a value
    /// @dev Uses 10000 as the base for percentage
    /// @param value The base value
    /// @param percentage The percentage to subtract (1-10000 for 0.01%-100%)
    /// @return The value with the percentage subtracted
    function subPercentage(
        uint256 value,
        uint256 percentage
    ) internal pure returns (uint256) {
        require(percentage < 10000, "LibMath: percentage cannot be 100% or more");
        return value - percentageOf(value, percentage);
    }

    // ====================== MIN/MAX ======================

    /// @notice Returns the minimum of two values
    /// @param a First value
    /// @param b Second value
    /// @return The minimum of a and b
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /// @notice Returns the maximum of two values
    /// @param a First value
    /// @param b Second value
    /// @return The maximum of a and b
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /// @notice Returns the minimum of three values
    /// @param a First value
    /// @param b Second value
    /// @param c Third value
    /// @return The minimum of a, b, and c
    function min3(
        uint256 a,
        uint256 b,
        uint256 c
    ) internal pure returns (uint256) {
        return min(min(a, b), c);
    }

    /// @notice Returns the maximum of three values
    /// @param a First value
    /// @param b Second value
    /// @param c Third value
    /// @return The maximum of a, b, and c
    function max3(
        uint256 a,
        uint256 b,
        uint256 c
    ) internal pure returns (uint256) {
        return max(max(a, b), c);
    }

    // ====================== RANGE CHECKS ======================

    /// @notice Checks if a value is within a range (inclusive)
    /// @param value The value to check
    /// @param min The minimum value (inclusive)
    /// @param max The maximum value (inclusive)
    /// @return Whether the value is within the range
    function inRange(
        uint256 value,
        uint256 min,
        uint256 max
    ) internal pure returns (bool) {
        return value >= min && value <= max;
    }

    /// @notice Checks if a value is within a range (exclusive)
    /// @param value The value to check
    /// @param min The minimum value (exclusive)
    /// @param max The maximum value (exclusive)
    /// @return Whether the value is within the range
    function inRangeExclusive(
        uint256 value,
        uint256 min,
        uint256 max
    ) internal pure returns (bool) {
        return value > min && value < max;
    }

    /// @notice Clamps a value to be within a range
    /// @param value The value to clamp
    /// @param min The minimum value
    /// @param max The maximum value
    /// @return The clamped value
    function clamp(
        uint256 value,
        uint256 min,
        uint256 max
    ) internal pure returns (uint256) {
        if (value < min) {
            return min;
        }
        if (value > max) {
            return max;
        }
        return value;
    }

    // ====================== POWER OPERATIONS ======================

    /// @notice Calculates x raised to the power of y
    /// @dev Uses exponentiation by squaring for efficiency
    /// @param x The base
    /// @param y The exponent
    /// @return x^y
    function pow(uint256 x, uint256 y) internal pure returns (uint256) {
        if (y == 0) {
            return 1;
        }
        if (y == 1) {
            return x;
        }

        uint256 result = 1;
        uint256 current = x;
        uint256 exponent = y;

        while (exponent > 0) {
            if (exponent % 2 == 1) {
                result = mul(result, current);
            }
            current = mul(current, current);
            exponent = exponent / 2;
        }

        return result;
    }

    /// @notice Calculates the square of a number
    /// @param x The number
    /// @return x^2
    function square(uint256 x) internal pure returns (uint256) {
        return mul(x, x);
    }

    /// @notice Calculates the cube of a number
    /// @param x The number
    /// @return x^3
    function cube(uint256 x) internal pure returns (uint256) {
        return mul(mul(x, x), x);
    }

    /// @notice Calculates the square root of a number (rounded down)
    /// @dev Uses Newton's method for approximation
    /// @param x The number
    /// @return The square root of x (rounded down)
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) {
            return 0;
        }

        uint256 result = x;
        uint256 prevResult;

        do {
            prevResult = result;
            result = (result + x / result) / 2;
        } while (result < prevResult);

        return result;
    }

    /// @notice Calculates the cube root of a number (rounded down)
    /// @dev Uses Newton's method for approximation
    /// @param x The number
    /// @return The cube root of x (rounded down)
    function cbrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) {
            return 0;
        }

        uint256 result = x;
        uint256 prevResult;

        do {
            prevResult = result;
            result = ((2 * result) + x / (result * result)) / 3;
        } while (result < prevResult);

        return result;
    }

    // ====================== LOGARITHM OPERATIONS ======================

    /// @notice Calculates the natural logarithm of a number (approximate)
    /// @dev Uses Taylor series approximation
    /// @param x The number (must be > 0)
    /// @param precision The number of iterations for approximation
    /// @return The natural logarithm of x (scaled by 1e18)
    function ln(uint256 x, uint256 precision) internal pure returns (uint256) {
        require(x > 0, "LibMath: logarithm of zero or negative");

        if (x == 1) {
            return 0;
        }

        // Scale x to fixed point (1e18)
        uint256 scaledX = x * 1e18;

        // Use the approximation: ln(1 + y) ≈ y - y^2/2 + y^3/3 - ...
        // where y = (x - 1) / (x + 1)
        uint256 y = ((scaledX - 1e18) * 1e18) / (scaledX + 1e18);

        uint256 result = 0;
        uint256 term = y;
        uint256 sign = 1;

        for (uint256 i = 1; i <= precision; i++) {
            result = add(result, sign * term / i);
            term = mul(term, y);
            sign = sign == 1 ? 2 : 1; // Alternate sign
        }

        return result;
    }

    /// @notice Calculates the base-10 logarithm of a number (approximate)
    /// @dev Uses natural logarithm and change of base formula
    /// @param x The number (must be > 0)
    /// @param precision The number of iterations for approximation
    /// @return The base-10 logarithm of x (scaled by 1e18)
    function log10(uint256 x, uint256 precision) internal pure returns (uint256) {
        // ln(x) / ln(10)
        // ln(10) ≈ 2.302585092994046e18 (scaled by 1e18)
        uint256 ln10 = 2302585092994045990; // ln(10) * 1e18 (approx)
        return div(ln(x, precision), ln10);
    }

    // ====================== EXPONENTIAL OPERATIONS ======================

    /// @notice Calculates e^x (approximate)
    /// @dev Uses Taylor series approximation
    /// @param x The exponent (scaled by 1e18)
    /// @param precision The number of iterations for approximation
    /// @return e^x (scaled by 1e18)
    function exp(uint256 x, uint256 precision) internal pure returns (uint256) {
        uint256 result = 1e18;
        uint256 term = 1e18;

        for (uint256 i = 1; i <= precision; i++) {
            term = div(mul(term, x), i);
            result = add(result, term);
        }

        return result;
    }

    // ====================== STATISTICAL OPERATIONS ======================

    /// @notice Calculates the average of an array of numbers
    /// @param values The array of numbers
    /// @return The average of the numbers
    function average(uint256[] memory values) internal pure returns (uint256) {
        require(values.length > 0, "LibMath: cannot average empty array");

        uint256 sum = 0;
        for (uint256 i = 0; i < values.length; i++) {
            sum = add(sum, values[i]);
        }

        return div(sum, values.length);
    }

    /// @notice Calculates the median of an array of numbers
    /// @dev The array must be sorted in ascending order
    /// @param values The sorted array of numbers
    /// @return The median of the numbers
    function median(uint256[] memory values) internal pure returns (uint256) {
        require(values.length > 0, "LibMath: cannot find median of empty array");

        uint256 length = values.length;
        if (length % 2 == 1) {
            // Odd length: return middle element
            return values[length / 2];
        } else {
            // Even length: return average of two middle elements
            uint256 mid1 = values[length / 2 - 1];
            uint256 mid2 = values[length / 2];
            return div(add(mid1, mid2), 2);
        }
    }

    /// @notice Calculates the weighted average of an array of numbers
    /// @param values The array of numbers
    /// @param weights The array of weights (must be same length as values)
    /// @return The weighted average of the numbers
    function weightedAverage(
        uint256[] memory values,
        uint256[] memory weights
    ) internal pure returns (uint256) {
        require(
            values.length == weights.length,
            "LibMath: values and weights must have same length"
        );
        require(values.length > 0, "LibMath: cannot calculate weighted average of empty array");

        uint256 weightedSum = 0;
        uint256 totalWeight = 0;

        for (uint256 i = 0; i < values.length; i++) {
            weightedSum = add(weightedSum, mul(values[i], weights[i]));
            totalWeight = add(totalWeight, weights[i]);
        }

        return div(weightedSum, totalWeight);
    }

    // ====================== INTERPOLATION ======================

    /// @notice Linear interpolation between two points
    /// @param x0 First x value
    /// @param y0 First y value
    /// @param x1 Second x value
    /// @param y1 Second y value
    /// @param x The x value to interpolate at
    /// @return The interpolated y value
    function linearInterpolate(
        uint256 x0,
        uint256 y0,
        uint256 x1,
        uint256 y1,
        uint256 x
    ) internal pure returns (uint256) {
        require(x1 != x0, "LibMath: x1 cannot equal x0");
        require(inRange(x, min(x0, x1), max(x0, x1)), "LibMath: x must be between x0 and x1");

        // y = y0 + (y1 - y0) * (x - x0) / (x1 - x0)
        uint256 slope = div(sub(y1, y0), sub(x1, x0));
        return add(y0, mul(slope, sub(x, x0)));
    }

    /// @notice Inverse linear interpolation (find x given y)
    /// @param x0 First x value
    /// @param y0 First y value
    /// @param x1 Second x value
    /// @param y1 Second y value
    /// @param y The y value to find x for
    /// @return The interpolated x value
    function inverseLinearInterpolate(
        uint256 x0,
        uint256 y0,
        uint256 x1,
        uint256 y1,
        uint256 y
    ) internal pure returns (uint256) {
        require(y1 != y0, "LibMath: y1 cannot equal y0");
        require(inRange(y, min(y0, y1), max(y0, y1)), "LibMath: y must be between y0 and y1");

        // x = x0 + (x1 - x0) * (y - y0) / (y1 - y0)
        uint256 invSlope = div(sub(x1, x0), sub(y1, y0));
        return add(x0, mul(invSlope, sub(y, y0)));
    }

    // ====================== FINANCIAL OPERATIONS ======================

    /// @notice Calculates compound interest
    /// @param principal The principal amount
    /// @param rate The interest rate (1-10000 for 0.01%-100%)
    /// @param periods The number of compounding periods
    /// @return The final amount after compound interest
    function compoundInterest(
        uint256 principal,
        uint256 rate,
        uint256 periods
    ) internal pure returns (uint256) {
        uint256 factor = percentageOf(1e18, rate) + 1e18;
        return mul(principal, pow(factor, periods)) / 1e18;
    }

    /// @notice Calculates simple interest
    /// @param principal The principal amount
    /// @param rate The interest rate (1-10000 for 0.01%-100%)
    /// @param periods The number of periods
    /// @return The final amount after simple interest
    function simpleInterest(
        uint256 principal,
        uint256 rate,
        uint256 periods
    ) internal pure returns (uint256) {
        uint256 interest = mul(principal, mul(rate, periods)) / 10000;
        return add(principal, interest);
    }

    /// @notice Calculates the future value of an annuity
    /// @param payment The periodic payment amount
    /// @param rate The interest rate per period (1-10000 for 0.01%-100%)
    /// @param periods The number of periods
    /// @return The future value of the annuity
    function futureValueAnnuity(
        uint256 payment,
        uint256 rate,
        uint256 periods
    ) internal pure returns (uint256) {
        uint256 factor = percentageOf(1e18, rate) + 1e18;
        uint256 numerator = mul(pow(factor, periods), sub(factor, 1e18));
        uint256 denominator = sub(factor, 1e18);
        return mul(payment, div(numerator, denominator)) / 1e18;
    }

    /// @notice Calculates the present value of an annuity
    /// @param payment The periodic payment amount
    /// @param rate The interest rate per period (1-10000 for 0.01%-100%)
    /// @param periods The number of periods
    /// @return The present value of the annuity
    function presentValueAnnuity(
        uint256 payment,
        uint256 rate,
        uint256 periods
    ) internal pure returns (uint256) {
        uint256 factor = percentageOf(1e18, rate) + 1e18;
        uint256 denominator = sub(factor, 1e18);
        // (1 + r)^-periods in 1e18 fixed point: pow() cannot express
        // negative exponents in uint256, so divide by (1 + r) repeatedly
        // instead of raising to a negative power.
        uint256 invFactor = 1e18;
        for (uint256 i = 0; i < periods; i++) {
            invFactor = div(mul(invFactor, 1e18), factor);
        }
        uint256 numerator = sub(1e18, invFactor);
        // Annuity factor (1 - (1 + r)^-periods) / r, in 1e18 fixed point
        uint256 annuityFactor = div(mul(numerator, 1e18), denominator);
        return mul(payment, annuityFactor) / 1e18;
    }

    // ====================== BIT OPERATIONS ======================

    /// @notice Checks if a bit is set at a specific position
    /// @param value The value to check
    /// @param position The bit position (0-indexed from the right)
    /// @return Whether the bit is set
    function isBitSet(uint256 value, uint256 position) internal pure returns (bool) {
        return (value & (1 << position)) != 0;
    }

    /// @notice Sets a bit at a specific position
    /// @param value The value to modify
    /// @param position The bit position (0-indexed from the right)
    /// @return The value with the bit set
    function setBit(uint256 value, uint256 position) internal pure returns (uint256) {
        return value | (1 << position);
    }

    /// @notice Clears a bit at a specific position
    /// @param value The value to modify
    /// @param position The bit position (0-indexed from the right)
    /// @return The value with the bit cleared
    function clearBit(uint256 value, uint256 position) internal pure returns (uint256) {
        return value & ~(1 << position);
    }

    /// @notice Toggles a bit at a specific position
    /// @param value The value to modify
    /// @param position The bit position (0-indexed from the right)
    /// @return The value with the bit toggled
    function toggleBit(uint256 value, uint256 position) internal pure returns (uint256) {
        return value ^ (1 << position);
    }

    /// @notice Counts the number of set bits (population count)
    /// @param value The value to count
    /// @return The number of set bits
    function countBits(uint256 value) internal pure returns (uint256) {
        uint256 count = 0;
        while (value != 0) {
            count = add(count, 1);
            value = value & (value - 1); // Clear the least significant set bit
        }
        return count;
    }

    /// @notice Finds the position of the most significant set bit
    /// @param value The value to check
    /// @return The position of the most significant set bit (0-indexed from the right)
    function findMostSignificantBit(uint256 value) internal pure returns (uint256) {
        require(value != 0, "LibMath: value cannot be zero");

        uint256 position = 255;
        while (position > 0 && (value & (1 << position)) == 0) {
            position = sub(position, 1);
        }
        return position;
    }

    /// @notice Finds the position of the least significant set bit
    /// @param value The value to check
    /// @return The position of the least significant set bit (0-indexed from the right)
    function findLeastSignificantBit(uint256 value) internal pure returns (uint256) {
        require(value != 0, "LibMath: value cannot be zero");

        uint256 position = 0;
        while ((value & (1 << position)) == 0) {
            position = add(position, 1);
        }
        return position;
    }

    // ====================== BYTE OPERATIONS ======================

    /// @notice Extracts a byte from a value at a specific position
    /// @param value The value to extract from
    /// @param position The byte position (0-indexed from the right)
    /// @return The byte at the specified position
    function extractByte(uint256 value, uint256 position) internal pure returns (uint8) {
        return uint8((value >> (position * 8)) & 0xff);
    }

    /// @notice Sets a byte in a value at a specific position
    /// @param value The value to modify
    /// @param position The byte position (0-indexed from the right)
    /// @param byteValue The byte value to set
    /// @return The value with the byte set
    function setByte(
        uint256 value,
        uint256 position,
        uint8 byteValue
    ) internal pure returns (uint256) {
        uint256 mask = ~(0xff << (position * 8));
        return (value & mask) | (uint256(byteValue) << (position * 8));
    }

    /// @notice Extracts a range of bytes from a value
    /// @param value The value to extract from
    /// @param startPosition The starting byte position (0-indexed from the right)
    /// @param length The number of bytes to extract
    /// @return The extracted bytes as a uint256
    function extractBytes(
        uint256 value,
        uint256 startPosition,
        uint256 length
    ) internal pure returns (uint256) {
        require(length <= 32, "LibMath: cannot extract more than 32 bytes");
        require(
            startPosition + length <= 32,
            "LibMath: bytes range exceeds 32 bytes"
        );

        uint256 mask = (1 << (length * 8)) - 1;
        return (value >> (startPosition * 8)) & mask;
    }

    // ====================== ADDRESS OPERATIONS ======================

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

    /// @notice Checks if an address is not a contract (EOA)
    /// @param addr The address to check
    /// @return Whether the address is an EOA
    function isEOA(address addr) internal view returns (bool) {
        return !isContract(addr);
    }

    // ====================== TIME OPERATIONS ======================

    /// @notice Converts seconds to minutes
    /// @param secondsValue The number of seconds
    /// @return The number of minutes
    function secondsToMinutes(uint256 secondsValue) internal pure returns (uint256) {
        return div(secondsValue, 60);
    }

    /// @notice Converts minutes to seconds
    /// @param minutesValue The number of minutes
    /// @return The number of seconds
    function minutesToSeconds(uint256 minutesValue) internal pure returns (uint256) {
        return mul(minutesValue, 60);
    }

    /// @notice Converts seconds to hours
    /// @param secondsValue The number of seconds
    /// @return The number of hours
    function secondsToHours(uint256 secondsValue) internal pure returns (uint256) {
        return div(secondsValue, 3600);
    }

    /// @notice Converts hours to seconds
    /// @param hoursValue The number of hours
    /// @return The number of seconds
    function hoursToSeconds(uint256 hoursValue) internal pure returns (uint256) {
        return mul(hoursValue, 3600);
    }

    /// @notice Converts seconds to days
    /// @param secondsValue The number of seconds
    /// @return The number of days
    function secondsToDays(uint256 secondsValue) internal pure returns (uint256) {
        return div(secondsValue, 86400);
    }

    /// @notice Converts days to seconds
    /// @param daysValue The number of days
    /// @return The number of seconds
    function daysToSeconds(uint256 daysValue) internal pure returns (uint256) {
        return mul(daysValue, 86400);
    }

    /// @notice Converts seconds to weeks
    /// @param secondsValue The number of seconds
    /// @return The number of weeks
    function secondsToWeeks(uint256 secondsValue) internal pure returns (uint256) {
        return div(secondsValue, 604800);
    }

    /// @notice Converts weeks to seconds
    /// @param weeksValue The number of weeks
    /// @return The number of seconds
    function weeksToSeconds(uint256 weeksValue) internal pure returns (uint256) {
        return mul(weeksValue, 604800);
    }

    /// @notice Converts seconds to years (365 days)
    /// @param secondsValue The number of seconds
    /// @return The number of years
    function secondsToYears(uint256 secondsValue) internal pure returns (uint256) {
        return div(secondsValue, 31536000);
    }

    /// @notice Converts years to seconds (365 days)
    /// @param yearsValue The number of years
    /// @return The number of seconds
    function yearsToSeconds(uint256 yearsValue) internal pure returns (uint256) {
        return mul(yearsValue, 31536000);
    }

    /// @notice Checks if a timestamp is in the past
    /// @param timestamp The timestamp to check
    /// @return Whether the timestamp is in the past
    function isPast(uint256 timestamp) internal view returns (bool) {
        return block.timestamp > timestamp;
    }

    /// @notice Checks if a timestamp is in the future
    /// @param timestamp The timestamp to check
    /// @return Whether the timestamp is in the future
    function isFuture(uint256 timestamp) internal view returns (bool) {
        return block.timestamp < timestamp;
    }

    /// @notice Checks if a timestamp is now (within a tolerance)
    /// @param timestamp The timestamp to check
    /// @param tolerance The tolerance in seconds
    /// @return Whether the timestamp is now (within tolerance)
    function isNow(
        uint256 timestamp,
        uint256 tolerance
    ) internal view returns (bool) {
        return inRange(
            block.timestamp,
            sub(timestamp, tolerance),
            add(timestamp, tolerance)
        );
    }

    /// @notice Gets the time remaining until a timestamp
    /// @param timestamp The future timestamp
    /// @return The time remaining in seconds
    function timeRemaining(uint256 timestamp) internal view returns (uint256) {
        require(
            block.timestamp <= timestamp,
            "LibMath: timestamp must be in the future"
        );
        return sub(timestamp, block.timestamp);
    }

    /// @notice Gets the time elapsed since a timestamp
    /// @param timestamp The past timestamp
    /// @return The time elapsed in seconds
    function timeElapsed(uint256 timestamp) internal view returns (uint256) {
        require(
            block.timestamp >= timestamp,
            "LibMath: timestamp must be in the past"
        );
        return sub(block.timestamp, timestamp);
    }

    // ====================== ETH UNIT CONVERSIONS ======================

    /// @notice Converts wei to ether
    /// @param weiValue The amount in wei
    /// @return The amount in ether (as a uint256 with 18 decimals)
    function weiToEther(uint256 weiValue) internal pure returns (uint256) {
        return div(weiValue, 1e18);
    }

    /// @notice Converts ether to wei
    /// @param etherValue The amount in ether (as a uint256 with 18 decimals)
    /// @return The amount in wei
    function etherToWei(uint256 etherValue) internal pure returns (uint256) {
        return mul(etherValue, 1e18);
    }

    /// @notice Converts wei to gwei
    /// @param weiValue The amount in wei
    /// @return The amount in gwei
    function weiToGwei(uint256 weiValue) internal pure returns (uint256) {
        return div(weiValue, 1e9);
    }

    /// @notice Converts gwei to wei
    /// @param gweiValue The amount in gwei
    /// @return The amount in wei
    function gweiToWei(uint256 gweiValue) internal pure returns (uint256) {
        return mul(gweiValue, 1e9);
    }

    // ====================== TOKEN UNIT CONVERSIONS ======================

    /// @notice Converts tokens to wei (for tokens with 18 decimals)
    /// @param tokens The amount in tokens (as a uint256 with decimals)
    /// @return The amount in wei
    function tokensToWei(uint256 tokens, uint8 decimals) internal pure returns (uint256) {
        uint256 multiplier = 10**decimals;
        return mul(tokens, multiplier);
    }

    /// @notice Converts wei to tokens (for tokens with 18 decimals)
    /// @param weiValue The amount in wei
    /// @param decimals The number of decimals
    /// @return The amount in tokens (as a uint256 with decimals)
    function weiToTokens(uint256 weiValue, uint8 decimals) internal pure returns (uint256) {
        uint256 multiplier = 10**decimals;
        return div(weiValue, multiplier);
    }
}
