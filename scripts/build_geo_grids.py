"""
Build data/grids/us-states.json and data/grids/world.json from source data.

JSON schema (same for all grids):
  [{"code": "CA", "row": 4, "col": 1,
    "names": ["California", "CALIFORNIA"],   // all matching strings, case-insensitive
    "territory": false}]                     // optional; true = hidden unless ShowTerritories

Run from repo root:
  python scripts/build_geo_grids.py
"""

import json
import pathlib

REPO = pathlib.Path(__file__).parent.parent
GRIDS_DIR = REPO / "data" / "grids"
GRIDS_DIR.mkdir(parents=True, exist_ok=True)

# ── US States ────────────────────────────────────────────────────────────────
# Layout mirrors sb_us_grid / sb_us_lookup in de_statebins.m

US_TILES = [
    # code  row  col  name
    ("ME",   0,  11, "Maine"),
    ("WI",   1,   6, "Wisconsin"),
    ("VT",   1,  10, "Vermont"),
    ("NH",   1,  11, "New Hampshire"),
    ("WA",   2,   1, "Washington"),
    ("ID",   2,   2, "Idaho"),
    ("MT",   2,   3, "Montana"),
    ("ND",   2,   4, "North Dakota"),
    ("MN",   2,   5, "Minnesota"),
    ("IL",   2,   6, "Illinois"),
    ("MI",   2,   7, "Michigan"),
    ("NY",   2,   9, "New York"),
    ("MA",   2,  10, "Massachusetts"),
    ("OR",   3,   1, "Oregon"),
    ("NV",   3,   2, "Nevada"),
    ("WY",   3,   3, "Wyoming"),
    ("SD",   3,   4, "South Dakota"),
    ("IA",   3,   5, "Iowa"),
    ("IN",   3,   6, "Indiana"),
    ("OH",   3,   7, "Ohio"),
    ("PA",   3,   8, "Pennsylvania"),
    ("NJ",   3,   9, "New Jersey"),
    ("CT",   3,  10, "Connecticut"),
    ("RI",   3,  11, "Rhode Island"),
    ("CA",   4,   1, "California"),
    ("UT",   4,   2, "Utah"),
    ("CO",   4,   3, "Colorado"),
    ("NE",   4,   4, "Nebraska"),
    ("MO",   4,   5, "Missouri"),
    ("KY",   4,   6, "Kentucky"),
    ("WV",   4,   7, "West Virginia"),
    ("VA",   4,   8, "Virginia"),
    ("MD",   4,   9, "Maryland"),
    ("DE",   4,  10, "Delaware"),
    ("AZ",   5,   2, "Arizona"),
    ("NM",   5,   3, "New Mexico"),
    ("KS",   5,   4, "Kansas"),
    ("AR",   5,   5, "Arkansas"),
    ("TN",   5,   6, "Tennessee"),
    ("NC",   5,   7, "North Carolina"),
    ("SC",   5,   8, "South Carolina"),
    ("DC",   5,   9, "District of Columbia"),
    ("AK",   6,   0, "Alaska"),
    ("OK",   6,   4, "Oklahoma"),
    ("LA",   6,   5, "Louisiana"),
    ("MS",   6,   6, "Mississippi"),
    ("AL",   6,   7, "Alabama"),
    ("GA",   6,   8, "Georgia"),
    ("HI",   7,   0, "Hawaii"),
    ("TX",   7,   4, "Texas"),
    ("FL",   7,   9, "Florida"),
    # Territories (shown only when ShowTerritories=true)
    ("GU",   6,   1, "Guam"),
    ("AS",   7,   1, "American Samoa"),
    ("TR",   7,   2, "Trust Territory"),   # historical; layout slot kept
    ("PR",   6,  11, "Puerto Rico"),
    ("VI",   7,  11, "Virgin Islands"),
]

TERRITORY_CODES = {"GU", "AS", "TR", "PR", "VI"}

# Additional names for matching (endonyms, historical, etc.)
US_EXTRA_NAMES = {
    "DC": ["Washington DC", "Washington D.C.", "Washington, D.C."],
    "PR": ["Puerto Rico"],
    "VI": ["US Virgin Islands", "U.S. Virgin Islands"],
    "GU": [],
    "AS": [],
    "TR": ["Trust Territory of the Pacific Islands"],
}

us_grid = []
for code, row, col, name in US_TILES:
    names = [name]
    if code in US_EXTRA_NAMES:
        names += US_EXTRA_NAMES[code]
    entry = {"code": code, "row": row, "col": col, "names": names}
    if code in TERRITORY_CODES:
        entry["territory"] = True
    us_grid.append(entry)

out = GRIDS_DIR / "us-states.json"
out.write_text(json.dumps(us_grid, ensure_ascii=False, indent=2))
print(f"Wrote {out} ({len(us_grid)} tiles)")


# ── World ─────────────────────────────────────────────────────────────────────
# Source: data/world_tile_grid.json  (Maarten Lambrechts / BBC)
# coordinates = [col_1idx, row_1idx]

WORLD_SOURCE = REPO / "data" / "world_tile_grid.json"
raw = json.loads(WORLD_SOURCE.read_text())

