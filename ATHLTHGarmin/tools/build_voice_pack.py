#!/usr/bin/env python3
"""Generate explicitly labelled local development voices; no network or API key."""
from pathlib import Path
import subprocess
import tempfile
import wave
import shutil
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "resources" / "coach_generated"
SOURCE = ROOT / "source" / "ATHLTHCoachResources.mc"
PHRASES = {
    "en-US": ("en-us", {
        "start": "Workout started", "pause": "Paused", "resume": "Resumed",
        "complete": "Workout saved", "setComplete": "Set complete",
        "restStart": "Rest", "restEnd": "Rest complete",
        **{f"n{i}": str(i) for i in range(1, 11)}
    }),
    "nb-NO": ("nb", {
        "start": "Økten starter", "pause": "Pause", "resume": "Fortsett",
        "complete": "Økten er lagret", "setComplete": "Sett ferdig",
        "restStart": "Hvile", "restEnd": "Hvilen er ferdig",
        **{f"n{i}": word for i, word in enumerate(
            ["en","to","tre","fire","fem","seks","sju","åtte","ni","ti"], 1)}
    })
}
def main():
    engine = shutil.which("espeak-ng")
    ffmpeg = shutil.which("ffmpeg")
    if not engine or not ffmpeg:
        raise SystemExit("Install espeak-ng and ffmpeg first; no substitute voice is selected.")
    OUT.mkdir(parents=True, exist_ok=True)
    xml = ET.Element("resources")
    code = ["// Generated developer test pack, not a production ATHLTH voice.",
            "module ATHLTHCoachResources {", "    function resource(language, cue) {"]
    for language, (voice, phrases) in PHRASES.items():
        prefix = language.replace("-", "_")
        code.append(f'        if (language == "{language}") {{')
        for cue, phrase in phrases.items():
            identifier = f"Coach_{prefix}_{cue}"
            path = OUT / (identifier + ".ogg")
            with tempfile.TemporaryDirectory() as tmp:
                wav = Path(tmp) / "cue.wav"
                subprocess.run([engine, "-v", voice, "-s", "185", "-w", str(wav), phrase], check=True)
                with wave.open(str(wav)) as audio:
                    length = audio.getnframes() / audio.getframerate()
                    if not 0 < length <= 5:
                        raise ValueError(f"Invalid voice clip duration: {identifier}")
                subprocess.run([ffmpeg, "-nostdin", "-loglevel", "error", "-y", "-i", str(wav),
                                "-ac", "1", "-c:a", "libopus", "-b:a", "24k", str(path)], check=True)
            ET.SubElement(xml, "audio", id=identifier, filename=path.name)
            code.append(f'            if (cue == "{cue}") {{ return Rez.Audio.{identifier}; }}')
        code.append("        }")
    code += ["        return null;", "    }", "}"]
    ET.ElementTree(xml).write(OUT / "audio.xml", encoding="UTF-8", xml_declaration=True)
    SOURCE.write_text("\n".join(code) + "\n", encoding="utf-8")
    print("Generated", sum(len(x[1]) for x in PHRASES.values()), "offline test speech clips.")

if __name__ == "__main__":
    main()
