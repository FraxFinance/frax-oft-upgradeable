import { PublicKey } from '@solana/web3.js';
import {} from "@layerzerolabs/lz-solana-sdk-v2"
async function verifyPDA(programId, seed) {
    const programPublicKey = new PublicKey(programId); // Your program ID as PublicKey
    const [pda, bump] = await PublicKey.findProgramAddressSync(
        [Buffer.from(seed)],  // Seed used to generate the PDA
        programPublicKey       // Program ID (your LayerZero program)
    );
    
    console.log(`Derived PDA: ${pda.toBase58()}`);
    console.log(`Bump: ${bump}`);
}

// verifyPDA('2XrYqmhBMPJgDsb4SVbjV1PnJBprurd5bzRCkHwiFCJB', 'MessageLib');
verifyPDA('FFozEKoFQ1CZD6Kn7bpwAxaWhK1jEA76pjucvBBHf9ZH', 'OFT');
