use anchor_lang::prelude::*;

declare_id!("PingPongXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX");

// ── Program ──────────────────────────────────────────────────────────────────

#[program]
pub mod ping_pong {
    use super::*;

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
        game.room_id         = room_id;
        game.player_left     = player_left;
        game.player_right    = player_right;
        game.paddle_type_left  = paddle_type_left;
        game.paddle_type_right = paddle_type_right;
        game.score_left      = 0;
        game.score_right     = 0;
        game.status          = GameStatus::Waiting as u8;
        game.created_at      = Clock::get()?.unix_timestamp;
        game.hit_count       = 0;
        game.vrf_seed        = [0u8; 32];
        Ok(())
    }

    /// Record a ball hit event.
    /// In a real VRF flow this would call Switchboard/Orao VRF CPI here.
    pub fn record_hit(
        ctx: Context<RecordHit>,
        hitter_side: u8,         // 0 = left, 1 = right
        ball_speed_x100: i32,    // speed * 100 to avoid floats
        vrf_request_id: [u8; 32],
    ) -> Result<()> {
        let game = &mut ctx.accounts.game;

        require!(
            game.status == GameStatus::Active as u8,
            PingPongError::GameNotActive
        );

        game.hit_count += 1;

        emit!(HitEvent {
            room_id:          game.room_id.clone(),
            hit_count:        game.hit_count,
            hitter_side,
            ball_speed_x100,
            vrf_request_id,
            timestamp:        Clock::get()?.unix_timestamp,
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
            room_id:      game.room_id.clone(),
            side,
            paddle_type,
            vrf_result,
            timestamp:    Clock::get()?.unix_timestamp,
        });

        Ok(())
    }

    /// Update score — called after each point scored.
    pub fn update_score(
        ctx: Context<RecordHit>,
        score_left: u8,
        score_right: u8,
    ) -> Result<()> {
        let game = &mut ctx.accounts.game;
        game.score_left  = score_left;
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

// ── State ─────────────────────────────────────────────────────────────────────

#[account]
pub struct GameAccount {
    pub room_id:           String,    // 4 + 36
    pub player_left:       Pubkey,    // 32
    pub player_right:      Pubkey,    // 32
    pub paddle_type_left:  u8,        // 1
    pub paddle_type_right: u8,        // 1
    pub score_left:        u8,        // 1
    pub score_right:       u8,        // 1
    pub status:            u8,        // 1 — GameStatus
    pub hit_count:         u32,       // 4
    pub vrf_seed:          [u8; 32],  // 32
    pub created_at:        i64,       // 8
}

impl GameAccount {
    pub fn space(room_id: &str) -> usize {
        8               // discriminator
        + 4 + room_id.len()
        + 32 + 32       // pubkeys
        + 1 + 1 + 1 + 1 + 1  // types, scores, status
        + 4             // hit_count
        + 32            // vrf_seed
        + 8             // created_at
    }
}

// ── Enums ─────────────────────────────────────────────────────────────────────

#[repr(u8)]
pub enum GameStatus {
    Waiting  = 0,
    Active   = 1,
    Finished = 2,
}

/// Paddle types — matches JS PADDLE_TYPES constants
/// 0=phoenix 1=frost 2=thunder 3=shadow 4=earth
#[repr(u8)]
pub enum PaddleTypeCode {
    Phoenix = 0,
    Frost   = 1,
    Thunder = 2,
    Shadow  = 3,
    Earth   = 4,
}

// ── Events ────────────────────────────────────────────────────────────────────

#[event]
pub struct HitEvent {
    pub room_id:          String,
    pub hit_count:        u32,
    pub hitter_side:      u8,
    pub ball_speed_x100:  i32,
    pub vrf_request_id:   [u8; 32],
    pub timestamp:        i64,
}

#[event]
pub struct PowerActivatedEvent {
    pub room_id:    String,
    pub side:       u8,
    pub paddle_type: u8,
    pub vrf_result: [u8; 32],
    pub timestamp:  i64,
}

// ── Errors ────────────────────────────────────────────────────────────────────

#[error_code]
pub enum PingPongError {
    #[msg("Game is not in Active status")]
    GameNotActive,
    #[msg("Invalid state transition")]
    InvalidState,
}
