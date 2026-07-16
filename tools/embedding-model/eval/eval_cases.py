import re
CASES = [
    ("cramp", "cramp", "noun", "Presently I was seized with a cramp in my stomach.", "painful contraction"),
    ("cramp", "cramp", "noun", "He used a cramp to hold the two boards together while the glue dried.", "clamp"),
    ("bank", "bank", "noun", "They had a picnic on the bank of the river, watching the water flow past.", "edge of river"),
    ("bank", "bank", "noun", "The bank refused to extend the loan after reviewing her credit history.", "place and borrow money"),
    ("bat", "bat", "noun", "He swung the bat hard and sent the ball over the fence.", "striking the ball"),
    ("bat", "bat", "noun", "A bat flew out of the cave at dusk, hunting insects.", "flying mammal"),
    ("spring", "spring", "noun", "They drank cold water from a spring at the foot of the mountain.", "body of water springing"),
    ("spring", "spring", "noun", "The flowers bloom in early spring when the days grow warmer.", "season of the year"),
    ("spring", "springs", "noun", "The old mattress creaked, its rusty springs poking through the fabric.", "elastic mechanical part"),
    ("chest", "chest", "noun", "He kept his tools in a wooden chest by the door.", "strong box"),
    ("chest", "chest", "noun", "The doctor listened to his chest with a stethoscope.", "base of the neck"),
    ("bar", "bar", "noun", "The lawyer was admitted to the bar after passing the exam.", "legal profession"),
    ("bar", "bar", "noun", "They met at a bar downtown for a drink after work.", "alcoholic drinks"),
    ("bar", "bars", "noun", "The prisoner gripped the iron bars of his cell.", "rigid object of metal"),
    ("vessel", "vessel", "noun", "The vessel sailed out of the harbor at dawn.", "craft"),
    ("vessel", "vessels", "noun", "The medication dilates the blood vessels and lowers pressure.", "tube or canal that carries fluid"),
    ("company", "company", "noun", "He enjoyed her company on the long walk home.", "companion"),
    ("company", "company", "noun", "The company reported record profits this quarter.", "business"),
    ("seize", "seized", "verb", "The engine seized after running without oil for an hour.", "lock in position immovably"),
    ("seize", "seized", "verb", "Customs officers seized the smuggled goods at the border.", "take possession"),
]
CITATION_RE = re.compile(r"\d{4}|letter to|page \d", re.I)
def flatten(entry_json):
    out = []
    def walk(sense, pos):
        definition = sense["definition"].strip()
        examples = [e.strip() for e in (sense.get("examples") or []) if 10 < len(e.strip()) < 160 and not CITATION_RE.search(e)]
        quotes = [q["text"].strip() for q in (sense.get("quotes") or []) if 10 < len(q.get("text","").strip()) < 160]
        if definition:
            out.append((pos, definition, examples, quotes))
        for sub in sense.get("subsenses") or []:
            walk(sub, pos)
    for entry in entry_json["entries"]:
        for sense in entry["senses"]:
            walk(sense, entry["partOfSpeech"])
    return out
def pos_matches(detected, candidate):
    d, c = detected.lower(), candidate.lower()
    return c in d or d in c
