'use strict';

const crypto = require('crypto');
const fs     = require('fs');
const os     = require('os');
const path   = require('path');
const {
  Connection,
  Keypair,
  PublicKey,
  SystemProgram,
  Transaction,
  TransactionInstruction,
} = require('@solana/web3.js');

const DEFAULT_RPC_URL   = process.env.SOLANA_RPC_URL   || 'https://api.devnet.solana.com';
const DEFAULT_PROGRAM_ID = process.env.SOLANA_PROGRAM_ID || 'Bcdp7uboxycoo6ApoMvnRDUoxKdVH4VvDPn1HLY7VYUR';
const KEYPAIR_PATH = process.env.SOLANA_KEYPAIR_PATH ||
  path.join(os.homedir(), '.config', 'solana', 'id.json');

// ── Helpers ────────────────────────────────────────────────────────────────────

function loadKeypair(keypairPath) {
  const raw = JSON.parse(fs.readFileSync(keypairPath, 'utf8'));
  return Keypair.fromSecretKey(Uint8Array.from(raw));
}

/** Returns the first 8 bytes of SHA-256("global:<name>") — Anchor's discriminator. */
function anchorDiscriminator(methodName) {
  return crypto
    .createHash('sha256')
    .update(`global:${methodName}`)
    .digest()
    .subarray(0, 8);
}

/** Encode a u64 value as 8-byte little-endian Buffer. */
function u64Le(value) {
  const b = Buffer.alloc(8);
  b.writeBigUInt64LE(BigInt(value));
  return b;
}

/**
 * Convert a UUID string (e.g. "550e8400-e29b-41d4-a716-446655440000") to a
 * 32-byte Buffer.  The 16 UUID bytes are placed first; the remaining 16 bytes
 * are zero-padded.  This is the canonical conversion used everywhere in the
 * backend so match_wagers and settle_match always agree on the PDA seed.
 */
function uuidToBytes32(uuid) {
  const hex = uuid.replace(/-/g, ''); // 32 hex chars = 16 bytes
  if (hex.length !== 32) throw new Error(`Invalid UUID hex length: ${hex.length}`);
  return Buffer.concat([Buffer.from(hex, 'hex'), Buffer.alloc(16)]);
}

// ── SolanaClient ───────────────────────────────────────────────────────────────

/**
 * Low-level Solana client used by WagerCustodyService (onchain mode).
 *
 * Handles:
 *   • init_wager_escrow  — house escrow for CPU wager games
 *   • match_wagers       — links two escrows into a MatchEscrow PDA
 *   • settle_match       — pays out winner + treasury from the MatchEscrow
 *   • cancel_wager_and_refund (unsigned tx) — for client-side signing
 *
 * All transactions are signed by the local match-authority keypair at
 * KEYPAIR_PATH (default: ~/.config/solana/id.json).
 */
class SolanaClient {
  constructor(opts = {}) {
    this.rpcUrl    = opts.rpcUrl    || DEFAULT_RPC_URL;
    this.programId = new PublicKey(opts.programId || DEFAULT_PROGRAM_ID);
    this.connection = new Connection(this.rpcUrl, 'confirmed');

    const keypairPath = opts.keypairPath || KEYPAIR_PATH;
    this.authority = loadKeypair(keypairPath);

    [this.wagerConfigPda] = PublicKey.findProgramAddressSync(
      [Buffer.from('wager_config')],
      this.programId,
    );

    // The treasury wallet was set to the authority wallet when
    // initialize_wager_config was called — keep them in sync.
    this.treasuryWallet = this.authority.publicKey;

    console.log('[SolanaClient] authority    =', this.authority.publicKey.toBase58());
    console.log('[SolanaClient] programId    =', this.programId.toBase58());
    console.log('[SolanaClient] wagerConfig  =', this.wagerConfigPda.toBase58());
    console.log('[SolanaClient] treasury     =', this.treasuryWallet.toBase58());
  }

  // ── PDA derivation ─────────────────────────────────────────────────────────

  /** Returns the wager_escrow PDA address (base58) for a given player + intentId. */
  deriveWagerEscrowPda(walletAddress, intentId) {
    const playerPk = new PublicKey(walletAddress);
    const [pda] = PublicKey.findProgramAddressSync(
      [Buffer.from('wager_escrow'), playerPk.toBuffer(), u64Le(intentId)],
      this.programId,
    );
    return pda.toBase58();
  }