# Extra names per alpha-2: endonyms, exonyms, historical codes, abbreviations.
# The official English name (from world_tile_grid.json) and alpha-3 are added
# automatically; only put additional strings here.
EXTRA_NAMES = {
    # ── Historical codes ──────────────────────────────────────────────────────
    "RU": ["SU", "USSR", "Soviet Union", "Россия", "Rossiya"],
    "RS": ["YU", "Yugoslavia", "Србија", "Srbija"],
    "CZ": ["CS", "CSK", "Czechoslovakia", "Czechia", "Česká republika", "Česko"],
    "DE": ["DD", "DDR", "East Germany", "West Germany",
           "Deutschland", "Allemagne", "Alemania", "Germania"],
    "CD": ["ZR", "ZAR", "Zaire", "Congo-Kinshasa"],
    "MM": ["BU", "BUR", "Burma", "မြန်မာ"],
    "TL": ["TP", "TMP", "East Timor", "Timor Leste"],
    "CW": ["AN", "ANT", "Netherlands Antilles"],
    "YE": ["YD", "South Yemen", "اليمن"],
    "VN": ["VD", "South Vietnam", "Việt Nam", "Viet Nam"],
    "ZW": ["RH", "Rhodesia", "Southern Rhodesia", "Zimbabwe Rhodesia"],
    "VU": ["NH", "New Hebrides"],
    "KI": ["CT", "Canton Island"],
    "PA": ["PZ", "Panama Canal Zone", "Panamá"],
    "SA": ["NT", "Arabia Saudita", "المملكة العربية السعودية", "KSA"],
    # ── UK constituent nations ────────────────────────────────────────────────
    "GB": ["UK", "ENG", "SCO", "WAL", "WLS", "NIR",
           "England", "Scotland", "Wales", "Northern Ireland",
           "United Kingdom", "Britain", "Great Britain"],
    # ── Endonyms & exonyms (Europe) ───────────────────────────────────────────
    "AT": ["Österreich", "Autriche", "Austria"],
    "BE": ["België", "Belgique", "Belgien"],
    "BG": ["България", "Bălgariya", "Bulgarie"],
    "BY": ["Беларусь", "Belarus", "Biélorussie"],
    "CH": ["Schweiz", "Suisse", "Svizzera", "Svizra", "Switzerland"],
    "DK": ["Danmark", "Dänemark", "Danemark"],
    "EE": ["Eesti", "Estonie"],
    "EL": ["Ελλάδα", "Hellas", "Greece", "Grèce"],  # EL is also used for Greece
    "GR": ["Ελλάδα", "Hellas", "Grèce", "Grecia"],
    "ES": ["España", "Espagne", "Spanien"],
    "FI": ["Suomi", "Finlande", "Finnland"],
    "FR": ["République française", "Frankreich", "Francia"],
    "HR": ["Hrvatska", "Croatie"],
    "HU": ["Magyarország", "Hongrie", "Ungarn"],
    "IE": ["Éire", "Ireland"],
    "IT": ["Italia", "Italie", "Italien"],
    "LT": ["Lietuva", "Lituanie"],
    "LV": ["Latvija", "Lettonie"],
    "MK": ["Македонија", "Severna Makedonija", "North Macedonia"],
    "NL": ["Nederland", "Holland", "Pays-Bas", "Niederlande"],
    "NO": ["Norge", "Noreg", "Norvège"],
    "PL": ["Polska", "Pologne"],
    "PT": ["Portugal", "Portogallo"],
    "RO": ["România", "Roumanie"],
    "SE": ["Sverige", "Suède", "Schweden"],
    "SI": ["Slovenija", "Slovénie"],
    "SK": ["Slovensko", "Slovaquie"],
    "UA": ["Україна", "Ukrayina", "Ucrania"],
    "BA": ["Bosna i Hercegovina", "Bosnia"],
    "MD": ["Moldova", "Молдова"],
    "ME": ["Crna Gora", "Montenegro"],
    "AL": ["Shqipëria", "Albanien"],
    "LU": ["Lëtzebuerg", "Luxembourg", "Luxemburg"],
    "MT": ["Repubblika ta' Malta"],
    "IS": ["Ísland"],
    "MK": ["Севeрна Македонија"],
    "GE": ["საქართველო", "Sakartvelo"],
    "AM": ["Հայաստան", "Hayastan"],
    "AZ": ["Azərbaycan"],
    # ── Endonyms & exonyms (Americas) ────────────────────────────────────────
    "US": ["USA", "United States", "United States of America",
           "América", "Amérique", "Estados Unidos"],
    "CA": ["Canada", "Kanada"],
    "MX": ["México", "Mexique", "Mejico"],
    "BR": ["Brasil", "Brésil"],
    "AR": ["Argentina", "Argentine"],
    "CO": ["Colombia", "Colombie"],
    "CL": ["Chile", "Chili"],
    "PE": ["Perú", "Pérou"],
    "VE": ["Venezuela", "Vénézuéla"],
    "EC": ["Ecuador", "Équateur"],
    "BO": ["Bolivia", "Bolivie", "Estado Plurinacional de Bolivia"],
    "PY": ["Paraguay"],
    "UY": ["Uruguay"],
    "CU": ["Cuba"],
    "DO": ["República Dominicana"],
    "GT": ["Guatemala"],
    "HN": ["Honduras"],
    "SV": ["El Salvador"],
    "NI": ["Nicaragua"],
    "CR": ["Costa Rica"],
    # ── Endonyms & exonyms (Asia) ─────────────────────────────────────────────
    "CN": ["China", "中国", "Zhongguo", "Chine", "República Popular China", "PRC"],
    "JP": ["日本", "Nihon", "Nippon", "Japon", "Japón"],
    "KR": ["한국", "대한민국", "South Korea", "Republic of Korea"],
    "KP": ["조선", "North Korea", "Democratic People's Republic of Korea", "DPRK"],
    "IN": ["भारत", "Bhārat", "Inde", "Indien"],
    "PK": ["پاکستان", "Pakistan"],
    "BD": ["বাংলাদেশ", "Bāṃlādēś"],
    "LK": ["ශ්‍රී ලංකාව", "இலங்கை", "Sri Lanka", "Ceylon"],
    "NP": ["नेपाल", "Nepāl"],
    "AF": ["افغانستان", "Afghānistān"],
    "IR": ["ایران", "Irān", "Persia"],
    "IQ": ["العراق", "Al-ʿIrāq"],
    "SA": ["المملكة العربية السعودية"],
    "AE": ["الإمارات العربية المتحدة", "UAE", "Emirates"],
    "TR": ["Türkiye", "Turquie", "Turchia"],
    "SY": ["سوريا", "Syria"],
    "IL": ["ישראל", "Yisra'el", "Israel"],
    "JO": ["الأردن", "Al-Urdun"],
    "LB": ["لبنان", "Lubnān"],
    "KW": ["الكويت", "Al-Kuwayt"],
    "QA": ["قطر", "Qaṭar"],
    "BH": ["البحرين", "Al-Baḥrayn"],
    "OM": ["عُمان", "ʿUmān"],
    "YE": ["اليمن"],
    "ID": ["Indonesia", "Indonésie"],
    "MY": ["Malaysia", "Malaisie"],
    "TH": ["ประเทศไทย", "Thaïlande"],
    "VN": ["Việt Nam", "Viet Nam"],
    "PH": ["Pilipinas", "Philippines"],
    "SG": ["Singapura", "新加坡", "Singapore"],
    "KH": ["កម្ពុជា", "Kâmpŭchéa", "Cambodia"],
    "LA": ["ລາວ", "Laos"],
    "MN": ["Монгол улс", "Mongolia"],
    "KZ": ["Қазақстан", "Qazaqstan"],
    "UZ": ["O'zbekiston", "Uzbekistan"],
    "TM": ["Türkmenistan", "Turkmenistan"],
    "TJ": ["Тоҷикистон", "Tajikistan"],
    "KG": ["Кыргызстан", "Kyrgyzstan"],
    "AU": ["Australia", "Australie", "Australien"],
    "NZ": ["Aotearoa", "New Zealand"],
    # ── Endonyms & exonyms (Africa & Middle East) ─────────────────────────────
    "EG": ["مصر", "Miṣr", "Égypte"],
    "MA": ["المغرب", "Al-Maġrib", "Maroc", "Marruecos"],
    "DZ": ["الجزائر", "Al-Jazāʾir", "Algérie"],
    "TN": ["تونس", "Tūnis", "Tunisie"],
    "LY": ["ليبيا", "Lībiyā"],
    "ET": ["ኢትዮጵያ", "ʾĪtyōṗṗyā", "Éthiopie"],
    "NG": ["Nigeria", "Nigéria"],
    "ZA": ["South Africa", "Suid-Afrika", "Afrique du Sud",
           "iNingizimu Afrika", "Afrika Borwa"],
    "KE": ["Kenya"],
    "TZ": ["Tanzania", "Tanzanie"],
    "GH": ["Ghana"],
    "CM": ["Cameroun", "Cameroon"],
    "CI": ["Côte d'Ivoire", "Ivory Coast"],
    "SN": ["Sénégal", "Senegal"],
    "MZ": ["Moçambique", "Mozambique"],
    "AO": ["Angola"],
    "ZM": ["Zambia", "Zambie"],
    "SO": ["Soomaaliya", "Somalia"],
    "SD": ["السودان", "As-Sūdān"],
    "SS": ["South Sudan", "Soudan du Sud"],
    "UG": ["Uganda", "Ouganda"],
    "RW": ["Rwanda", "Urwanda"],
    "MG": ["Madagasikara", "Madagascar"],
}

