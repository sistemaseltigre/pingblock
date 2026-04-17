use anchor_lang::prelude::*;
use anchor_lang::solana_program::{program::invoke, system_instruction};

declare_id!("Bcdp7uboxycoo6ApoMvnRDUoxKdVH4VvDPn1HLY7VYUR");

const BPS_DENOMINATOR: u16 = 10_000;

#[cfg(test)]
const TREASURY_BPS_DEFAULT: u16 = 1_000;
#[cfg(test)]
const MIN_WAGER_LAMPORTS_DEFAULT: u64 = 1_000_000; // 0.001 SOL
#[cfg(test)]
const MAX_WAGER_LAMPORTS_DEFAULT: u64 = 5_000_000_000; // 5 SOL

// ── Program ──────────────────────────────────────────────────────────────────

#[program]
pub mod ping_pong {
    use super::*;

    // ── Existing game instructions ────────────────────────────────────────

    /// Initialize a new game session on-chain.
    /// Called by the backend after two players are matched.
    pub fn init_game(
        ctx: Context<InitGame>,
        room_id: String,
        player_left: Pubkey,
        player_right: Pubkey,
        paddle_type_left: u8,
        paddle_type_right: u8,
    ) -> Result<()> {
        let game = &mut ctx.accounts.game;
        game.room_id = room_id;
        game.player_left = player_left;
        game.player_right = player_right;
        game.paddle_type_left = paddle_type_left;
        game.paddle_type_right = paddle_type_right;
        game.score_left = 0;
        game.score_right = 0;
        game.status = GameStatus::Waiting as u8;
        game.created_at = Clock::get()?.unix_timestamp;
        game.hit_count = 0;
        game.vrf_seed = [0u8; 32];
        Ok(())
    }

    /// Record a ball hit event.
    /// In a real VRF flow this would call Switchboard/Orao VRF CPI here.
    pub fn record_hit(
        ctx: Context<RecordHit>,
        hitter_side: u8,      // 0 = left, 1 = right
        ball_speed_x100: i32, // speed * 100 to avoid floats
        vrf_request_id: [u8; 32],
    ) -> Result<()> {
        let game = &mut ctx.accounts.game;

        require!(
            game.status == GameStatus::Active as u8,
            PingPongError::GameNotActive
        );

        game.hit_count += 1;

        emit!(HitEvent {
            room_id: game.room_id.clone(),
            hit_count: game.hit_count,
            hitter_side,
            ball_speed_x100,
            vrf_request_id,
            timestamp: Clock::get()?.unix_timestamp,
        });

        Ok(())
    }

    /// Record VRF result that determined power activation.
    pub fn record_power_activation(
        ctx: Context<RecordHit>,
        side: u8,
        paddle_type: u8,
        vrf_result: [u8; 32],
    ) -> Result<()> {
        let game = &mut ctx.accounts.game;

        require!(
            game.status == GameStatus::Active as u8,
            PingPongError::GameNotActive
        );

        // Store last VRF result for auditability
        game.vrf_seed = vrf_result;

        emit!(PowerActivatedEvent {
            room_id: game.room_id.clone(),
            side,
            paddle_type,
            vrf_result,
            timestamp: Clock::get()?.unix_timestamp,
        });

        Ok(())
    }

    /// Update score — called after each point scored.
    pub fn update_score(ctx: Context<RecordHit>, score_left: u8, score_right: u8) -> Result<()> {
        let game = &mut ctx.accounts.game;
        game.score_left = score_left;
        game.score_right = score_right;

        if score_left >= 7 || score_right >= 7 {
            game.status = GameStatus::Finished as u8;
        }

        Ok(())
    }

    /// Start the game — called when both players are ready.
    pub fn start_game(ctx: Context<RecordHit>) -> Result<()> {
        let game = &mut ctx.accounts.game;
        require!(
            game.status == GameStatus::Waiting as u8,
            PingPongError::InvalidState
        );
        game.status = GameStatus::Active as u8;
        Ok(())
    }

    // ── Wager instructions (Phase B) ──────────────────────────────────────

