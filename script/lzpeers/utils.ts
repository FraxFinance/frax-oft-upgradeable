
// Convert wei (raw token amount) to decimal format by dividing by 10^18
export function formatTokenAmount(amount: bigint | string | number): string {
    if (typeof amount === 'string' || typeof amount === 'number') {
        // Handle already decimal values (like from Solana)
        return amount.toString()
    }

    // Convert BigInt wei to decimal by dividing by 10^18
    const divisor = 10n ** 18n
    const wholePart = amount / divisor
    const fractionalPart = amount % divisor

    // Convert to decimal string with up to 18 decimal places
    const fractionalStr = fractionalPart.toString().padStart(18, '0')
    const trimmedFractional = fractionalStr.replace(/0+$/, '') // Remove trailing zeros

    if (trimmedFractional === '') {
        return wholePart.toString()
    } else {
        return `${wholePart}.${trimmedFractional}`
    }
}