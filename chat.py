from google import genai
from google.genai import types
import os
import sys

def get_response(instruction, prompt):
    api_key = os.environ.get("GEMINI_API_KEY")
    client = genai.Client(api_key=api_key)
    response = client.models.generate_content(
        config=types.GenerateContentConfig(
            system_instruction=instruction,
            max_output_tokens=1000,
            temperature=0
        ),
        model="gemini-2.0-flash",
        contents=prompt,
    )
    return response.text

def main():
    response = ""
    if sys.argv[1] and sys.argv[2]:
        instruction = sys.argv[1]
        prompt = sys.argv[2]
        if prompt:
            response = get_response(instruction, prompt)
    print(response)

if __name__ == "__main__":
    main()