    /// Initializes wager config PDA and operational authorities.
    pub fn initialize_wager_config(
        ctx: Context<InitializeWagerConfig>,
        match_authority: Pubkey,
        treasury_wallet: Pubkey,
        treasury_bps: u16,
        min_wager_lamports: u64,
        max_wager_lamports: u64,
    ) -> Result<()> {
        validate_treasury_bps(treasury_bps)?;
        validate_wager_range(min_wager_lamports, max_wager_lamports)?;

        let cfg = &mut ctx.accounts.wager_config;
        cfg.admin = ctx.accounts.admin.key();
        cfg.match_authority = match_authority;
        cfg.treasury_wallet = treasury_wallet;
        cfg.treasury_bps = treasury_bps;
        cfg.min_wager_lamports = min_wager_lamports;
        cfg.max_wager_lamports = max_wager_lamports;
        cfg.bump = ctx.bumps.wager_config;

        Ok(())
    }

    /// Admin-only config update.
    pub fn update_wager_config(
        ctx: Context<UpdateWagerConfig>,
        match_authority: Pubkey,
        treasury_wallet: Pubkey,
        treasury_bps: u16,
        min_wager_lamports: u64,
        max_wager_lamports: u64,
    ) -> Result<()> {
        validate_treasury_bps(treasury_bps)?;
        validate_wager_range(min_wager_lamports, max_wager_lamports)?;

        let cfg = &mut ctx.accounts.wager_config;
        cfg.match_authority = match_authority;
        cfg.treasury_wallet = treasury_wallet;
        cfg.treasury_bps = treasury_bps;
        cfg.min_wager_lamports = min_wager_lamports;
        cfg.max_wager_lamports = max_wager_lamports;

        Ok(())
    }

    /// Player locks SOL in escrow while searching for a wager match.
    pub fn init_wager_escrow(
        ctx: Context<InitWagerEscrow>,
        intent_id: u64,
        amount_lamports: u64,
    ) -> Result<()> {
        let cfg = &ctx.accounts.wager_config;
        validate_wager_amount(
            amount_lamports,
            cfg.min_wager_lamports,
            cfg.max_wager_lamports,
        )?;

        let escrow_key = ctx.accounts.wager_escrow.key();
        invoke(
            &system_instruction::transfer(
                &ctx.accounts.player.key(),
                &escrow_key,
                amount_lamports,
            ),
            &[
                ctx.accounts.player.to_account_info(),
                ctx.accounts.wager_escrow.to_account_info(),
                ctx.accounts.system_program.to_account_info(),
            ],
        )?;

        let escrow = &mut ctx.accounts.wager_escrow;
        escrow.player = ctx.accounts.player.key();
        escrow.intent_id = intent_id;
        escrow.amount_lamports = amount_lamports;
        escrow.status = WagerEscrowStatus::Initiated as u8;
        escrow.match_escrow = Pubkey::default();
        escrow.created_at = Clock::get()?.unix_timestamp;
        escrow.bump = ctx.bumps.wager_escrow;

        emit!(WagerEscrowCreatedEvent {
            player: escrow.player,
            escrow: escrow_key,
            intent_id,
            amount_lamports,
            timestamp: escrow.created_at,
        });

        Ok(())
    }

    /// Player cancels search and receives full wager amount back.
    pub fn cancel_wager_and_refund(ctx: Context<CancelWagerAndRefund>, intent_id: u64) -> Result<()> {
        let escrow_key = ctx.accounts.wager_escrow.key();
        let escrow_ai = ctx.accounts.wager_escrow.to_account_info();
        let player_ai = ctx.accounts.player.to_account_info();
        let escrow = &mut ctx.accounts.wager_escrow;
        require!(escrow.intent_id == intent_id, PingPongError::IntentIdMismatch);
        require!(
            escrow.status == WagerEscrowStatus::Initiated as u8,
            PingPongError::EscrowNotInitiated
        );

        // Return only wagered funds; close() returns rent-exempt reserve.
        transfer_lamports(
            &escrow_ai,
            &player_ai,
            escrow.amount_lamports,
        )?;

        escrow.status = WagerEscrowStatus::Cancelled as u8;

        emit!(WagerRefundedEvent {
            player: ctx.accounts.player.key(),
            escrow: escrow_key,
            amount_lamports: escrow.amount_lamports,
            timestamp: Clock::get()?.unix_timestamp,
        });

        Ok(())
    }