# Build a lookup from alpha-2 → index in raw
a2_to_raw = {r["alpha-2"]: r for r in raw}

world_grid = []
for r in raw:
    a2   = r["alpha-2"]
    a3   = r.get("alpha-3", "")
    name = r["name"]
    col  = r["coordinates"][0] - 1   # 1-indexed → 0-indexed
    row  = r["coordinates"][1] - 1

    names_raw = [name]
    if a3:
        names_raw.append(a3)
    if a2 in EXTRA_NAMES:
        names_raw += EXTRA_NAMES[a2]
    # Deduplicate preserving order
    seen = set()
    names = []
    for n in names_raw:
        key = n.strip().upper()
        if key not in seen:
            seen.add(key)
            names.append(n)

    entry = {"code": a2, "row": row, "col": col, "names": names}
    world_grid.append(entry)

out = GRIDS_DIR / "world.json"
out.write_text(json.dumps(world_grid, ensure_ascii=False, indent=2))
print(f"Wrote {out} ({len(world_grid)} tiles)")


# ── Helper: write a grid JSON ─────────────────────────────────────────────────
def write_grid(name, tiles):
    """tiles: list of (code, row, col, names_list, territory=False)"""
    entries = []
    for t in tiles:
        code, row, col, names = t[0], t[1], t[2], t[3]
        territory = t[4] if len(t) > 4 else False
        e = {"code": code, "row": row, "col": col, "names": names}
        if territory:
            e["territory"] = True
        entries.append(e)
    path = GRIDS_DIR / f"{name}.json"
    path.write_text(json.dumps(entries, ensure_ascii=False, indent=2))
    print(f"Wrote {path} ({len(entries)} tiles)")


# ── Canada (ca-provinces) ─────────────────────────────────────────────────────
# 10 provinces + 3 territories
write_grid("ca-provinces", [
    # code  row  col  names
    ("YT",  0, 0, ["Yukon", "Yukon Territory"]),
    ("NT",  0, 1, ["Northwest Territories", "NWT"]),
    ("NU",  0, 2, ["Nunavut"]),
    ("BC",  1, 0, ["British Columbia", "Colombie-Britannique"]),
    ("AB",  1, 1, ["Alberta"]),
    ("SK",  1, 2, ["Saskatchewan"]),
    ("MB",  1, 3, ["Manitoba"]),
    ("ON",  1, 4, ["Ontario"]),
    ("QC",  1, 5, ["Quebec", "Québec"]),
    ("NL",  1, 6, ["Newfoundland and Labrador", "Newfoundland", "Labrador",
                    "Terre-Neuve-et-Labrador"]),
    ("NB",  2, 5, ["New Brunswick", "Nouveau-Brunswick"]),
    ("NS",  3, 5, ["Nova Scotia", "Nouvelle-Écosse"]),
    ("PE",  3, 6, ["Prince Edward Island", "PEI", "Île-du-Prince-Édouard"]),
])

