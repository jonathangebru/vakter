#!/usr/bin/env bash
# Pre-render every (locale, phrase) Vakter speaks during an alarm into
# a bundled .m4a file. Runs once on a dev Mac at build time. The
# rendered audio ships in `Sources/VakterApp/Resources/voices/<locale>/`
# and is loaded via AVAudioPlayer at runtime — no neural-net code in
# Vakter, no internet dependency, no per-launch latency.
#
# Two-engine pipeline:
#   • Piper TTS for the 8 European languages we have neural models for
#     (en, nl, no, de, fr, es, it, zh). Models live in `voices/models/`.
#   • Apple `say` for ja and ko (Piper has no models for either —
#     `voices.json` confirmed; 158 voices, 0 Japanese, 0 Korean).
#     Uses the user's installed `Kyoko` and `Yuna` voices, which on a
#     dev Mac that's downloaded the Enhanced/Premium variants give us
#     genuinely natural output.
#
# Both paths emit AAC-encoded `.m4a` at 64 kbps via `afconvert`. Output
# size: ~30–60 KB per phrase, ~5 MB total across 10 locales × 3
# phrases.
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VOICES_DIR="${ROOT}/voices/models"
OUT_DIR="${ROOT}/Sources/VakterApp/Resources/voices"
PIPER="${ROOT}/voices/piper-venv/bin/piper"

[[ -x "${PIPER}" ]] || { echo "✗ Piper not found at ${PIPER}. Run Scripts/install-piper.sh first."; exit 1; }
[[ -d "${VOICES_DIR}" ]] || { echo "✗ Voice models not found at ${VOICES_DIR}."; exit 1; }

# ── Locale → engine + model mapping ──────────────────────────────────
# Format per row:  locale|engine|model_or_voice
# engine: "piper" or "say"
declare -a LOCALES=(
  "en-US|piper|en_US-amy-medium"
  "nb-NO|piper|no_NO-talesyntese-medium"
  "de-DE|piper|de_DE-thorsten-medium"
  "fr-FR|piper|fr_FR-siwis-medium"
  "it-IT|piper|it_IT-paola-medium"
  "zh-CN|piper|zh_CN-huayan-medium"
  # Piper's only nl_NL voice is "mls_5809-low" which outputs at a
  # sample rate afconvert won't accept (the "low" tier voices share
  # this problem). Apple's Xander is high-quality Dutch and works.
  "nl-NL|say|Xander"
  # Same story for es_ES — Mónica is Apple's flagship Spanish voice.
  "es-ES|say|Mónica"
  # Piper has no Japanese voices at all (voices.json, 0 ja matches).
  "ja-JP|say|Kyoko"
  # Piper has no Korean voices either.
  "ko-KR|say|Yuna"
)

# ── Phrase keys (must mirror VakterPhrase Swift enum) ────────────────
PHRASES=(
  "alarmVoiceCue"
  "alarmVoiceCueEscalation2"
  "alarmVoiceCueEscalation3"
)