  /** Returns the match_escrow PDA address (base58) for a given 32-byte wager_id. */
  deriveMatchEscrowPda(wagerIdBytes32) {
    const [pda] = PublicKey.findProgramAddressSync(
      [Buffer.from('match_escrow'), wagerIdBytes32],
      this.programId,
    );
    return pda.toBase58();
  }

  // ── Instructions ───────────────────────────────────────────────────────────

  /**
   * Call match_wagers on-chain.
   *
   * @param {object} p
   * @param {string}  p.wagerId         – UUID string (converted to [u8;32])
   * @param {string}  p.wagerEscrowPdaA – base58 PDA of player A's wager escrow
   * @param {string}  p.wagerEscrowPdaB – base58 PDA of player B's wager escrow
   * @returns {{ sig: string, matchEscrowPda: string }}
   */
  async matchWagers({ wagerId, wagerEscrowPdaA, wagerEscrowPdaB }) {
    const wagerIdBytes    = uuidToBytes32(wagerId);
    const matchEscrowAddr = this.deriveMatchEscrowPda(wagerIdBytes);
    const matchEscrowPk   = new PublicKey(matchEscrowAddr);
    const wagerAPk        = new PublicKey(wagerEscrowPdaA);
    const wagerBPk        = new PublicKey(wagerEscrowPdaB);

    const data = Buffer.concat([
      anchorDiscriminator('match_wagers'),
      wagerIdBytes,                          // [u8; 32]
    ]);

    const ix = new TransactionInstruction({
      programId: this.programId,
      keys: [
        { pubkey: this.wagerConfigPda,      isSigner: false, isWritable: false },
        { pubkey: this.authority.publicKey, isSigner: true,  isWritable: true  },
        { pubkey: matchEscrowPk,            isSigner: false, isWritable: true  },
        { pubkey: wagerAPk,                 isSigner: false, isWritable: true  },
        { pubkey: wagerBPk,                 isSigner: false, isWritable: true  },
        { pubkey: SystemProgram.programId,  isSigner: false, isWritable: false },
      ],
      data,
    });

    const sig = await this._buildAndSend([ix]);
    console.log(`[SolanaClient] matchWagers ok  sig=${sig} matchEscrow=${matchEscrowAddr}`);
    return { sig, matchEscrowPda: matchEscrowAddr };
  }

  /**
   * Call settle_match on-chain.
   *
   * @param {object} p
   * @param {string}  p.matchEscrowPda    – base58 match_escrow PDA
   * @param {string}  p.wagerEscrowPdaA   – base58 wager_escrow for player A
   * @param {string}  p.wagerEscrowPdaB   – base58 wager_escrow for player B
   * @param {string}  p.playerAWallet     – base58 wallet of player A
   * @param {string}  p.playerBWallet     – base58 wallet of player B
   * @param {string}  p.winnerWallet      – base58 wallet of the winner
   * @returns {string} transaction signature
   */
  async settleMatch({
    matchEscrowPda,
    wagerEscrowPdaA,
    wagerEscrowPdaB,
    playerAWallet,
    playerBWallet,
    winnerWallet,
  }) {
    const matchEscrowPk = new PublicKey(matchEscrowPda);
    const wagerAPk      = new PublicKey(wagerEscrowPdaA);
    const wagerBPk      = new PublicKey(wagerEscrowPdaB);
    const playerAPk     = new PublicKey(playerAWallet);
    const playerBPk     = new PublicKey(playerBWallet);
    const winnerPk      = new PublicKey(winnerWallet);

    const data = Buffer.concat([
      anchorDiscriminator('settle_match'),
      winnerPk.toBuffer(),   // Pubkey = 32 bytes
    ]);

    // Account order MUST match SettleMatch<'info> in lib.rs:
    //   wager_config, match_authority, treasury_wallet,
    //   player_a_wallet, player_b_wallet,
    //   wager_a, wager_b, match_escrow
    const ix = new TransactionInstruction({
      programId: this.programId,
      keys: [
        { pubkey: this.wagerConfigPda,      isSigner: false, isWritable: false },
        { pubkey: this.authority.publicKey, isSigner: true,  isWritable: true  },
        { pubkey: this.treasuryWallet,      isSigner: false, isWritable: true  },
        { pubkey: playerAPk,               isSigner: false, isWritable: true  },
        { pubkey: playerBPk,               isSigner: false, isWritable: true  },
        { pubkey: wagerAPk,                isSigner: false, isWritable: true  },
        { pubkey: wagerBPk,                isSigner: false, isWritable: true  },
        { pubkey: matchEscrowPk,           isSigner: false, isWritable: true  },
      ],
      data,
    });

    const sig = await this._buildAndSend([ix]);
    console.log(`[SolanaClient] settleMatch ok  sig=${sig} winner=${winnerWallet}`);
    return sig;
  }