# ── Australia (au-states) ─────────────────────────────────────────────────────
write_grid("au-states", [
    ("WA",  0, 0, ["Western Australia"]),
    ("NT",  0, 1, ["Northern Territory"]),
    ("QLD", 0, 2, ["Queensland"]),
    ("SA",  1, 1, ["South Australia"]),
    ("NSW", 1, 2, ["New South Wales"]),
    ("TAS", 2, 0, ["Tasmania"]),
    ("VIC", 2, 1, ["Victoria"]),
    ("ACT", 2, 2, ["Australian Capital Territory", "Canberra"]),
])

# ── Germany — Bundesländer (de-states) ───────────────────────────────────────
write_grid("de-states", [
    ("SH",  0, 1, ["Schleswig-Holstein"]),
    ("HH",  1, 0, ["Hamburg"]),
    ("MV",  1, 2, ["Mecklenburg-Vorpommern", "Mecklenburg"]),
    ("HB",  2, 0, ["Bremen"]),
    ("NI",  2, 1, ["Niedersachsen", "Lower Saxony"]),
    ("BB",  2, 2, ["Brandenburg"]),
    ("BE",  2, 3, ["Berlin"]),
    ("NW",  3, 0, ["Nordrhein-Westfalen", "North Rhine-Westphalia", "NRW"]),
    ("ST",  3, 1, ["Sachsen-Anhalt", "Saxony-Anhalt"]),
    ("SN",  3, 2, ["Sachsen", "Saxony"]),
    ("SL",  4, 0, ["Saarland"]),
    ("HE",  4, 1, ["Hessen", "Hesse"]),
    ("TH",  4, 2, ["Thüringen", "Thuringia"]),
    ("BY",  4, 3, ["Bayern", "Bavaria"]),
    ("RP",  5, 0, ["Rheinland-Pfalz", "Rhineland-Palatinate"]),
    ("BW",  5, 1, ["Baden-Württemberg", "Baden-Wuerttemberg"]),
])

# ── UK — nations + Crown dependencies (gb-nations) ───────────────────────────
write_grid("gb-nations", [
    ("SCO", 0, 1, ["Scotland", "Alba"]),
    ("NIR", 1, 0, ["Northern Ireland"]),
    ("ENG", 1, 1, ["England"]),
    ("WAL", 2, 0, ["Wales", "Cymru"]),
])

# ── India — states + union territories (in-states) ────────────────────────────
# Using short codes; ISO 3166-2:IN prefixes (IN-MH etc.) also in names
write_grid("in-states", [
    # row 0: J&K, HP, UK, Arunachal, Assam, Nagaland, Manipur, Arunachal is far east
    ("JK",  0, 0, ["Jammu and Kashmir", "Jammu & Kashmir", "IN-JK"]),
    ("HP",  0, 1, ["Himachal Pradesh", "IN-HP"]),
    ("UK",  0, 2, ["Uttarakhand", "Uttaranchal", "IN-UT"]),
    ("UP",  0, 3, ["Uttar Pradesh", "IN-UP"]),
    ("BR",  0, 4, ["Bihar", "IN-BR"]),
    ("WB",  0, 5, ["West Bengal", "IN-WB"]),
    ("SK",  0, 6, ["Sikkim", "IN-SK"]),
    ("AR",  0, 7, ["Arunachal Pradesh", "IN-AR"]),
    ("AS",  1, 6, ["Assam", "IN-AS"]),
    ("NL",  1, 7, ["Nagaland", "IN-NL"]),
    ("MN",  2, 7, ["Manipur", "IN-MN"]),
    ("ML",  2, 6, ["Meghalaya", "IN-ML"]),
    ("TR",  2, 5, ["Tripura", "IN-TR"]),
    ("MZ",  3, 7, ["Mizoram", "IN-MZ"]),
    ("PB",  1, 0, ["Punjab", "IN-PB"]),
    ("HR",  1, 1, ["Haryana", "IN-HR"]),
    ("DL",  1, 2, ["Delhi", "NCT", "IN-DL", "National Capital Territory"]),
    ("RJ",  1, 3, ["Rajasthan", "Rajputana", "IN-RJ"]),
    ("MP",  1, 4, ["Madhya Pradesh", "IN-MP"]),
    ("JH",  1, 5, ["Jharkhand", "IN-JH"]),
    ("OD",  2, 4, ["Odisha", "Orissa", "IN-OR"]),
    ("CG",  2, 3, ["Chhattisgarh", "IN-CT"]),
    ("GJ",  2, 1, ["Gujarat", "IN-GJ"]),
    ("MH",  2, 2, ["Maharashtra", "IN-MH"]),
    ("TS",  3, 3, ["Telangana", "IN-TG"]),
    ("AP",  3, 4, ["Andhra Pradesh", "IN-AP"]),
    ("KA",  3, 2, ["Karnataka", "IN-KA"]),
    ("GA",  3, 1, ["Goa", "IN-GA"]),
    ("TN",  4, 3, ["Tamil Nadu", "IN-TN"]),
    ("KL",  4, 2, ["Kerala", "IN-KL"]),
    ("LA",  0, -1, ["Ladakh", "IN-LA"], True),   # territory, col=-1 → overflow
    ("CH",  1, -1, ["Chandigarh", "IN-CH"], True),
    ("PY",  4, 4, ["Puducherry", "Pondicherry", "IN-PY"], True),
    ("AN",  4, 5, ["Andaman and Nicobar Islands", "A&N Islands", "IN-AN"], True),
    ("DN",  3, 0, ["Dadra and Nagar Haveli and Daman and Diu", "DNHDD", "IN-DH"], True),
    ("LD",  4, 1, ["Lakshadweep", "IN-LD"], True),
])

