import { PublicKey } from '@solana/web3.js';

async function verifyPDA(programId, seed) {
    const programPublicKey = new PublicKey(programId); // Your program ID as PublicKey
    const [pda, bump] = await PublicKey.findProgramAddressSync(
        [Buffer.from(seed)],  // Seed used to generate the PDA
        programPublicKey       // Program ID (your LayerZero program)
    );
    
    console.log(`Derived PDA: ${pda.toBase58()}`);
    console.log(`Bump: ${bump}`);
}

verifyPDA('2XrYqmhBMPJgDsb4SVbjV1PnJBprurd5bzRCkHwiFCJB', 'MessageLib');
