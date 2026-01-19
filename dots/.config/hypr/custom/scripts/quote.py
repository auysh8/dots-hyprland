import json
import random
import os

# 1. The correct path we found in your config folder
config_path = os.path.expanduser("~/.config/illogical-impulse/config.json")

# 2. Quotes from the Bhagavad Gita
quotes = [
    "Man is made by his belief. As he believes, so he is.",
    "Perform your duty, and leave the rest to God.",
    "Change is the law of the universe.",
    "Calmness is the cradle of power.",
    "A man is his own friend and his own enemy.",
    "Focus on your action, not on the result.",
    "Lust, anger, and greed are the gates to self-destruction.",
    "Knowledge is better than mere ritual.",
    "The soul is never born and never dies.",
    "Work is worship."
]

def push():
    try:
        # Load the config
        with open(config_path, 'r') as f:
            data = json.load(f)

        # Pick a random quote
        new_quote = random.choice(quotes)

        # Update the specific field
        # Targets: background -> widgets -> clock -> quote -> text
        data['background']['widgets']['clock']['quote']['text'] = new_quote

        # Save back to the file
        with open(config_path, 'w') as f:
            json.dump(data, f, indent=4)

        print(f"✅ Updated Quote: \"{new_quote}\"")

    except FileNotFoundError:
        print(f"❌ Error: Config file not found at {config_path}")
    except Exception as e:
        print(f"❌ Error: {e}")

if __name__ == "__main__":
    push()