# ── Brazil (br-states) ────────────────────────────────────────────────────────
write_grid("br-states", [
    ("AM",  0, 1, ["Amazonas"]),
    ("RR",  0, 2, ["Roraima"]),
    ("AP",  0, 3, ["Amapá"]),
    ("PA",  1, 2, ["Pará"]),
    ("MA",  1, 3, ["Maranhão"]),
    ("CE",  1, 4, ["Ceará"]),
    ("RN",  1, 5, ["Rio Grande do Norte"]),
    ("AC",  1, 0, ["Acre"]),
    ("RO",  2, 0, ["Rondônia"]),
    ("MT",  2, 1, ["Mato Grosso"]),
    ("TO",  2, 2, ["Tocantins"]),
    ("PI",  2, 3, ["Piauí"]),
    ("PB",  2, 5, ["Paraíba"]),
    ("PE",  2, 4, ["Pernambuco"]),
    ("AL",  3, 4, ["Alagoas"]),
    ("SE",  3, 5, ["Sergipe"]),
    ("BA",  3, 3, ["Bahia"]),
    ("DF",  3, 2, ["Distrito Federal", "Brasília"]),
    ("GO",  3, 1, ["Goiás"]),
    ("MS",  3, 0, ["Mato Grosso do Sul"]),
    ("MG",  4, 3, ["Minas Gerais"]),
    ("ES",  4, 4, ["Espírito Santo"]),
    ("RJ",  5, 4, ["Rio de Janeiro"]),
    ("SP",  4, 2, ["São Paulo"]),
    ("PR",  5, 2, ["Paraná"]),
    ("SC",  5, 3, ["Santa Catarina"]),
    ("RS",  6, 3, ["Rio Grande do Sul"]),
])

# ── South Africa (za-provinces) ──────────────────────────────────────────────
write_grid("za-provinces", [
    ("NC",  0, 0, ["Northern Cape"]),
    ("NW",  0, 1, ["North West"]),
    ("LP",  0, 2, ["Limpopo"]),
    ("WC",  1, 0, ["Western Cape"]),
    ("FS",  1, 1, ["Free State"]),
    ("GP",  1, 2, ["Gauteng", "GT"]),
    ("MP",  1, 3, ["Mpumalanga"]),
    ("EC",  2, 1, ["Eastern Cape"]),
    ("KZN", 2, 2, ["KwaZulu-Natal", "KZN"]),
])

# ── France — metropolitan regions (fr-regions) ────────────────────────────────
write_grid("fr-regions", [
    ("HDF", 0, 1, ["Hauts-de-France", "Nord-Pas-de-Calais"]),
    ("NOR", 0, 2, ["Normandie", "Normandy"]),
    ("BRE", 0, 3, ["Bretagne", "Brittany"]),
    ("IDF", 1, 2, ["Île-de-France", "Paris"]),
    ("GES", 1, 3, ["Grand Est", "Alsace-Lorraine"]),
    ("PDL", 1, 1, ["Pays de la Loire"]),
    ("CVL", 1, 4, ["Centre-Val de Loire"]),
    ("BFC", 2, 3, ["Bourgogne-Franche-Comté", "Burgundy"]),
    ("NAQ", 2, 1, ["Nouvelle-Aquitaine", "Aquitaine"]),
    ("ARA", 2, 2, ["Auvergne-Rhône-Alpes"]),
    ("OCC", 3, 2, ["Occitanie", "Languedoc"]),
    ("PAC", 3, 3, ["Provence-Alpes-Côte d'Azur", "PACA"]),
    ("COR", 3, 4, ["Corse", "Corsica"], True),
])

# ── Italy (it-regions) ────────────────────────────────────────────────────────
write_grid("it-regions", [
    ("VDA", 0, 0, ["Valle d'Aosta", "Aosta Valley"]),
    ("PIE", 0, 1, ["Piemonte", "Piedmont"]),
    ("LOM", 0, 2, ["Lombardia", "Lombardy"]),
    ("TAA", 0, 3, ["Trentino-Alto Adige", "Trentino"]),
    ("VEN", 0, 4, ["Veneto"]),
    ("FVG", 0, 5, ["Friuli-Venezia Giulia", "Friuli"]),
    ("LIG", 1, 0, ["Liguria"]),
    ("EMR", 1, 2, ["Emilia-Romagna", "Emilia"]),
    ("TOS", 2, 1, ["Toscana", "Tuscany"]),
    ("MAR", 2, 3, ["Marche"]),
    ("UMB", 2, 2, ["Umbria"]),
    ("LAZ", 3, 2, ["Lazio", "Latium"]),
    ("ABR", 3, 3, ["Abruzzo"]),
    ("MOL", 3, 4, ["Molise"]),
    ("CAM", 4, 2, ["Campania"]),
    ("PUG", 4, 4, ["Puglia", "Apulia"]),
    ("BAS", 4, 3, ["Basilicata"]),
    ("CAL", 5, 3, ["Calabria"]),
    ("SIC", 5, 2, ["Sicilia", "Sicily"]),
    ("SAR", 4, 0, ["Sardegna", "Sardinia"]),
])

