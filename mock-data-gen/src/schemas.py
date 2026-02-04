import random
from datetime import datetime, timezone, timedelta

from faker import Faker

fake = Faker()

# ---------------------------------------------------------------------------
# Weighted distributions
# ---------------------------------------------------------------------------

BANNER_SIZES = [(300, 250), (728, 90), (160, 600), (320, 50), (970, 250)]
BANNER_SIZE_WEIGHTS = [0.40, 0.20, 0.15, 0.15, 0.10]

DEVICE_TYPES = [2, 1, 4]  # mobile/tablet, desktop, phone
DEVICE_TYPE_WEIGHTS = [0.60, 0.30, 0.10]

OS_CHOICES = ["iOS", "Android", "Windows", "macOS"]
OS_WEIGHTS = [0.35, 0.35, 0.20, 0.10]

OS_VERSIONS = {
    "iOS": ["16.0", "16.5", "17.0", "17.1", "17.2", "18.0"],
    "Android": ["12", "13", "14", "15"],
    "Windows": ["10", "11"],
    "macOS": ["13.0", "14.0", "15.0"],
}

GEO_COUNTRIES = ["USA", "GBR", "DEU", "CAN", "AUS", "FRA"]
GEO_COUNTRY_WEIGHTS = [0.50, 0.15, 0.10, 0.10, 0.10, 0.05]

GEO_REGIONS = {
    "USA": ["CA", "NY", "TX", "FL", "IL", "WA"],
    "GBR": ["ENG", "SCT"],
    "DEU": ["BY", "NW", "BE"],
    "CAN": ["ON", "BC", "QC"],
    "AUS": ["NSW", "VIC", "QLD"],
    "FRA": ["IDF", "PAC", "ARA"],
}

GEO_COORDS = {
    "USA": {"lat": (25.0, 48.0), "lon": (-124.0, -71.0)},
    "GBR": {"lat": (50.0, 58.0), "lon": (-8.0, 2.0)},
    "DEU": {"lat": (47.0, 55.0), "lon": (5.0, 15.0)},
    "CAN": {"lat": (42.0, 60.0), "lon": (-141.0, -52.0)},
    "AUS": {"lat": (-44.0, -10.0), "lon": (113.0, 154.0)},
    "FRA": {"lat": (42.0, 51.0), "lon": (-5.0, 9.0)},
}

IAB_CATEGORIES = [f"IAB{i}" for i in range(1, 11)]

TMAX_CHOICES = [100, 120, 150, 200, 300]


def generate_bid_request() -> dict:
    """Generate a single OpenRTB 2.6 BidRequest dictionary."""

    # Banner
    w, h = random.choices(BANNER_SIZES, weights=BANNER_SIZE_WEIGHTS, k=1)[0]
    banner_pos = random.randint(0, 3)

    # Device
    device_type = random.choices(DEVICE_TYPES, weights=DEVICE_TYPE_WEIGHTS, k=1)[0]
    os_name = random.choices(OS_CHOICES, weights=OS_WEIGHTS, k=1)[0]
    os_version = random.choice(OS_VERSIONS[os_name])

    # Geo
    country = random.choices(GEO_COUNTRIES, weights=GEO_COUNTRY_WEIGHTS, k=1)[0]
    region = random.choice(GEO_REGIONS[country])
    coords = GEO_COORDS[country]
    lat = round(random.uniform(*coords["lat"]), 4)
    lon = round(random.uniform(*coords["lon"]), 4)

    # Site / Publisher
    site_id = f"site-{random.randint(100, 999)}"
    pub_id = f"pub-{random.randint(100, 999)}"
    pub_name = fake.company()
    domain = fake.domain_name()
    page_path = fake.uri_path()
    page_url = f"https://{domain}/{page_path}"

    # Categories (1-3 random IAB categories)
    num_cats = random.randint(1, 3)
    categories = random.sample(IAB_CATEGORIES, k=num_cats)

    # Auction
    auction_type = random.choices([1, 2], weights=[0.70, 0.30], k=1)[0]
    tmax = random.choice(TMAX_CHOICES)
    bidfloor = round(random.uniform(0.01, 5.00), 2)

    # Regulatory
    coppa = random.choices([0, 1], weights=[0.95, 0.05], k=1)[0]
    gdpr = random.choices([0, 1], weights=[0.70, 0.30], k=1)[0]

    # Timestamps
    event_ts = datetime.now(timezone.utc)
    received_at = event_ts + timedelta(milliseconds=random.randint(1, 50))

    return {
        "id": fake.uuid4(),
        "imp": [
            {
                "id": "1",
                "banner": {"w": w, "h": h, "pos": banner_pos},
                "bidfloor": bidfloor,
                "bidfloorcur": "USD",
                "secure": 1,
            }
        ],
        "site": {
            "id": site_id,
            "domain": domain,
            "cat": categories,
            "page": page_url,
            "publisher": {"id": pub_id, "name": pub_name},
        },
        "device": {
            "ua": fake.user_agent(),
            "ip": fake.ipv4(),
            "geo": {
                "lat": lat,
                "lon": lon,
                "country": country,
                "region": region,
            },
            "devicetype": device_type,
            "os": os_name,
            "osv": os_version,
        },
        "user": {
            "id": fake.uuid4(),
            "buyeruid": fake.uuid4(),
        },
        "at": auction_type,
        "tmax": tmax,
        "cur": ["USD"],
        "source": {
            "fd": 1,
            "tid": fake.uuid4(),
        },
        "regs": {
            "coppa": coppa,
            "ext": {"gdpr": gdpr},
        },
        "event_timestamp": event_ts.isoformat(),
        "received_at": received_at.isoformat(),
    }
