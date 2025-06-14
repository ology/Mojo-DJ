from google import genai
import os
import sys

def get_response(prompt):
    api_key = os.environ.get("GEMINI_API_KEY")
    client = genai.Client(api_key=api_key)
    response = client.models.generate_content(
        contents=prompt,
        model="gemini-2.0-flash",
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