# ── Spain — autonomous communities (es-regions) ───────────────────────────────
write_grid("es-regions", [
    ("GAL", 0, 0, ["Galicia", "Galiza"]),
    ("AST", 0, 1, ["Asturias"]),
    ("CNT", 0, 2, ["Cantabria"]),
    ("PVA", 0, 3, ["País Vasco", "Basque Country", "Euskadi"]),
    ("NAV", 0, 4, ["Navarra", "Navarre"]),
    ("RIO", 0, 5, ["La Rioja"]),
    ("ARA", 1, 4, ["Aragón", "Aragon"]),
    ("CAT", 1, 5, ["Cataluña", "Catalunya", "Catalonia"]),
    ("CYL", 1, 1, ["Castilla y León", "Castile and León"]),
    ("MAD", 1, 2, ["Comunidad de Madrid", "Madrid"]),
    ("CLM", 2, 2, ["Castilla-La Mancha", "Castile-La Mancha"]),
    ("EXT", 2, 1, ["Extremadura"]),
    ("VAL", 2, 4, ["Comunitat Valenciana", "Valencia"]),
    ("MUR", 3, 4, ["Región de Murcia", "Murcia"]),
    ("AND", 3, 2, ["Andalucía", "Andalusia"]),
    ("IBA", 3, 5, ["Illes Balears", "Balearic Islands", "Baleares"]),
    ("CAN", 3, 0, ["Canarias", "Canary Islands"], True),
])

# ── Mexico (mx-states) ────────────────────────────────────────────────────────
write_grid("mx-states", [
    ("BC",  0, 0, ["Baja California"]),
    ("SON", 0, 1, ["Sonora"]),
    ("CHI", 0, 2, ["Chihuahua"]),
    ("COA", 0, 3, ["Coahuila"]),
    ("NUL", 0, 4, ["Nuevo León"]),
    ("TAM", 0, 5, ["Tamaulipas"]),
    ("BCS", 1, 0, ["Baja California Sur"]),
    ("SIN", 1, 1, ["Sinaloa"]),
    ("DUR", 1, 2, ["Durango"]),
    ("ZAC", 1, 3, ["Zacatecas"]),
    ("SLP", 1, 4, ["San Luis Potosí"]),
    ("VER", 1, 5, ["Veracruz"]),
    ("NAY", 2, 1, ["Nayarit"]),
    ("JAL", 2, 2, ["Jalisco"]),
    ("AGS", 2, 3, ["Aguascalientes"]),
    ("GTO", 2, 4, ["Guanajuato"]),
    ("QRO", 2, 5, ["Querétaro"]),
    ("HID", 2, 6, ["Hidalgo"]),
    ("COL", 3, 1, ["Colima"]),
    ("MIC", 3, 2, ["Michoacán"]),
    ("MEX", 3, 3, ["Estado de México", "State of Mexico"]),
    ("CDMX",3, 4, ["Ciudad de México", "Mexico City", "DF", "Distrito Federal"]),
    ("MOR", 3, 5, ["Morelos"]),
    ("PUE", 3, 6, ["Puebla"]),
    ("TLX", 3, 7, ["Tlaxcala"]),
    ("GRO", 4, 2, ["Guerrero"]),
    ("OAX", 4, 4, ["Oaxaca"]),
    ("VER", 4, 5, ["Veracruz"]),
    ("TAB", 4, 6, ["Tabasco"]),
    ("CHP", 5, 4, ["Chiapas"]),
    ("CAM", 5, 6, ["Campeche"]),
    ("YUC", 5, 7, ["Yucatán"]),
    ("ROO", 5, 8, ["Quintana Roo"]),
])

# ── Argentina (ar-provinces) ──────────────────────────────────────────────────
write_grid("ar-provinces", [
    ("JUJ", 0, 0, ["Jujuy"]),
    ("SAL", 0, 1, ["Salta"]),
    ("FOR", 0, 3, ["Formosa"]),
    ("CHA", 0, 4, ["Chaco"]),
    ("MIS", 0, 5, ["Misiones"]),
    ("TUC", 1, 1, ["Tucumán", "Tucuman"]),
    ("SDE", 1, 2, ["Santiago del Estero"]),
    ("SGO", 1, 2, ["Santiago del Estero"]),  # duplicate name
    ("CAT", 1, 0, ["Catamarca"]),
    ("COR", 1, 4, ["Corrientes"]),
    ("ERR", 1, 5, ["Entre Ríos"]),
    ("LRI", 2, 0, ["La Rioja"]),
    ("SJU", 2, 1, ["San Juan"]),
    ("CBA", 2, 3, ["Córdoba"]),
    ("SFE", 2, 4, ["Santa Fe"]),
    ("BAI", 3, 2, ["Buenos Aires"]),   # Province
    ("CABA",3, 3, ["CABA", "Ciudad Autónoma de Buenos Aires", "Ciudad de Buenos Aires"]),
    ("MZA", 2, 2, ["Mendoza"]),
    ("SLU", 3, 1, ["San Luis"]),
    ("LPA", 3, 0, ["La Pampa"]),
    ("RNE", 4, 0, ["Río Negro"]),
    ("NEU", 4, 1, ["Neuquén"]),
    ("CHU", 5, 1, ["Chubut"]),
    ("SCR", 6, 1, ["Santa Cruz"]),
    ("TDF", 7, 1, ["Tierra del Fuego"]),
])

