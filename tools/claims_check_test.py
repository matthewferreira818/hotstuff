"""Behavior checks for the offline helper; synthetic drafts, no private data.
Run: PYTHONDONTWRITEBYTECODE=1 python3 tools/claims_check_test.py
"""
import copy
import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout, redirect_stderr
from datetime import date
from pathlib import Path
from unittest.mock import patch

from claims_check import check_text, load_facts, main, validate_facts

TODAY = date(2026, 10, 5)


class ClaimsChecks(unittest.TestCase):
    def setUp(self):
        # The tests run against a frozen copy of the facts (the 62-day situation GPT audited), so they keep meaning the same
        # thing when the real tools/claims_facts.json is updated.
        self.facts = load_facts(Path(__file__).with_name("claims_facts_test_fixture.json"))

    def codes(self, text, facts=None, day=TODAY):
        return {f.code for f in check_text(text, facts or self.facts, day)}

    def confirmed(self):
        facts = copy.deepcopy(self.facts)
        facts['feed'].update(website_history_since='2026-08-04', website_history_days=62, full_streak_confirmed=True)
        return facts

    def test_wrong_streak(self):
        self.assertIn('STREAK_COUNT', self.codes("My own store's feed has published a new post every day for 61 days."))

    def test_correct_counter_still_needs_archive(self):
        self.assertIn('STREAK_EVIDENCE', self.codes("My own store's feed has published a new post every day for 62 days."))

    def test_confirmed_full_streak(self):
        self.assertEqual(set(), self.codes("My own store’s feed has published a new post every day for 62 days.", self.confirmed()))

    def test_page_streak_scope(self):
        self.assertIn('STREAK_SCOPE', self.codes('My page has posted daily for 62 days.', self.confirmed()))

    def test_straight_days(self):
        self.assertIn('STREAK_COUNT', self.codes("Our store's feed has posted for 63 days in a row."))

    def test_gap_does_not_prove_streak(self):
        facts = copy.deepcopy(self.facts)
        facts['feed']['total'] = 61
        self.assertIn('FEED_GAPS', self.codes("Our store's feed has posted every day for 61 days.", facts))

    def test_since_requires_evidence(self):
        self.assertIn('STREAK_EVIDENCE', self.codes("My own store's feed has published every day since August 4th."))

    def test_today_requires_today(self):
        self.assertIn('NOT_POSTED_TODAY', self.codes("My own store's feed published today."))

    def test_published_total(self):
        self.assertIn('FEED_COUNT', self.codes('63 posts published automatically since August 4.'))

    def test_stale_snapshot(self):
        codes = self.codes('See the website.', day=date(2026, 10, 7))
        self.assertTrue({'STALE_FACTS', 'STALE_FEED'} <= codes)

    def test_future_snapshot_not_trusted(self):
        self.assertIn('STALE_FACTS', self.codes('See the website.', day=date(2026, 10, 4)))

    def test_daily_posts_name_feed(self):
        self.assertIn('UNCLEAR_FEED', self.codes('My page posts every day.'))
        self.assertNotIn('UNCLEAR_FEED', self.codes("My own store's feed publishes every day."))

    def test_three_daily_site_posts(self):
        for n in ['3', 'three', 'twice']:
            with self.subTest(n=n):
                self.assertIn('POST_FREQUENCY', self.codes(f"My own store's feed posts {n} times a day."))

    def test_x_frequency(self):
        self.assertIn('POST_FREQUENCY', self.codes("Our store's feed posts 3x daily."))

    def test_once_daily(self):
        self.assertEqual(set(), self.codes("My own store's feed posts once a day."))

    def test_off_channels(self):
        for channel in ['X', 'Twitter', 'Facebook', 'Instagram', 'TikTok', 'Pinterest']:
            with self.subTest(channel=channel):
                self.assertIn('CHANNEL_NOT_LIVE', self.codes(f'We post daily on {channel}.'))

    def test_tiktok_drafts_not_public(self):
        self.assertNotIn('CHANNEL_NOT_LIVE', self.codes('We publish TikTok drafts.'))
        self.assertIn('CHANNEL_NOT_LIVE', self.codes('We publish on TikTok daily.'))

    def test_negated_channel_not_claim(self):
        self.assertNotIn('CHANNEL_NOT_LIVE', self.codes("We don't post on X."))
        self.assertNotIn('CHANNEL_NOT_LIVE', self.codes('We used to post on X.'))

    def test_one_denial_not_other_channel(self):
        self.assertIn('CHANNEL_NOT_LIVE', self.codes("We don't post on X; Facebook posts daily."))

    def test_everywhere(self):
        self.assertIn('ALL_CHANNELS', self.codes('We post on every platform.'))

    def test_daily_restock(self):
        self.assertIn('CATALOG_FREQUENCY', self.codes('Restocked daily.'))
        self.assertIn('CATALOG_FREQUENCY', self.codes('The catalog refreshes every day.'))

    def test_wrong_catalog_interval(self):
        self.assertIn('CATALOG_FREQUENCY', self.codes('Our catalog refreshes every two days.'))
        self.assertNotIn('CATALOG_FREQUENCY', self.codes('Our catalog refreshes every three days.'))

    def test_products(self):
        self.assertIn('UNSUPPORTED_COUNT', self.codes('We have 120 products.'))
        self.assertIn('UNSUPPORTED_COUNT', self.codes('We have 200 products.'))
        self.assertNotIn('UNSUPPORTED_COUNT', self.codes('We have 199 products.'))
        self.assertNotIn('UNSUPPORTED_COUNT', self.codes('We have about 200 products.'))

    def test_jobs_checks_customers(self):
        for text in ['13 scheduled jobs run.', 'Fourteen health checks run.', '10 happy customers.']:
            with self.subTest(text=text):
                self.assertIn('UNSUPPORTED_COUNT', self.codes(text))

    def test_review_and_quote(self):
        for text in ['A five-star Google review.', 'Customers love us.', '"Amazing service" — a customer.', 'Trusted by local businesses.']:
            with self.subTest(text=text):
                self.assertIn('TESTIMONIAL_PROOF', self.codes(text))

    def test_no_testimonials(self):
        self.assertNotIn('TESTIMONIAL_PROOF', self.codes('We have no testimonials.'))

    def test_exact_approved_quote_does_not_approve_second(self):
        facts = copy.deepcopy(self.facts)
        facts['approved_testimonials'] = ['Customers say this is helpful']
        self.assertNotIn('TESTIMONIAL_PROOF', self.codes('Customers say this is helpful.', facts))
        self.assertIn('TESTIMONIAL_PROOF', self.codes('Customers say this is helpful. Customers say it tripled sales.', facts))

    def test_invented_outcomes(self):
        for text in ['Sales grew 30%.', '100 followers.', 'It doubled revenue.', 'Our customers earned $500.']:
            with self.subTest(text=text):
                self.assertTrue({'STATISTIC_PROOF', 'PRICE_OR_MONEY_PROOF'} & self.codes(text))

    def test_prices_and_currency(self):
        self.assertEqual(set(), self.codes('Free sample week first. $79/month CAD.'))
        self.assertIn('PRICE_OR_MONEY_PROOF', self.codes('$99/month CAD.'))
        self.assertIn('WRONG_CURRENCY', self.codes('$79/month USD.'))

    def test_absolute_results(self):
        self.assertIn('ABSOLUTE_PROMISE', self.codes('The engine never forgets.'))

    def test_trend_score(self):
        self.assertIn('TREND_FORMULA', self.codes('Trend score is a blend of search volume and sell-through.'))

    def test_shipping_and_zero_cost(self):
        self.assertIn('SHIPPING_SCOPE', self.codes('Free shipping on every order.'))
        self.assertIn('COST_SCOPE', self.codes('Operating cost: $0/month.'))
        self.assertNotIn('COST_SCOPE', self.codes('Hosting infrastructure is $0/month; domain and per-order costs are separate.'))

    def test_empty_text(self):
        with self.assertRaises(ValueError):
            check_text('   ', self.facts, TODAY)

    def test_missing_facts(self):
        with self.assertRaises(ValueError):
            validate_facts({})

    def test_bool_cannot_be_count(self):
        self.facts['feed']['total'] = True
        with self.assertRaises(ValueError):
            validate_facts(self.facts)

    def test_impossible_dates_and_totals(self):
        for key, value in [('since', '2026-10-07'), ('last', '2026-10-06'), ('total', 999)]:
            facts = copy.deepcopy(self.facts)
            facts['feed'][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate_facts(facts)

    def test_unproved_confirmation_rejected(self):
        self.facts['feed']['full_streak_confirmed'] = True
        with self.assertRaises(ValueError):
            validate_facts(self.facts)

    def test_negative_phrase_cannot_hide_joined_claim(self):
        self.assertIn('CHANNEL_NOT_LIVE', self.codes("We don't post on X and Facebook posts daily."))

    def test_draft_word_cannot_hide_public_post(self):
        self.assertIn('CHANNEL_NOT_LIVE', self.codes('We publish public TikTok posts and drafts.'))

    def test_published_total_before_number(self):
        self.assertIn('FEED_COUNT', self.codes('Our store feed has published 70 posts.'))

    def test_comma_count(self):
        self.assertIn('UNSUPPORTED_COUNT', self.codes('We have 1,000 happy customers.'))

    def test_plus_count(self):
        self.assertIn('UNSUPPORTED_COUNT', self.codes('We have 200+ products.'))

    def test_popularity_is_not_evidence(self):
        self.assertIn('TESTIMONIAL_PROOF', self.codes('Trending products people actually love.'))

    def test_unicode_daily_multiplier(self):
        self.assertIn('POST_FREQUENCY', self.codes("My own store's feed posts 3× daily."))

    def test_fictional_quote_cannot_approve_a_post(self):
        self.assertIn('TESTIMONIAL_PROOF', self.codes('Fictional sample: a five-star Google review.'))

    def test_checker_does_not_change_facts(self):
        before = copy.deepcopy(self.facts)
        check_text('My page posts daily.', self.facts, TODAY)
        self.assertEqual(before, self.facts)

    def test_cli_json_exit_and_no_draft_echo(self):
        output = io.StringIO()
        with redirect_stdout(output):
            status = main(['--text', 'We post on X daily.', '--as-of', '2026-10-05', '--json'])
        self.assertEqual(1, status)
        result = json.loads(output.getvalue())
        self.assertFalse(result['approved'])
        self.assertTrue(result['findings'])
        self.assertNotIn('We post on X daily.', output.getvalue())

    def test_cli_stdin(self):
        with patch('sys.stdin', io.StringIO('See findhotstuff.com/automation.')), redirect_stdout(io.StringIO()):
            self.assertEqual(0, main(['--as-of', '2026-10-05']))

    def test_cli_bad_facts_fail_closed(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / 'facts.json'
            path.write_text('{bad json')
            with redirect_stderr(io.StringIO()):
                self.assertEqual(2, main(['--text', 'See the website.', '--facts', str(path)]))


if __name__ == '__main__':
    unittest.main()