# ── Per-locale × per-phrase translated text ──────────────────────────
# Each takes (locale, phraseKey) and prints the actual text Vakter will
# speak. Translations done at indie-app quality — not professionally
# reviewed but plain enough that a native speaker would recognise the
# meaning. Native-speaker review is a v1.2 backlog item.
get_text() {
  local locale="$1" key="$2"
  case "${locale}:${key}" in
    # English
    "en-US:alarmVoiceCue")              echo "This MacBook is being tracked. Please put it down." ;;
    "en-US:alarmVoiceCueEscalation2")   echo "Step away from this Mac. The owner has been alerted." ;;
    "en-US:alarmVoiceCueEscalation3")   echo "Photos are being recorded. Put the Mac down now." ;;
    # Dutch
    "nl-NL:alarmVoiceCue")              echo "Deze MacBook wordt gevolgd. Leg hem alstublieft neer." ;;
    "nl-NL:alarmVoiceCueEscalation2")   echo "Stap weg van deze Mac. De eigenaar is gewaarschuwd." ;;
    "nl-NL:alarmVoiceCueEscalation3")   echo "Er worden foto's gemaakt. Leg de Mac nu neer." ;;
    # Norwegian
    "nb-NO:alarmVoiceCue")              echo "Denne Macen blir sporet. Vennligst sett den fra deg." ;;
    "nb-NO:alarmVoiceCueEscalation2")   echo "Gå vekk fra denne Macen. Eieren er varslet." ;;
    "nb-NO:alarmVoiceCueEscalation3")   echo "Bilder blir tatt. Sett Macen ned nå." ;;
    # German
    "de-DE:alarmVoiceCue")              echo "Dieses MacBook wird verfolgt. Bitte legen Sie es ab." ;;
    "de-DE:alarmVoiceCueEscalation2")   echo "Treten Sie von diesem Mac zurück. Der Eigentümer wurde benachrichtigt." ;;
    "de-DE:alarmVoiceCueEscalation3")   echo "Es werden Fotos aufgenommen. Legen Sie den Mac jetzt ab." ;;
    # French
    "fr-FR:alarmVoiceCue")              echo "Ce MacBook est suivi. Veuillez le reposer." ;;
    "fr-FR:alarmVoiceCueEscalation2")   echo "Éloignez-vous de ce Mac. Le propriétaire a été alerté." ;;
    "fr-FR:alarmVoiceCueEscalation3")   echo "Des photos sont enregistrées. Reposez le Mac maintenant." ;;
    # Spanish
    "es-ES:alarmVoiceCue")              echo "Este MacBook está siendo rastreado. Por favor, déjelo." ;;
    "es-ES:alarmVoiceCueEscalation2")   echo "Aléjese de este Mac. El propietario ha sido alertado." ;;
    "es-ES:alarmVoiceCueEscalation3")   echo "Se están grabando fotos. Deje el Mac ahora." ;;
    # Italian
    "it-IT:alarmVoiceCue")              echo "Questo MacBook è sotto sorveglianza. La prego di riporlo." ;;
    "it-IT:alarmVoiceCueEscalation2")   echo "Si allontani da questo Mac. Il proprietario è stato avvisato." ;;
    "it-IT:alarmVoiceCueEscalation3")   echo "Le foto vengono registrate. Posi il Mac ora." ;;
    # Mandarin Chinese
    "zh-CN:alarmVoiceCue")              echo "这台 MacBook 正在被追踪。请放下。" ;;
    "zh-CN:alarmVoiceCueEscalation2")   echo "请远离这台 Mac。所有者已被通知。" ;;
    "zh-CN:alarmVoiceCueEscalation3")   echo "正在拍摄照片。请立即放下 Mac。" ;;
    # Japanese
    "ja-JP:alarmVoiceCue")              echo "この MacBook は追跡されています。置いてください。" ;;
    "ja-JP:alarmVoiceCueEscalation2")   echo "この Mac から離れてください。所有者に通知が届きました。" ;;
    "ja-JP:alarmVoiceCueEscalation3")   echo "写真を記録しています。今すぐ Mac を置いてください。" ;;
    # Korean
    "ko-KR:alarmVoiceCue")              echo "이 맥북은 추적되고 있습니다. 내려놓아 주세요." ;;
    "ko-KR:alarmVoiceCueEscalation2")   echo "이 맥에서 떨어져 주세요. 소유자에게 알림이 전송되었습니다." ;;
    "ko-KR:alarmVoiceCueEscalation3")   echo "사진이 촬영되고 있습니다. 지금 맥을 내려놓으세요." ;;
    *) echo "" ;;
  esac
}

# ── Render loop ──────────────────────────────────────────────────────
rendered=0
skipped=0
for row in "${LOCALES[@]}"; do
  IFS='|' read -r locale engine asset <<< "${row}"
  out_locale_dir="${OUT_DIR}/${locale}"
  mkdir -p "${out_locale_dir}"
  for phrase in "${PHRASES[@]}"; do
    text="$(get_text "${locale}" "${phrase}")"
    if [[ -z "${text}" ]]; then
      skipped=$((skipped + 1))
      continue
    fi
    raw="${out_locale_dir}/${phrase}.raw"
    m4a="${out_locale_dir}/${phrase}.m4a"

    case "${engine}" in
      piper)
        model="${VOICES_DIR}/${asset}.onnx"
        cfg="${VOICES_DIR}/${asset}.onnx.json"
        if [[ ! -f "${model}" ]]; then
          echo "✗ ${locale}/${phrase}: missing Piper model ${asset}.onnx — skipped"
          continue
        fi
        # Piper outputs raw 16-bit mono PCM at the rate in the config.
        # We always wrap it as a WAV file (deterministic) and then
        # convert WAV→m4a via afconvert. Trying to feed afconvert raw
        # PCM directly hits sample-rate mismatches for some voices.
        echo "${text}" | "${PIPER}" --model "${model}" --config "${cfg}" --output-raw \
          > "${raw}" 2>/dev/null
        wav="${out_locale_dir}/${phrase}.wav"
        /usr/bin/python3 - "${raw}" "${wav}" "${cfg}" <<'PY'
import sys, json, wave
raw, wav, cfg = sys.argv[1], sys.argv[2], sys.argv[3]
sr = json.load(open(cfg))["audio"]["sample_rate"]
data = open(raw, "rb").read()
with wave.open(wav, "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr); w.writeframes(data)
PY
        afconvert -f m4af -d aac -b 64000 "${wav}" "${m4a}" 2>&1 | head -3 || true
        rm -f "${raw}" "${wav}"
        ;;
      say)
        aiff="${out_locale_dir}/${phrase}.aiff"
        say -v "${asset}" -o "${aiff}" "${text}"
        afconvert -f m4af -d aac -b 64000 "${aiff}" "${m4a}"
        rm -f "${aiff}"
        ;;
      *)
        echo "✗ ${locale}/${phrase}: unknown engine '${engine}' — skipped"
        continue
        ;;
    esac

    if [[ -f "${m4a}" ]]; then
      size=$(stat -f%z "${m4a}")
      printf "  ✓ %s/%s  (%s, %.1f KB)\n" "${locale}" "${phrase}" "${engine}" "$(echo "scale=1; ${size}/1024" | bc)"
      rendered=$((rendered + 1))
    else
      echo "  ✗ ${locale}/${phrase} (${engine}) — render failed"
    fi
  done
done

echo
echo "✅ ${rendered} clips rendered, ${skipped} skipped."
du -sh "${OUT_DIR}"
