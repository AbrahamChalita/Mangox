import re

with open("Mangox/Services/InstagramStoryShare.swift", "r") as f:
    text = f.read()

text = re.sub(r',\s*aiCardTitle:\s*String\?\s*=\s*nil', '', text)
text = re.sub(r',\s*aiCardTitle:\s*aiCardTitle', '', text)

with open("Mangox/Services/InstagramStoryShare.swift", "w") as f:
    f.write(text)
