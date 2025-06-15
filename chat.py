from google import genai
from google.genai import types
import os
import sys
import wave

def wave_file(filename, pcm, channels=1, rate=24000, sample_width=2):
    with wave.open(filename, "wb") as wf:
        wf.setnchannels(channels)
        wf.setsampwidth(sample_width)
        wf.setframerate(rate)
        wf.writeframes(pcm)

def build_response(client, instruction, prompt):
    transcript = client.models.generate_content(
        model="gemini-2.0-flash",
        contents=prompt,
        config=types.GenerateContentConfig(
            system_instruction=instruction,
            max_output_tokens=1000,
            temperature=0
        ),
    ).text
    response = client.models.generate_content(
        model="gemini-2.5-flash-preview-tts",
        contents=transcript,
        config=types.GenerateContentConfig(
            response_modalities=["AUDIO"],
            speech_config=types.SpeechConfig(
                voice_config=types.VoiceConfig(
                    prebuilt_voice_config=types.PrebuiltVoiceConfig(
                        voice_name='Schedar',
                    )
                )
            ),
        )
    )
    data = response.candidates[0].content.parts[0].inline_data.data
    file_name='out.wav'
    wave_file(file_name, data)
    return transcript

def main():
    response = ""
    if sys.argv[1] and sys.argv[2]:
        instruction = sys.argv[1]
        prompt = sys.argv[2]
        api_key = os.environ.get("GEMINI_API_KEY")
        client = genai.Client(api_key=api_key)
        if prompt:
            response = build_response(client, instruction, prompt)
    print(response)

if __name__ == "__main__":
    main()
