'use strict';

const crypto = require('crypto');
const { v4: uuidv4 } = require('uuid');
const {
  Connection,
  PublicKey,
  SystemProgram,
  Transaction,
  TransactionInstruction,
} = require('@solana/web3.js');
const { WAGER } = require('./constants');
const { computePayouts } = require('./wagerRules');

const DEFAULT_RPC_URL = process.env.SOLANA_RPC_URL || 'https://api.devnet.solana.com';
const DEFAULT_PROGRAM_ID =
  process.env.SOLANA_PROGRAM_ID || 'Bcdp7uboxycoo6ApoMvnRDUoxKdVH4VvDPn1HLY7VYUR';
const DEFAULT_CUSTODY_MODE = process.env.WAGER_CUSTODY_MODE || 'mock';

const WAGER_ESCROW_ACCOUNT_SIZE = 8 + 32 + 8 + 8 + 1 + 32 + 8 + 1;

function u64Le(value) {
  const b = Buffer.alloc(8);
  b.writeBigUInt64LE(BigInt(value));
  return b;
}

function anchorDiscriminator(methodName) {
  return crypto
    .createHash('sha256')
    .update(`global:${methodName}`)
    .digest()
    .subarray(0, 8);
}

function parseEscrowAccount(data) {
  if (!Buffer.isBuffer(data) || data.length < WAGER_ESCROW_ACCOUNT_SIZE) return null;
  return {
    player: new PublicKey(data.subarray(8, 40)).toBase58(),
    intentId: data.readBigUInt64LE(40),
    amountLamports: data.readBigUInt64LE(48),
    status: data.readUInt8(56),
    matchEscrow: new PublicKey(data.subarray(57, 89)).toBase58(),
    createdAt: data.readBigInt64LE(89),
    bump: data.readUInt8(97),
  };
}

/**
 * Custody gateway for wager escrow validation/refund/settlement.
 *
 * Modes:
 * - mock (default): deterministic local behavior
 * - onchain: prepares and verifies real `init_wager_escrow` transactions on Solana
 */
class WagerCustodyService {
  constructor(opts = {}) {
    this.mode = opts.mode || DEFAULT_CUSTODY_MODE;
    this.rpcUrl = opts.rpcUrl || DEFAULT_RPC_URL;
    this.programId = new PublicKey(opts.programId || DEFAULT_PROGRAM_ID);

    if (this.mode === 'onchain') {
      this.connection = new Connection(this.rpcUrl, 'confirmed');
      this.wagerConfigPda = PublicKey.findProgramAddressSync(
        [Buffer.from('wager_config')],
        this.programId,
      )[0];
    }
  }