    /// Backend/relayer authority matches two open escrows with equal amount.
    pub fn match_wagers(ctx: Context<MatchWagers>, wager_id: [u8; 32]) -> Result<()> {
        let match_escrow_key = ctx.accounts.match_escrow.key();
        let wager_a = &mut ctx.accounts.wager_a;
        let wager_b = &mut ctx.accounts.wager_b;

        require!(
            wager_a.status == WagerEscrowStatus::Initiated as u8
                && wager_b.status == WagerEscrowStatus::Initiated as u8,
            PingPongError::EscrowNotInitiated
        );
        require!(
            wager_a.player != wager_b.player,
            PingPongError::PlayersMustBeDistinct
        );
        require!(
            wager_a.amount_lamports == wager_b.amount_lamports,
            PingPongError::WagerAmountMismatch
        );
        require!(
            wager_a.match_escrow == Pubkey::default()
                && wager_b.match_escrow == Pubkey::default(),
            PingPongError::EscrowAlreadyMatched
        );

        let pot_lamports = wager_a
            .amount_lamports
            .checked_mul(2)
            .ok_or(PingPongError::MathOverflow)?;

        let match_escrow = &mut ctx.accounts.match_escrow;
        match_escrow.wager_id = wager_id;
        match_escrow.player_a = wager_a.player;
        match_escrow.player_b = wager_b.player;
        match_escrow.amount_each_lamports = wager_a.amount_lamports;
        match_escrow.pot_lamports = pot_lamports;
        match_escrow.winner = Pubkey::default();
        match_escrow.status = MatchEscrowStatus::Open as u8;
        match_escrow.treasury_bps = ctx.accounts.wager_config.treasury_bps;
        match_escrow.created_at = Clock::get()?.unix_timestamp;
        match_escrow.bump = ctx.bumps.match_escrow;

        wager_a.status = WagerEscrowStatus::Matched as u8;
        wager_b.status = WagerEscrowStatus::Matched as u8;
        wager_a.match_escrow = match_escrow_key;
        wager_b.match_escrow = match_escrow_key;

        emit!(WagerMatchedEvent {
            wager_id,
            match_escrow: match_escrow_key,
            player_a: match_escrow.player_a,
            player_b: match_escrow.player_b,
            amount_each_lamports: match_escrow.amount_each_lamports,
            pot_lamports,
            timestamp: match_escrow.created_at,
        });

        Ok(())
    }

    /// Settles matched wager:
    /// winner gets 90%, treasury gets 10%.
    pub fn settle_match(ctx: Context<SettleMatch>, winner: Pubkey) -> Result<()> {
        let match_escrow_key = ctx.accounts.match_escrow.key();
        let treasury_ai = ctx.accounts.treasury_wallet.to_account_info();
        let match_escrow = &mut ctx.accounts.match_escrow;
        let wager_a = &mut ctx.accounts.wager_a;
        let wager_b = &mut ctx.accounts.wager_b;

        require!(
            match_escrow.status == MatchEscrowStatus::Open as u8,
            PingPongError::MatchNotOpen
        );
        require!(
            winner == match_escrow.player_a || winner == match_escrow.player_b,
            PingPongError::InvalidWinner
        );
        require!(
            wager_a.match_escrow == match_escrow_key
                && wager_b.match_escrow == match_escrow_key,
            PingPongError::EscrowMatchMismatch
        );
        require!(
            wager_a.status == WagerEscrowStatus::Matched as u8
                && wager_b.status == WagerEscrowStatus::Matched as u8,
            PingPongError::EscrowNotMatched
        );
        require!(
            wager_a.amount_lamports == match_escrow.amount_each_lamports
                && wager_b.amount_lamports == match_escrow.amount_each_lamports,
            PingPongError::WagerAmountMismatch
        );

        let (_pot, winner_lamports, treasury_lamports) =
            compute_payouts(match_escrow.amount_each_lamports, match_escrow.treasury_bps)?;
        let total_principal = match_escrow
            .amount_each_lamports
            .checked_mul(2)
            .ok_or(PingPongError::MathOverflow)?;
        require!(total_principal == match_escrow.pot_lamports, PingPongError::PotMismatch);
        require!(
            winner_lamports
                .checked_add(treasury_lamports)
                .ok_or(PingPongError::MathOverflow)?
                == total_principal,
            PingPongError::PayoutMismatch
        );

        // Split winner payout across both escrows without overdrawing either one.
        let winner_from_a = winner_lamports.min(match_escrow.amount_each_lamports);
        let winner_from_b = winner_lamports
            .checked_sub(winner_from_a)
            .ok_or(PingPongError::MathOverflow)?;

        let treasury_from_a = match_escrow
            .amount_each_lamports
            .checked_sub(winner_from_a)
            .ok_or(PingPongError::MathOverflow)?;
        let treasury_from_b = match_escrow
            .amount_each_lamports
            .checked_sub(winner_from_b)
            .ok_or(PingPongError::MathOverflow)?;

        if winner == match_escrow.player_a {
            transfer_lamports(
                &wager_a.to_account_info(),
                &ctx.accounts.player_a_wallet.to_account_info(),
                winner_from_a,
            )?;
            transfer_lamports(
                &wager_b.to_account_info(),
                &ctx.accounts.player_a_wallet.to_account_info(),
                winner_from_b,
            )?;
        } else {
            transfer_lamports(
                &wager_a.to_account_info(),
                &ctx.accounts.player_b_wallet.to_account_info(),
                winner_from_a,
            )?;
            transfer_lamports(
                &wager_b.to_account_info(),
                &ctx.accounts.player_b_wallet.to_account_info(),
                winner_from_b,
            )?;
        }
        transfer_lamports(
            &wager_a.to_account_info(),
            &treasury_ai,
            treasury_from_a,
        )?;
        transfer_lamports(
            &wager_b.to_account_info(),
            &treasury_ai,
            treasury_from_b,
        )?;

        wager_a.status = WagerEscrowStatus::Settled as u8;
        wager_b.status = WagerEscrowStatus::Settled as u8;
        match_escrow.status = MatchEscrowStatus::Settled as u8;
        match_escrow.winner = winner;

        emit!(WagerSettledEvent {
            wager_id: match_escrow.wager_id,
            winner,
            winner_lamports,
            treasury_lamports,
            timestamp: Clock::get()?.unix_timestamp,
        });

        Ok(())
    }
}

