# Wake delivery test, Haiku vs Sonnet (2026-11-06, ~6:20 PM Moncton, Friday)

The Helm's real wake prompt and flags (stream-json, tools ToolSearch/ListAgents/SendMessage only, dontAsk, no MCP, hooks off,
--no-session-persistence), run from an empty folder, target = Friday's own chat, fixed test text. "exact" = SendMessage called once,
reply success:true, sent to Friday, text identical. Interleaved so neither model got the quieter minutes.

| # | model | seconds | delivered | exact |
|---|---|---|---|---|
| 1 | sonnet | 8.5 | yes | yes |
| 2 | haiku | 11.0 | yes | yes |
| 3 | sonnet | 13.2 | yes | yes |
| 4 | haiku | 8.1 | yes | yes |
| 5 | sonnet | 9.5 | yes | yes |
| 6 | haiku | 10.6 | yes | yes |

Median: Haiku 10.6 s, Sonnet 9.5 s (3 each: a tiny sample; read it as "about the same", not "Haiku is slower").
Earlier the same evening (same harness): Haiku 3/3 exact deliveries (11.9, 11.2 incl. lowercase "friday" match, 13.3 s), and a missing
chat "LC-Nobody": Haiku NOT DELIVERED with 0 sends (10.6 s), Sonnet the same (9.7 s).
Only test text was sent (to Friday's own chat); no private text.