# ── South Korea (kr-regions) ─────────────────────────────────────────────────
write_grid("kr-regions", [
    ("GG",  0, 0, ["Gyeonggi", "Gyeonggi-do"]),
    ("IC",  0, 1, ["Incheon", "Incheon Metropolitan City"]),
    ("SE",  0, 2, ["Seoul", "서울", "Seoul Special City"]),
    ("GW",  0, 3, ["Gangwon", "Gangwon-do"]),
    ("CB",  1, 0, ["Chungcheongbuk-do", "North Chungcheong", "Chungbuk"]),
    ("CN",  1, 1, ["Daejeon", "대전"]),
    ("SJ",  1, 2, ["Sejong", "세종", "Sejong City"]),
    ("GB",  1, 3, ["Gyeongsangbuk-do", "North Gyeongsang", "Gyeongbuk"]),
    ("DG",  1, 4, ["Daegu", "대구"]),
    ("CN2", 2, 0, ["Chungcheongnam-do", "South Chungcheong", "Chungnam"]),
    ("JB",  2, 1, ["Jeollabuk-do", "North Jeolla", "Jeonbuk"]),
    ("GN",  2, 3, ["Gyeongsangnam-do", "South Gyeongsang", "Gyeongnam"]),
    ("US",  2, 4, ["Ulsan", "울산"]),
    ("BS",  2, 5, ["Busan", "부산"]),
    ("JN",  3, 1, ["Jeollanam-do", "South Jeolla", "Jeonnam"]),
    ("GJ",  3, 2, ["Gwangju", "광주"]),
    ("JJ",  3, 3, ["Jeju", "제주", "Jeju Island", "Jeju-do"]),
])

# ── Japan (jp-prefectures) ────────────────────────────────────────────────────
# 47 prefectures arranged roughly north→south
write_grid("jp-prefectures", [
    # Hokkaido
    ("HKD", 0, 0, ["Hokkaido", "北海道"]),
    # Tohoku
    ("AOM", 1, 1, ["Aomori", "青森"]),
    ("IWT", 1, 2, ["Iwate", "岩手"]),
    ("MYG", 1, 3, ["Miyagi", "宮城"]),
    ("AKT", 2, 1, ["Akita", "秋田"]),
    ("YGT", 2, 2, ["Yamagata", "山形"]),
    ("FKS", 2, 3, ["Fukushima", "福島"]),
    # Kanto
    ("IBR", 3, 3, ["Ibaraki", "茨城"]),
    ("TCG", 3, 4, ["Tochigi", "栃木"]),
    ("GNM", 3, 5, ["Gunma", "群馬"]),
    ("STM", 3, 6, ["Saitama", "埼玉"]),
    ("CHB", 4, 6, ["Chiba", "千葉"]),
    ("TKY", 3, 7, ["Tokyo", "東京", "Tōkyō"]),
    ("KNG", 4, 7, ["Kanagawa", "神奈川"]),
    # Chubu
    ("NGT", 2, 4, ["Niigata", "新潟"]),
    ("TYM", 3, 2, ["Toyama", "富山"]),
    ("ISK", 3, 1, ["Ishikawa", "石川"]),
    ("FKI", 4, 1, ["Fukui", "福井"]),
    ("YMN", 4, 5, ["Yamanashi", "山梨"]),
    ("NGN", 4, 4, ["Nagano", "長野"]),
    ("SZK", 5, 5, ["Shizuoka", "静岡"]),
    ("AIC", 5, 4, ["Aichi", "愛知"]),
    ("GIF", 4, 3, ["Gifu", "岐阜"]),
    # Kinki/Kansai
    ("MIE", 5, 3, ["Mie", "三重"]),
    ("SIG", 4, 2, ["Shiga", "滋賀"]),
    ("KYT", 5, 2, ["Kyoto", "京都", "Kyōto"]),
    ("OSK", 5, 1, ["Osaka", "大阪", "Ōsaka"]),
    ("HYG", 5, 0, ["Hyogo", "兵庫"]),
    ("NAR", 6, 2, ["Nara", "奈良"]),
    ("WKY", 6, 1, ["Wakayama", "和歌山"]),
    # Chugoku
    ("TTR", 5, -1, ["Tottori", "鳥取"]),
    ("SMN", 6, 0, ["Shimane", "島根"]),
    ("OKY", 6, 3, ["Okayama", "岡山"]),
    ("HRS", 6, 4, ["Hiroshima", "広島"]),
    ("YMG", 6, 5, ["Yamaguchi", "山口"]),
    # Shikoku
    ("TKS", 7, 3, ["Tokushima", "徳島"]),
    ("KGW", 7, 4, ["Kagawa", "香川"]),
    ("EHM", 7, 2, ["Ehime", "愛媛"]),
    ("KCI", 7, 5, ["Kochi", "高知"]),
    # Kyushu
    ("FKO", 7, 6, ["Fukuoka", "福岡"]),
    ("SAG", 8, 5, ["Saga", "佐賀"]),
    ("NGS", 8, 4, ["Nagasaki", "長崎"]),
    ("KMM", 8, 6, ["Kumamoto", "熊本"]),
    ("OIT", 8, 7, ["Oita", "大分"]),
    ("MYZ", 9, 6, ["Miyazaki", "宮崎"]),
    ("KGS", 9, 5, ["Kagoshima", "鹿児島"]),
    # Okinawa
    ("OKN", 9, 3, ["Okinawa", "沖縄"]),
])