// ── Accounts ─────────────────────────────────────────────────────────────────

#[derive(Accounts)]
#[instruction(room_id: String)]
pub struct InitGame<'info> {
    #[account(
        init,
        payer = authority,
        space = GameAccount::space(&room_id),
        seeds = [b"game", room_id.as_bytes()],
        bump,
    )]
    pub game: Account<'info, GameAccount>,

    #[account(mut)]
    pub authority: Signer<'info>,

    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct RecordHit<'info> {
    #[account(mut)]
    pub game: Account<'info, GameAccount>,
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct InitializeWagerConfig<'info> {
    #[account(
        init,
        payer = admin,
        space = WagerConfig::SPACE,
        seeds = [b"wager_config"],
        bump
    )]
    pub wager_config: Account<'info, WagerConfig>,

    #[account(mut)]
    pub admin: Signer<'info>,

    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct UpdateWagerConfig<'info> {
    #[account(mut, seeds = [b"wager_config"], bump = wager_config.bump, has_one = admin)]
    pub wager_config: Account<'info, WagerConfig>,
    pub admin: Signer<'info>,
}

#[derive(Accounts)]
#[instruction(intent_id: u64)]
pub struct InitWagerEscrow<'info> {
    #[account(seeds = [b"wager_config"], bump = wager_config.bump)]
    pub wager_config: Account<'info, WagerConfig>,

    #[account(
        init,
        payer = player,
        space = WagerEscrow::SPACE,
        seeds = [b"wager_escrow", player.key().as_ref(), &intent_id.to_le_bytes()],
        bump
    )]
    pub wager_escrow: Account<'info, WagerEscrow>,

    #[account(mut)]
    pub player: Signer<'info>,

    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
#[instruction(intent_id: u64)]
pub struct CancelWagerAndRefund<'info> {
    #[account(mut)]
    pub player: Signer<'info>,

    #[account(
        mut,
        close = player,
        seeds = [b"wager_escrow", player.key().as_ref(), &intent_id.to_le_bytes()],
        bump = wager_escrow.bump,
        constraint = wager_escrow.player == player.key() @ PingPongError::UnauthorizedPlayer
    )]
    pub wager_escrow: Account<'info, WagerEscrow>,
}

