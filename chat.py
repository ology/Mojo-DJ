from google import genai
from google.genai import types
import os
import sys

def get_response(prompt):
    api_key = os.environ.get("GEMINI_API_KEY")
    client = genai.Client(api_key=api_key)
    response = client.models.generate_content(
        config=types.GenerateContentConfig(
            system_instruction="Detail the history of the given song.",
            max_output_tokens=1000,
            temperature=0
        ),
        model="gemini-2.0-flash",
        contents=prompt,
    )
    return response.text

def main():
    response = ""
    if sys.argv[1]:
        prompt = sys.argv[1]
        if prompt:
            response = get_response(prompt)
    print(response)

if __name__ == "__main__":
    main()