# ── Languages ─────────────────────────────────────────────────────────────────
# ISO 639-1 two-letter codes, arranged loosely by language family.
# Layout: rows = family groups, cols = individual languages.
# This is conceptual, not geographic.
write_grid("languages", [
    # Germanic (row 0)
    ("en",  0, 0, ["English"]),
    ("de",  0, 1, ["German", "Deutsch"]),
    ("nl",  0, 2, ["Dutch", "Nederlands", "Flemish"]),
    ("sv",  0, 3, ["Swedish", "Svenska"]),
    ("no",  0, 4, ["Norwegian", "Norsk"]),
    ("da",  0, 5, ["Danish", "Dansk"]),
    ("is",  0, 6, ["Icelandic", "Íslenska"]),
    ("af",  0, 7, ["Afrikaans"]),
    # Romance (row 1)
    ("fr",  1, 0, ["French", "Français"]),
    ("es",  1, 1, ["Spanish", "Español", "Castellano"]),
    ("pt",  1, 2, ["Portuguese", "Português"]),
    ("it",  1, 3, ["Italian", "Italiano"]),
    ("ro",  1, 4, ["Romanian", "Română"]),
    ("ca",  1, 5, ["Catalan", "Català"]),
    ("gl",  1, 6, ["Galician", "Galego"]),
    ("la",  1, 7, ["Latin", "Latina"]),
    # Slavic (row 2)
    ("ru",  2, 0, ["Russian", "Русский"]),
    ("pl",  2, 1, ["Polish", "Polski"]),
    ("cs",  2, 2, ["Czech", "Čeština"]),
    ("sk",  2, 3, ["Slovak", "Slovenčina"]),
    ("bg",  2, 4, ["Bulgarian", "Български"]),
    ("hr",  2, 5, ["Croatian", "Hrvatski"]),
    ("sr",  2, 6, ["Serbian", "Српски", "Srpski"]),
    ("sl",  2, 7, ["Slovenian", "Slovenščina"]),
    ("uk",  2, 8, ["Ukrainian", "Українська"]),
    ("be",  2, 9, ["Belarusian", "Беларуская"]),
    # Other European (row 3)
    ("el",  3, 0, ["Greek", "Ελληνικά"]),
    ("fi",  3, 1, ["Finnish", "Suomi"]),
    ("hu",  3, 2, ["Hungarian", "Magyar"]),
    ("et",  3, 3, ["Estonian", "Eesti"]),
    ("lv",  3, 4, ["Latvian", "Latviešu"]),
    ("lt",  3, 5, ["Lithuanian", "Lietuvių"]),
    ("ga",  3, 6, ["Irish", "Gaeilge"]),
    ("eu",  3, 7, ["Basque", "Euskara"]),
    ("cy",  3, 8, ["Welsh", "Cymraeg"]),
    ("mt",  3, 9, ["Maltese", "Malti"]),
    # Semitic (row 4)
    ("ar",  4, 0, ["Arabic", "العربية"]),
    ("he",  4, 1, ["Hebrew", "עברית"]),
    ("am",  4, 2, ["Amharic", "አማርኛ"]),
    ("so",  4, 3, ["Somali", "Soomaali"]),
    # Iranian / Turkic (row 5)
    ("fa",  5, 0, ["Persian", "Farsi", "فارسی"]),
    ("tr",  5, 1, ["Turkish", "Türkçe"]),
    ("az",  5, 2, ["Azerbaijani", "Azərbaycan"]),
    ("kk",  5, 3, ["Kazakh", "Қазақ"]),
    ("uz",  5, 4, ["Uzbek", "O'zbek"]),
    ("ky",  5, 5, ["Kyrgyz", "Кыргыз"]),
    ("tk",  5, 6, ["Turkmen", "Türkmen"]),
    # South Asian (row 6)
    ("hi",  6, 0, ["Hindi", "हिन्दी"]),
    ("ur",  6, 1, ["Urdu", "اردو"]),
    ("bn",  6, 2, ["Bengali", "বাংলা"]),
    ("pa",  6, 3, ["Punjabi", "ਪੰਜਾਬੀ"]),
    ("gu",  6, 4, ["Gujarati", "ગુજરાતી"]),
    ("mr",  6, 5, ["Marathi", "मराठी"]),
    ("ta",  6, 6, ["Tamil", "தமிழ்"]),
    ("te",  6, 7, ["Telugu", "తెలుగు"]),
    ("ml",  6, 8, ["Malayalam", "മലയാളം"]),
    ("kn",  6, 9, ["Kannada", "ಕನ್ನಡ"]),
    ("si",  6, 10, ["Sinhala", "සිංහල"]),
    ("ne",  6, 11, ["Nepali", "नेपाली"]),
    # East / Southeast Asian (row 7)
    ("zh",  7, 0, ["Chinese", "中文", "Mandarin", "Zhongwen", "Putonghua"]),
    ("ja",  7, 1, ["Japanese", "日本語", "Nihongo"]),
    ("ko",  7, 2, ["Korean", "한국어", "조선어"]),
    ("th",  7, 3, ["Thai", "ภาษาไทย"]),
    ("vi",  7, 4, ["Vietnamese", "Tiếng Việt"]),
    ("km",  7, 5, ["Khmer", "ខ្មែរ"]),
    ("lo",  7, 6, ["Lao", "ລາວ"]),
    ("my",  7, 7, ["Burmese", "Myanmar", "မြန်မာ"]),
    ("ms",  7, 8, ["Malay", "Bahasa Melayu"]),
    ("id",  7, 9, ["Indonesian", "Bahasa Indonesia"]),
    ("tl",  7, 10, ["Filipino", "Tagalog"]),
    ("mn",  7, 11, ["Mongolian", "Монгол"]),
    # African (row 8)
    ("sw",  8, 0, ["Swahili", "Kiswahili"]),
    ("yo",  8, 1, ["Yoruba"]),
    ("ig",  8, 2, ["Igbo"]),
    ("ha",  8, 3, ["Hausa"]),
    ("zu",  8, 4, ["Zulu", "isiZulu"]),
    ("xh",  8, 5, ["Xhosa", "isiXhosa"]),
    ("st",  8, 6, ["Sesotho", "Southern Sotho"]),
    ("sn",  8, 7, ["Shona"]),
    # Americas / Pacific (row 9)
    ("qu",  9, 0, ["Quechua", "Runasimi"]),
    ("gu2", 9, 1, ["Guaraní"]),
    ("nah", 9, 2, ["Nahuatl", "Aztec"]),
    ("nv",  9, 3, ["Navajo", "Diné bizaad"]),
    ("mi",  9, 4, ["Māori", "Maori"]),
    ("haw", 9, 5, ["Hawaiian", "ʻŌlelo Hawaiʻi"]),
])

print("Done.")