#[derive(Accounts)]
#[instruction(wager_id: [u8; 32])]
pub struct MatchWagers<'info> {
    #[account(seeds = [b"wager_config"], bump = wager_config.bump)]
    pub wager_config: Account<'info, WagerConfig>,

    #[account(mut, address = wager_config.match_authority)]
    pub match_authority: Signer<'info>,

    #[account(
        init,
        payer = match_authority,
        space = MatchEscrow::SPACE,
        seeds = [b"match_escrow", wager_id.as_ref()],
        bump
    )]
    pub match_escrow: Account<'info, MatchEscrow>,

    #[account(mut)]
    pub wager_a: Account<'info, WagerEscrow>,

    #[account(mut)]
    pub wager_b: Account<'info, WagerEscrow>,

    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct SettleMatch<'info> {
    #[account(seeds = [b"wager_config"], bump = wager_config.bump)]
    pub wager_config: Account<'info, WagerConfig>,

    #[account(mut, address = wager_config.match_authority)]
    pub match_authority: Signer<'info>,

    #[account(mut, address = wager_config.treasury_wallet)]
    pub treasury_wallet: SystemAccount<'info>,

    #[account(mut, address = match_escrow.player_a)]
    pub player_a_wallet: SystemAccount<'info>,

    #[account(mut, address = match_escrow.player_b)]
    pub player_b_wallet: SystemAccount<'info>,

    #[account(
        mut,
        close = player_a_wallet,
        constraint = wager_a.player == match_escrow.player_a @ PingPongError::EscrowMatchMismatch
    )]
    pub wager_a: Account<'info, WagerEscrow>,

    #[account(
        mut,
        close = player_b_wallet,
        constraint = wager_b.player == match_escrow.player_b @ PingPongError::EscrowMatchMismatch
    )]
    pub wager_b: Account<'info, WagerEscrow>,

    #[account(
        mut,
        seeds = [b"match_escrow", match_escrow.wager_id.as_ref()],
        bump = match_escrow.bump,
        close = match_authority
    )]
    pub match_escrow: Account<'info, MatchEscrow>,
}

// ── State ─────────────────────────────────────────────────────────────────────

#[account]
pub struct GameAccount {
    pub room_id: String, // 4 + 36
    pub player_left: Pubkey, // 32
    pub player_right: Pubkey, // 32
    pub paddle_type_left: u8, // 1
    pub paddle_type_right: u8, // 1
    pub score_left: u8,  // 1
    pub score_right: u8, // 1
    pub status: u8,      // 1 — GameStatus
    pub hit_count: u32,  // 4
    pub vrf_seed: [u8; 32], // 32
    pub created_at: i64, // 8
}

impl GameAccount {
    pub fn space(room_id: &str) -> usize {
        8 // discriminator
        + 4
        + room_id.len()
        + 32
        + 32 // pubkeys
        + 1
        + 1
        + 1
        + 1
        + 1 // types, scores, status
        + 4 // hit_count
        + 32 // vrf_seed
        + 8 // created_at
    }
}

#[account]
pub struct WagerConfig {
    pub admin: Pubkey,
    pub match_authority: Pubkey,
    pub treasury_wallet: Pubkey,
    pub treasury_bps: u16,
    pub min_wager_lamports: u64,
    pub max_wager_lamports: u64,
    pub bump: u8,
}

impl WagerConfig {
    pub const SPACE: usize = 8 + 32 + 32 + 32 + 2 + 8 + 8 + 1;
}

#[account]
pub struct WagerEscrow {
    pub player: Pubkey,
    pub intent_id: u64,
    pub amount_lamports: u64,
    pub status: u8,
    pub match_escrow: Pubkey,
    pub created_at: i64,
    pub bump: u8,
}

impl WagerEscrow {
    pub const SPACE: usize = 8 + 32 + 8 + 8 + 1 + 32 + 8 + 1;
}

#[account]
pub struct MatchEscrow {
    pub wager_id: [u8; 32],
    pub player_a: Pubkey,
    pub player_b: Pubkey,
    pub amount_each_lamports: u64,
    pub pot_lamports: u64,
    pub winner: Pubkey,
    pub status: u8,
    pub treasury_bps: u16,
    pub created_at: i64,
    pub bump: u8,
}

impl MatchEscrow {
    pub const SPACE: usize = 8 + 32 + 32 + 32 + 8 + 8 + 32 + 1 + 2 + 8 + 1;
}

