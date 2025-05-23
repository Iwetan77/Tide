module wave::liquidity_pool {
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance, Supply};

    // Error constants
    const EInvalidAmount: u64 = 1;
    const EZeroLiquidity: u64 = 2;

    // Liquidity Pool struct
    public struct LiquidityPool<phantom X, phantom Y> has key, store {
        id: UID,
        token_x: Balance<X>,
        token_y: Balance<Y>,
        lp_supply: Supply<LP<X, Y>>
    }

    // LP Token struct
    public struct LP<phantom X, phantom Y> has drop {}

    // Function to create a new liquidity pool
    public fun create_pool<X, Y>(
        token_x: Coin<X>, 
        token_y: Coin<Y>, 
        ctx: &mut TxContext
    ): LiquidityPool<X, Y> {
        let x_amount = coin::value(&token_x);
        let y_amount = coin::value(&token_y);

        assert!(x_amount > 0 && y_amount > 0, EInvalidAmount);

        LiquidityPool {
            id: object::new(ctx),
            token_x: coin::into_balance(token_x),
            token_y: coin::into_balance(token_y),
            lp_supply: balance::create_supply(LP<X, Y> {})
        }
    }

    // Add liquidity to the pool
    public fun add_liquidity<X, Y>(
        pool: &mut LiquidityPool<X, Y>,
        token_x: Coin<X>,
        token_y: Coin<Y>,
        ctx: &mut TxContext
    ): Coin<LP<X, Y>> {
        let x_added = coin::value(&token_x);
        let y_added = coin::value(&token_y);

        assert!(x_added > 0 && y_added > 0, EInvalidAmount);

        // Calculate LP tokens to mint
        let lp_tokens = calculate_lp_tokens(
            balance::value(&pool.token_x),
            balance::value(&pool.token_y),
            x_added,
            y_added
        );

        assert!(lp_tokens > 0, EZeroLiquidity);

        // Add tokens to pool
        balance::join(&mut pool.token_x, coin::into_balance(token_x));
        balance::join(&mut pool.token_y, coin::into_balance(token_y));

        // Mint LP tokens
        let lp_coin = coin::from_balance(
            balance::increase_supply(&mut pool.lp_supply, lp_tokens),
            ctx
        );

        lp_coin
    }

    // Swap tokens
    public fun swap<X, Y>(
        pool: &mut LiquidityPool<X, Y>,
        input_coin: Coin<X>,
        ctx: &mut TxContext
    ): Coin<Y> {
        let input_amount = coin::value(&input_coin);
        assert!(input_amount > 0, EInvalidAmount);

        // Calculate output amount using constant product formula
        let x_reserve = balance::value(&pool.token_x);
        let y_reserve = balance::value(&pool.token_y);

        let output_amount = calculate_swap_output(
            input_amount, 
            x_reserve, 
            y_reserve
        );

        // Add input tokens to pool
        balance::join(&mut pool.token_x, coin::into_balance(input_coin));

        // Create output coin
        let output_coin = coin::take(
            &mut pool.token_y, 
            output_amount, 
            ctx
        );

        output_coin
    }
    // Calculate LP tokens to mint
    fun calculate_lp_tokens(
        x_reserve: u64, 
        y_reserve: u64, 
        x_added: u64, 
        y_added: u64
    ): u64 {
        // Simplified LP token calculation
        if (x_reserve == 0 || y_reserve == 0) {
            x_added // Initial liquidity
        } else {
            // Proportional to smaller ratio
            let x_ratio = (x_added * y_reserve) / y_added;
            let y_ratio = (y_added * x_reserve) / x_added;
            
            if (x_ratio < y_ratio) x_ratio else y_ratio
        }
    }

    // Calculate swap output using constant product formula
    fun calculate_swap_output(
        input_amount: u64, 
        x_reserve: u64, 
        y_reserve: u64
    ): u64 {
        // Constant product formula with 0.3% fee
        let input_with_fee = input_amount * 997;
        let numerator = input_with_fee * y_reserve;
        let denominator = (x_reserve * 1000) + input_with_fee;
        
        numerator / denominator
    }

     // Getter for token X balance
    public fun get_token_x_balance<X, Y>(pool: &LiquidityPool<X, Y>): u64 {
        balance::value(&pool.token_x)
    }

    // Getter for token Y balance
    public fun get_token_y_balance<X, Y>(pool: &LiquidityPool<X, Y>): u64 {
        balance::value(&pool.token_y)
    }

    // Getter for total LP supply
    public fun get_lp_supply<X, Y>(pool: &LiquidityPool<X, Y>): u64 {
        balance::supply_value(&pool.lp_supply)
    }

    // Getter for pool UID
    public fun get_pool_id<X, Y>(pool: &LiquidityPool<X, Y>): &UID {
        &pool.id
    }

    // Optional: Get current price (ratio between token X and Y)
    public fun get_current_price<X, Y>(pool: &LiquidityPool<X, Y>): (u64, u64) {
        let x_balance = balance::value(&pool.token_x);
        let y_balance = balance::value(&pool.token_y);
        (x_balance, y_balance)
    }

    // Function to remove liquidity (optional, for completeness)
    public fun remove_liquidity<X, Y>(
        pool: &mut LiquidityPool<X, Y>,
        lp_coin: Coin<LP<X, Y>>,
        ctx: &mut TxContext
    ): (Coin<X>, Coin<Y>) {
        let lp_amount = coin::value(&lp_coin);
        assert!(lp_amount > 0, EInvalidAmount);

        let total_lp_supply = balance::supply_value(&pool.lp_supply);
        
        // Calculate proportional amounts to withdraw
        let x_withdrawn = (balance::value(&pool.token_x) * lp_amount) / total_lp_supply;
        let y_withdrawn = (balance::value(&pool.token_y) * lp_amount) / total_lp_supply;

        // Burn LP tokens
        balance::decrease_supply(&mut pool.lp_supply, coin::into_balance(lp_coin));

        // Withdraw tokens
        let token_x = coin::take(&mut pool.token_x, x_withdrawn, ctx);
        let token_y = coin::take(&mut pool.token_y, y_withdrawn, ctx);

        (token_x, token_y)

    }

}