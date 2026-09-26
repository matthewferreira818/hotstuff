"""The trading rules, in one place.

Both the live bot (stock_bot.py) and every backtest (backtest.py) call
these two functions, so what we test is exactly what trades. Rules use
the watchlist's keys: buy_below, buy_dip_pct, take_profit_pct,
stop_loss_pct, sell_above (0 or missing = off).
"""


def sell_reason(price, entry, rules):
    """Why to sell a position bought at `entry`, or None to keep it."""
    change = (price - entry) / entry * 100
    if rules.get("sell_above") and price >= rules["sell_above"]:
        return "sell_above", f"price {price:.2f} >= sell_above {rules['sell_above']}"
    if rules.get("take_profit_pct") and change >= rules["take_profit_pct"]:
        return "take_profit", (f"up {change:.1f}% "
                               f"(target {rules['take_profit_pct']}%)")
    if rules.get("stop_loss_pct") and change <= -rules["stop_loss_pct"]:
        return "stop_loss", (f"down {change:.1f}% "
                             f"(stop-loss {rules['stop_loss_pct']}%)")
    return None


def buy_reason(price, high20, rules):
    """Why to buy at `price`, given the recent 20-day high, or None."""
    if rules.get("buy_below") and price <= rules["buy_below"]:
        return "buy_below", f"price {price:.2f} <= buy_below {rules['buy_below']}"
    if rules.get("buy_dip_pct") and high20:
        dip = (high20 - price) / high20 * 100
        if dip >= rules["buy_dip_pct"]:
            return "dip", f"{dip:.1f}% under its 20-day high {high20:.2f}"
    return None


def rules_from(dip, take_profit, stop_loss):
    """Short form (dip/TP/SL %) to watchlist-style rules."""
    return {"buy_dip_pct": dip, "take_profit_pct": take_profit,
            "stop_loss_pct": stop_loss}