  async prepareEscrowTransaction({ wallet, lamports, intentId }) {
    if (this.mode !== 'onchain') {
      throw new Error('prepareEscrowTransaction is only available in onchain mode');
    }
    if (!wallet || typeof wallet !== 'string') {
      throw new Error('wallet is required');
    }
    if (!Number.isSafeInteger(lamports) || lamports <= 0) {
      throw new Error('lamports must be a positive integer');
    }

    const programInfo = await this.connection.getAccountInfo(this.programId, 'confirmed');
    if (!programInfo) {
      throw new Error(`Program ${this.programId.toBase58()} is not deployed on ${this.rpcUrl}`);
    }
    const configInfo = await this.connection.getAccountInfo(this.wagerConfigPda, 'confirmed');
    if (!configInfo) {
      throw new Error(
        `Wager config PDA ${this.wagerConfigPda.toBase58()} is not initialized for program ${this.programId.toBase58()}`,
      );
    }

    const playerPk = new PublicKey(wallet);
    const resolvedIntent =
      intentId != null ? BigInt(intentId) : BigInt(Date.now() * 1000 + Math.floor(Math.random() * 1000));

    const [wagerEscrowPda] = PublicKey.findProgramAddressSync(
      [Buffer.from('wager_escrow'), playerPk.toBuffer(), u64Le(resolvedIntent)],
      this.programId,
    );

    const ixData = Buffer.concat([
      anchorDiscriminator('init_wager_escrow'),
      u64Le(resolvedIntent),
      u64Le(lamports),
    ]);

    const ix = new TransactionInstruction({
      programId: this.programId,
      keys: [
        { pubkey: this.wagerConfigPda, isSigner: false, isWritable: false },
        { pubkey: wagerEscrowPda, isSigner: false, isWritable: true },
        { pubkey: playerPk, isSigner: true, isWritable: true },
        { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
      ],
      data: ixData,
    });

    const latest = await this.connection.getLatestBlockhash('confirmed');
    const tx = new Transaction({
      feePayer: playerPk,
      blockhash: latest.blockhash,
      lastValidBlockHeight: latest.lastValidBlockHeight,
    });
    tx.add(ix);

    const txBase64 = tx
      .serialize({ requireAllSignatures: false, verifySignatures: false })
      .toString('base64');

    return {
      intentId: resolvedIntent.toString(),
      wagerEscrowPda: wagerEscrowPda.toBase58(),
      txBase64,
      blockhash: latest.blockhash,
      lastValidBlockHeight: latest.lastValidBlockHeight,
      programId: this.programId.toBase58(),
      wagerConfigPda: this.wagerConfigPda.toBase58(),
    };
  }

  async verifyEscrow({ wallet, lamports, escrowTxSig, intentId }) {
    if (this.mode !== 'onchain') {
      if (!wallet || typeof wallet !== 'string') return false;
      if (!Number.isSafeInteger(lamports) || lamports <= 0) return false;
      if (!escrowTxSig || typeof escrowTxSig !== 'string') return false;
      return escrowTxSig.trim().length >= 16;
    }

    if (!wallet || typeof wallet !== 'string') return false;
    if (!Number.isSafeInteger(lamports) || lamports <= 0) return false;
    if (!escrowTxSig || typeof escrowTxSig !== 'string') return false;
    if (intentId == null) return false;

    try {
      const playerPk = new PublicKey(wallet);
      const [escrowPda] = PublicKey.findProgramAddressSync(
        [Buffer.from('wager_escrow'), playerPk.toBuffer(), u64Le(intentId)],
        this.programId,
      );

      // Wallet sign-and-send can race propagation by a few hundred ms.
      for (let i = 0; i < 6; i++) {
        const sigStatus = await this.connection.getSignatureStatus(escrowTxSig, {
          searchTransactionHistory: true,
        });
        const status = sigStatus?.value;
        if (status?.err) return false;
        if (!status?.confirmationStatus) {
          await new Promise((r) => setTimeout(r, 500));
          continue;
        }

        const ai = await this.connection.getAccountInfo(escrowPda, 'confirmed');
        if (!ai?.data) {
          await new Promise((r) => setTimeout(r, 500));
          continue;
        }

        const escrow = parseEscrowAccount(ai.data);
        if (!escrow) return false;
        if (escrow.player !== wallet) return false;
        if (escrow.intentId !== BigInt(intentId)) return false;
        if (escrow.amountLamports !== BigInt(lamports)) return false;
        // Initiated
        if (escrow.status !== 0) return false;
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  async refundSearchCancel({ wallet, lamports, escrowTxSig }) {
    // NOTE: current on-chain program requires the player signer for cancel.
    // Backend relayer-only cancel is still mocked until client-side cancel tx is implemented.
    return {
      ok: true,
      wallet,
      lamports,
      escrowTxSig,
      refundTxSig: `refund_${uuidv4().replace(/-/g, '')}`,
    };
  }

  async settleMatch({ wagerId, lamportsEach, winnerWallet, loserWallet }) {
    const { potLamports, winnerLamports, treasuryLamports } = computePayouts(
      lamportsEach,
      WAGER.TREASURY_BPS,
    );

    // In real implementation, call Solana program `settle_match`.
    return {
      ok: true,
      wagerId,
      winnerWallet,
      loserWallet,
      lamportsEach: BigInt(lamportsEach),
      potLamports,
      winnerLamports,
      treasuryLamports,
      settlementTxSig: `settle_${uuidv4().replace(/-/g, '')}`,
    };
  }
}

module.exports = { WagerCustodyService };
