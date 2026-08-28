"""Single source of truth for East Coast Social's public web address.

ECS currently lives as a section of the store's site. It will eventually move
to its own domain (eastcoastsocial.ca) so that a business-to-business service
stops being a subfolder of a gadget shop. That move touches printed cards, QR
codes on merch, Pinterest pins, sample packs, the Google listing and every
daily caption — which is exactly why the address belongs in one place instead
of being retyped in each generator.

To migrate: change HOST and PATH below, run the generators listed in
marketing/east-coast-social/domain-migration.md, and republish. Nothing else
in the code needs to be touched.

    from ecs_site import ecs_url
    ecs_url()            -> https://findhotstuff.com/automation/
    ecs_url("merch")     -> https://findhotstuff.com/automation/?ref=merch
    ecs_url("ecs", bare=True) -> findhotstuff.com/automation/?ref=ecs
"""

# --- the two lines the migration changes -------------------------------
HOST = "findhotstuff.com"
PATH = "/automation/"
# -----------------------------------------------------------------------

# eastcoastsocial.ca currently 301s here from a registrar URL-forward that
# DROPS the query string (verified 2026-08-28: ?ref=card is stripped), so
# anything needing attribution must point at HOST directly until that domain
# is served properly rather than forwarded.
BRAND_DOMAIN = "eastcoastsocial.ca"
BRAND_DOMAIN_PRESERVES_QUERY = False


def ecs_url(ref: str | None = None, bare: bool = False) -> str:
    """The canonical ECS address, optionally tagged for channel attribution.

    `bare` drops the scheme for places where a printed or spoken URL reads
    better without it (card faces, slide footers, captions).
    """
    url = f"{HOST}{PATH}"
    if not bare:
        url = f"https://{url}"
    if ref:
        url = f"{url}?ref={ref}"
    return url


def brand_url(ref: str | None = None) -> str:
    """The branded domain, for print where the short name matters more than
    tracking. Returns the tracking-safe address instead whenever the forward
    would eat the tag, so a QR code can never be silently untrackable."""
    if ref and not BRAND_DOMAIN_PRESERVES_QUERY:
        return ecs_url(ref)
    return f"https://{BRAND_DOMAIN}/" + (f"?ref={ref}" if ref else "")