// ── Enums ─────────────────────────────────────────────────────────────────────

#[repr(u8)]
pub enum GameStatus {
    Waiting = 0,
    Active = 1,
    Finished = 2,
}

/// Paddle types — matches JS PADDLE_TYPES constants
/// 0=phoenix 1=frost 2=thunder 3=shadow 4=earth
#[repr(u8)]
pub enum PaddleTypeCode {
    Phoenix = 0,
    Frost = 1,
    Thunder = 2,
    Shadow = 3,
    Earth = 4,
}

#[repr(u8)]
pub enum WagerEscrowStatus {
    Initiated = 0,
    Matched = 1,
    Cancelled = 2,
    Settled = 3,
}

#[repr(u8)]
pub enum MatchEscrowStatus {
    Open = 0,
    Settled = 1,
}

// ── Events ────────────────────────────────────────────────────────────────────

#[event]
pub struct HitEvent {
    pub room_id: String,
    pub hit_count: u32,
    pub hitter_side: u8,
    pub ball_speed_x100: i32,
    pub vrf_request_id: [u8; 32],
    pub timestamp: i64,
}

#[event]
pub struct PowerActivatedEvent {
    pub room_id: String,
    pub side: u8,
    pub paddle_type: u8,
    pub vrf_result: [u8; 32],
    pub timestamp: i64,
}

#[event]
pub struct WagerEscrowCreatedEvent {
    pub player: Pubkey,
    pub escrow: Pubkey,
    pub intent_id: u64,
    pub amount_lamports: u64,
    pub timestamp: i64,
}

#[event]
pub struct WagerMatchedEvent {
    pub wager_id: [u8; 32],
    pub match_escrow: Pubkey,
    pub player_a: Pubkey,
    pub player_b: Pubkey,
    pub amount_each_lamports: u64,
    pub pot_lamports: u64,
    pub timestamp: i64,
}

#[event]
pub struct WagerSettledEvent {
    pub wager_id: [u8; 32],
    pub winner: Pubkey,
    pub winner_lamports: u64,
    pub treasury_lamports: u64,
    pub timestamp: i64,
}

#[event]
pub struct WagerRefundedEvent {
    pub player: Pubkey,
    pub escrow: Pubkey,
    pub amount_lamports: u64,
    pub timestamp: i64,
}

// ── Helpers ───────────────────────────────────────────────────────────────────

fn validate_treasury_bps(treasury_bps: u16) -> Result<()> {
    require!(
        treasury_bps <= BPS_DENOMINATOR,
        PingPongError::TreasuryBpsOutOfRange
    );
    Ok(())
}

fn validate_wager_range(min_wager_lamports: u64, max_wager_lamports: u64) -> Result<()> {
    require!(
        min_wager_lamports > 0 && min_wager_lamports <= max_wager_lamports,
        PingPongError::InvalidWagerRange
    );
    Ok(())
}

fn validate_wager_amount(amount: u64, min: u64, max: u64) -> Result<()> {
    require!(amount > 0, PingPongError::InvalidWagerAmount);
    require!(amount >= min && amount <= max, PingPongError::InvalidWagerAmount);
    Ok(())
}

fn compute_payouts(amount_each: u64, treasury_bps: u16) -> Result<(u64, u64, u64)> {
    validate_treasury_bps(treasury_bps)?;
    require!(amount_each > 0, PingPongError::InvalidWagerAmount);

    let pot = amount_each
        .checked_mul(2)
        .ok_or(PingPongError::MathOverflow)?;

    let denom = BPS_DENOMINATOR as u128;
    let winner_numerator = (BPS_DENOMINATOR - treasury_bps) as u128;
    let winner = ((pot as u128) * winner_numerator / denom) as u64;
    let treasury = pot
        .checked_sub(winner)
        .ok_or(PingPongError::MathOverflow)?;

    Ok((pot, winner, treasury))
}

fn transfer_lamports(from: &AccountInfo, to: &AccountInfo, amount: u64) -> Result<()> {
    if amount == 0 {
        return Ok(());
    }

    let mut from_lamports = from.try_borrow_mut_lamports()?;
    require!(
        **from_lamports >= amount,
        PingPongError::InsufficientEscrowFunds
    );
    let from_next = (**from_lamports)
        .checked_sub(amount)
        .ok_or(PingPongError::MathOverflow)?;
    **from_lamports = from_next;
    drop(from_lamports);

    let mut to_lamports = to.try_borrow_mut_lamports()?;
    let to_next = (**to_lamports)
        .checked_add(amount)
        .ok_or(PingPongError::MathOverflow)?;
    **to_lamports = to_next;
    Ok(())
}