  /**
   * Backend creates a "house" wager escrow for CPU wager games.
   * The authority wallet puts up the same amount of lamports as the player.
   *
   * @param {object} p
   * @param {number|bigint} p.intentId  – unique u64 intent id for this escrow
   * @param {number}        p.lamports  – wager amount in lamports
   * @returns {{ sig: string, wagerEscrowPda: string }}
   */
  async initHouseEscrow({ intentId, lamports }) {
    const houseAddr = this.deriveWagerEscrowPda(
      this.authority.publicKey.toBase58(),
      intentId,
    );
    const houseEscrowPk = new PublicKey(houseAddr);

    const data = Buffer.concat([
      anchorDiscriminator('init_wager_escrow'),
      u64Le(intentId),
      u64Le(lamports),
    ]);

    const ix = new TransactionInstruction({
      programId: this.programId,
      keys: [
        { pubkey: this.wagerConfigPda,      isSigner: false, isWritable: false },
        { pubkey: houseEscrowPk,            isSigner: false, isWritable: true  },
        { pubkey: this.authority.publicKey, isSigner: true,  isWritable: true  },
        { pubkey: SystemProgram.programId,  isSigner: false, isWritable: false },
      ],
      data,
    });

    const sig = await this._buildAndSend([ix]);
    console.log(`[SolanaClient] initHouseEscrow ok  sig=${sig} pda=${houseAddr}`);
    return { sig, wagerEscrowPda: houseAddr };
  }

  /**
   * Build an **unsigned** cancel_wager_and_refund transaction.
   * The player must sign it via MWA before it can be submitted.
   *
   * @param {object} p
   * @param {string}        p.playerWallet – base58 wallet of the player
   * @param {number|bigint} p.intentId     – the intentId used when creating the escrow
   * @returns {{ txBase64: string, blockhash: string, lastValidBlockHeight: number }}
   */
  async buildCancelTx({ playerWallet, intentId }) {
    const playerPk       = new PublicKey(playerWallet);
    const wagerEscrowPk  = new PublicKey(
      this.deriveWagerEscrowPda(playerWallet, intentId),
    );

    const data = Buffer.concat([
      anchorDiscriminator('cancel_wager_and_refund'),
      u64Le(intentId),
    ]);

    const ix = new TransactionInstruction({
      programId: this.programId,
      keys: [
        { pubkey: playerPk,      isSigner: true,  isWritable: true },
        { pubkey: wagerEscrowPk, isSigner: false, isWritable: true },
      ],
      data,
    });

    const latest = await this.connection.getLatestBlockhash('confirmed');
    const tx = new Transaction({
      feePayer: playerPk,
      blockhash: latest.blockhash,
      lastValidBlockHeight: latest.lastValidBlockHeight,
    });
    tx.add(ix);

    return {
      txBase64: tx
        .serialize({ requireAllSignatures: false, verifySignatures: false })
        .toString('base64'),
      blockhash: latest.blockhash,
      lastValidBlockHeight: latest.lastValidBlockHeight,
    };
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  async _buildAndSend(instructions) {
    const latest = await this.connection.getLatestBlockhash('confirmed');
    const tx = new Transaction({
      feePayer: this.authority.publicKey,
      blockhash: latest.blockhash,
      lastValidBlockHeight: latest.lastValidBlockHeight,
    });
    for (const ix of instructions) tx.add(ix);
    tx.sign(this.authority);

    const sig = await this.connection.sendRawTransaction(tx.serialize(), {
      skipPreflight: false,
      preflightCommitment: 'confirmed',
    });

    await this.connection.confirmTransaction(
      {
        signature: sig,
        blockhash: latest.blockhash,
        lastValidBlockHeight: latest.lastValidBlockHeight,
      },
      'confirmed',
    );

    return sig;
  }
}

module.exports = { SolanaClient, uuidToBytes32 };