// ── Errors ────────────────────────────────────────────────────────────────────

#[error_code]
pub enum PingPongError {
    #[msg("Game is not in Active status")]
    GameNotActive,
    #[msg("Invalid state transition")]
    InvalidState,
    #[msg("Treasury bps is out of range")]
    TreasuryBpsOutOfRange,
    #[msg("Invalid wager range")]
    InvalidWagerRange,
    #[msg("Invalid wager amount")]
    InvalidWagerAmount,
    #[msg("Math overflow")]
    MathOverflow,
    #[msg("Intent id mismatch")]
    IntentIdMismatch,
    #[msg("Escrow is not in Initiated status")]
    EscrowNotInitiated,
    #[msg("Unauthorized player")]
    UnauthorizedPlayer,
    #[msg("Escrow already matched")]
    EscrowAlreadyMatched,
    #[msg("Wager amount mismatch")]
    WagerAmountMismatch,
    #[msg("Players must be distinct")]
    PlayersMustBeDistinct,
    #[msg("Match escrow is not open")]
    MatchNotOpen,
    #[msg("Invalid winner")]
    InvalidWinner,
    #[msg("Escrow account does not belong to this match")]
    EscrowMatchMismatch,
    #[msg("Escrow is not in Matched status")]
    EscrowNotMatched,
    #[msg("Pot does not match expected value")]
    PotMismatch,
    #[msg("Payout does not match expected value")]
    PayoutMismatch,
    #[msg("Escrow has insufficient funds")]
    InsufficientEscrowFunds,
}

// ── Unit tests (Phase B logic guards) ───────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn payouts_90_10_for_one_sol_each() {
        let one_sol = 1_000_000_000;
        let (pot, winner, treasury) =
            compute_payouts(one_sol, TREASURY_BPS_DEFAULT).expect("payout");
        assert_eq!(pot, 2_000_000_000);
        assert_eq!(winner, 1_800_000_000);
        assert_eq!(treasury, 200_000_000);
    }

    #[test]
    fn payouts_conserve_for_small_amount() {
        let (pot, winner, treasury) =
            compute_payouts(1, TREASURY_BPS_DEFAULT).expect("payout");
        assert_eq!(pot, winner + treasury);
    }

    #[test]
    fn wager_amount_validation_rejects_out_of_range() {
        assert!(validate_wager_amount(
            MIN_WAGER_LAMPORTS_DEFAULT,
            MIN_WAGER_LAMPORTS_DEFAULT,
            MAX_WAGER_LAMPORTS_DEFAULT,
        )
        .is_ok());
        assert!(validate_wager_amount(
            MAX_WAGER_LAMPORTS_DEFAULT,
            MIN_WAGER_LAMPORTS_DEFAULT,
            MAX_WAGER_LAMPORTS_DEFAULT,
        )
        .is_ok());

        assert!(validate_wager_amount(
            0,
            MIN_WAGER_LAMPORTS_DEFAULT,
            MAX_WAGER_LAMPORTS_DEFAULT,
        )
        .is_err());
        assert!(validate_wager_amount(
            MIN_WAGER_LAMPORTS_DEFAULT - 1,
            MIN_WAGER_LAMPORTS_DEFAULT,
            MAX_WAGER_LAMPORTS_DEFAULT,
        )
        .is_err());
        assert!(validate_wager_amount(
            MAX_WAGER_LAMPORTS_DEFAULT + 1,
            MIN_WAGER_LAMPORTS_DEFAULT,
            MAX_WAGER_LAMPORTS_DEFAULT,
        )
        .is_err());
    }

    #[test]
    fn treasury_bps_validation_works() {
        assert!(validate_treasury_bps(0).is_ok());
        assert!(validate_treasury_bps(TREASURY_BPS_DEFAULT).is_ok());
        assert!(validate_treasury_bps(BPS_DENOMINATOR).is_ok());
        assert!(validate_treasury_bps(BPS_DENOMINATOR + 1).is_err());
    }
}
