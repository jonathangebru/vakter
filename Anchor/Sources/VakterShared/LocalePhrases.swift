import Foundation

/// Strings that Vakter speaks or writes to the user, in 7 languages.
///
/// We localise:
///   - the alarm voice cue ("This MacBook is being tracked..."), spoken
///     by `AVSpeechSynthesizer` every 4 s during an audible alarm
///   - the iMessage body sent to the evidence recipient when an alarm
///     fires
///   - the human-readable trigger reason ("Find My disabled while armed",
///     "Apple ID changed while armed") that's appended to the message
///
/// Not localised (deliberately): the brand name "Vakter" and timestamps
/// (rendered via the user's system locale).
///
/// **Maintenance.** Languages chosen by overlap of three things: macOS
/// market share by country, where the user has connections, and where
/// the brand etymology lands ("vakter" is Norwegian). To add a language
/// add a case to `Language` + a row to every dictionary in
/// `phraseTable`. The build won't compile until the dictionaries are
/// exhaustive (every Language must have every VakterPhrase mapped).
public enum VakterPhrase: String, CaseIterable, Sendable {
    /// The first alarm voice cue, calm and matter-of-fact.
    case alarmVoiceCue
    /// Second escalation tier — fired ~12 s into the alarm. Direct.
    case alarmVoiceCueEscalation2
    /// Third escalation tier — fired ~24 s into the alarm. Insistent.
    case alarmVoiceCueEscalation3
    /// Subject line / first line of the iMessage to the recipient.
    case evidenceMessageHeader
    /// Format string for the "location" line. Substitutes `{maps_url}`.
    case evidenceLocationLine
    /// Format string used when we have no current location, only a
    /// last-known one. Substitutes `{maps_url}` and `{age_minutes}`.
    case evidenceLastKnownLocationLine
    /// Format string used when location is fully unavailable.
    case evidenceLocationUnavailable
    /// Reason line for a Find-My-token-cleared trigger.
    case findMyClearedReason
    /// Reason line for an Apple-ID-changed trigger.
    case appleIDChangedReason
    /// Footer / signature line.
    case evidenceFooter
}

/// Languages with localised phrase tables. Falls back to English for
/// any locale outside this list. Italian / Mandarin / Korean were
/// added in v1.1 alongside the bundled pre-rendered audio for those
/// locales (see `Scripts/render-voices.sh`).
private enum Language: String {
    case en, nl, no, de, fr, es, ja, it, zh, ko
}

public enum LocalePhrases {

    /// Translate a phrase, optionally substituting `{key}` tokens in the
    /// template. Falls back to English on unknown locale.
    public static func text(_ phrase: VakterPhrase,
                            locale: Locale = .current,
                            substitutions: [String: String] = [:]) -> String {
        let lang = language(for: locale)
        let table = phraseTable[lang] ?? phraseTable[.en]!
        var template = table[phrase] ?? phraseTable[.en]![phrase] ?? ""
        for (key, value) in substitutions {
            template = template.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return template
    }

    /// Pick a BCP-47 voice tag for `AVSpeechSynthesisVoice(language:)`.
    /// Falls back to `"en-US"` on unknown locales.
    public static func voiceLanguageTag(for locale: Locale = .current) -> String {
        switch language(for: locale) {
        case .en: return "en-US"
        case .nl: return "nl-NL"
        case .no: return "nb-NO"   // Norwegian Bokmål
        case .de: return "de-DE"
        case .fr: return "fr-FR"
        case .es: return "es-ES"
        case .ja: return "ja-JP"
        case .it: return "it-IT"
        case .zh: return "zh-CN"
        case .ko: return "ko-KR"
        }
    }

    /// Map a `Locale` to one of our supported `Language` cases. macOS
    /// 13+ uses `Locale.Language` API; older callers should be fine
    /// because we're not building below 14.
    ///
    /// Special case: macOS canonicalises "no" (Norwegian) to "nb"
    /// (Bokmål) — both should land on our `.no` case.
    private static func language(for locale: Locale) -> Language {
        let code = (locale.language.languageCode?.identifier ?? "en").lowercased()
        if code == "nb" { return .no }
        return Language(rawValue: code) ?? .en
    }

    // MARK: - Phrase table
    //
    // Concise but human. Avoid jargon — these are read by a panicked
    // user on their phone in the middle of a public space. Keep the
    // alarmVoiceCue under ~5 seconds at default TTS rate (~10–12
    // words) so the loop's 4 s cadence stays natural.

    private static let phraseTable: [Language: [VakterPhrase: String]] = [
        .en: [
            .alarmVoiceCue:                  "This MacBook is being tracked. Please put it down.",
            .alarmVoiceCueEscalation2:       "Step away from this Mac. The owner has been alerted.",
            .alarmVoiceCueEscalation3:       "Photos are being recorded. Put the Mac down now.",
            .evidenceMessageHeader:          "Vakter alert — your Mac may have been moved or accessed.",
            .evidenceLocationLine:           "Location: {maps_url}",
            .evidenceLastKnownLocationLine:  "Last-known location ({age_minutes} min ago): {maps_url}",
            .evidenceLocationUnavailable:    "Location: unavailable.",
            .findMyClearedReason:            "Find My was disabled while Vakter was armed.",
            .appleIDChangedReason:           "The signed-in Apple ID changed while Vakter was armed.",
            .evidenceFooter:                 "Photos attached. Disarm Vakter to stop the alert.",
        ],
        .nl: [
            .alarmVoiceCue:                  "Deze MacBook wordt gevolgd. Leg hem alstublieft neer.",
            .alarmVoiceCueEscalation2:       "Stap weg van deze Mac. De eigenaar is gewaarschuwd.",
            .alarmVoiceCueEscalation3:       "Er worden foto's gemaakt. Leg de Mac nu neer.",
            .evidenceMessageHeader:          "Vakter-melding — je Mac is mogelijk verplaatst of geopend.",
            .evidenceLocationLine:           "Locatie: {maps_url}",
            .evidenceLastKnownLocationLine:  "Laatst bekende locatie ({age_minutes} min geleden): {maps_url}",
            .evidenceLocationUnavailable:    "Locatie: niet beschikbaar.",
            .findMyClearedReason:            "Zoek Mijn werd uitgeschakeld terwijl Vakter geactiveerd was.",
            .appleIDChangedReason:           "De Apple ID is gewijzigd terwijl Vakter geactiveerd was.",
            .evidenceFooter:                 "Foto's bijgevoegd. Deactiveer Vakter om het alarm te stoppen.",
        ],
        .no: [
            .alarmVoiceCue:                  "Denne Macen blir sporet. Vennligst sett den fra deg.",
            .alarmVoiceCueEscalation2:       "Gå vekk fra denne Macen. Eieren er varslet.",
            .alarmVoiceCueEscalation3:       "Bilder blir tatt. Sett Macen ned nå.",
            .evidenceMessageHeader:          "Vakter-varsel — Macen din kan ha blitt flyttet eller åpnet.",
            .evidenceLocationLine:           "Posisjon: {maps_url}",
            .evidenceLastKnownLocationLine:  "Siste kjente posisjon (for {age_minutes} min siden): {maps_url}",
            .evidenceLocationUnavailable:    "Posisjon: utilgjengelig.",
            .findMyClearedReason:            "Finn min ble slått av mens Vakter var aktivert.",
            .appleIDChangedReason:           "Apple-ID-en ble endret mens Vakter var aktivert.",
            .evidenceFooter:                 "Bilder vedlagt. Deaktiver Vakter for å stoppe varselet.",
        ],
        .de: [
            .alarmVoiceCue:                  "Dieses MacBook wird verfolgt. Bitte legen Sie es ab.",
            .alarmVoiceCueEscalation2:       "Treten Sie von diesem Mac zurück. Der Eigentümer wurde benachrichtigt.",
            .alarmVoiceCueEscalation3:       "Es werden Fotos aufgenommen. Legen Sie den Mac jetzt ab.",
            .evidenceMessageHeader:          "Vakter-Alarm — Ihr Mac wurde möglicherweise bewegt oder genutzt.",
            .evidenceLocationLine:           "Standort: {maps_url}",
            .evidenceLastKnownLocationLine:  "Letzter bekannter Standort (vor {age_minutes} Min.): {maps_url}",
            .evidenceLocationUnavailable:    "Standort: nicht verfügbar.",
            .findMyClearedReason:            "Wo ist? wurde deaktiviert, während Vakter aktiv war.",
            .appleIDChangedReason:           "Die angemeldete Apple-ID hat sich geändert, während Vakter aktiv war.",
            .evidenceFooter:                 "Fotos angehängt. Vakter deaktivieren, um den Alarm zu stoppen.",
        ],
        .fr: [
            .alarmVoiceCue:                  "Ce MacBook est suivi. Veuillez le reposer.",
            .alarmVoiceCueEscalation2:       "Éloignez-vous de ce Mac. Le propriétaire a été alerté.",
            .alarmVoiceCueEscalation3:       "Des photos sont enregistrées. Reposez le Mac maintenant.",
            .evidenceMessageHeader:          "Alerte Vakter — votre Mac a peut-être été déplacé ou utilisé.",
            .evidenceLocationLine:           "Emplacement : {maps_url}",
            .evidenceLastKnownLocationLine:  "Dernière position connue (il y a {age_minutes} min) : {maps_url}",
            .evidenceLocationUnavailable:    "Emplacement : indisponible.",
            .findMyClearedReason:            "Localiser a été désactivé pendant que Vakter était armé.",
            .appleIDChangedReason:           "L’identifiant Apple a changé pendant que Vakter était armé.",
            .evidenceFooter:                 "Photos jointes. Désarmez Vakter pour arrêter l’alerte.",
        ],
        .es: [
            .alarmVoiceCue:                  "Este MacBook está siendo rastreado. Por favor, déjelo.",
            .alarmVoiceCueEscalation2:       "Aléjese de este Mac. El propietario ha sido alertado.",
            .alarmVoiceCueEscalation3:       "Se están grabando fotos. Deje el Mac ahora.",
            .evidenceMessageHeader:          "Alerta de Vakter — tu Mac puede haber sido movido o accedido.",
            .evidenceLocationLine:           "Ubicación: {maps_url}",
            .evidenceLastKnownLocationLine:  "Última ubicación conocida (hace {age_minutes} min): {maps_url}",
            .evidenceLocationUnavailable:    "Ubicación: no disponible.",
            .findMyClearedReason:            "Buscar se desactivó mientras Vakter estaba activado.",
            .appleIDChangedReason:           "El ID de Apple cambió mientras Vakter estaba activado.",
            .evidenceFooter:                 "Fotos adjuntas. Desactiva Vakter para detener la alerta.",
        ],
        .ja: [
            .alarmVoiceCue:                  "このMacBookは追跡されています。置いてください。",
            .alarmVoiceCueEscalation2:       "このMacから離れてください。所有者に通知が届きました。",
            .alarmVoiceCueEscalation3:       "写真を記録しています。今すぐMacを置いてください。",
            .evidenceMessageHeader:          "Vakter警告 — Macが移動または使用された可能性があります。",
            .evidenceLocationLine:           "位置: {maps_url}",
            .evidenceLastKnownLocationLine:  "最後の既知の位置 ({age_minutes}分前): {maps_url}",
            .evidenceLocationUnavailable:    "位置: 利用不可。",
            .findMyClearedReason:            "Vakter作動中に「探す」が無効化されました。",
            .appleIDChangedReason:           "Vakter作動中にApple IDが変更されました。",
            .evidenceFooter:                 "写真を添付しました。Vakterを解除すると警告が停止します。",
        ],
        .it: [
            .alarmVoiceCue:                  "Questo MacBook è sotto sorveglianza. La prego di riporlo.",
            .alarmVoiceCueEscalation2:       "Si allontani da questo Mac. Il proprietario è stato avvisato.",
            .alarmVoiceCueEscalation3:       "Le foto vengono registrate. Posi il Mac ora.",
            .evidenceMessageHeader:          "Allarme Vakter — il tuo Mac potrebbe essere stato spostato o utilizzato.",
            .evidenceLocationLine:           "Posizione: {maps_url}",
            .evidenceLastKnownLocationLine:  "Ultima posizione nota ({age_minutes} min fa): {maps_url}",
            .evidenceLocationUnavailable:    "Posizione: non disponibile.",
            .findMyClearedReason:            "Dov'è è stato disattivato mentre Vakter era attivo.",
            .appleIDChangedReason:           "L'ID Apple è cambiato mentre Vakter era attivo.",
            .evidenceFooter:                 "Foto allegate. Disattiva Vakter per fermare l'allarme.",
        ],
        .zh: [
            .alarmVoiceCue:                  "这台 MacBook 正在被追踪。请放下。",
            .alarmVoiceCueEscalation2:       "请远离这台 Mac。所有者已被通知。",
            .alarmVoiceCueEscalation3:       "正在拍摄照片。请立即放下 Mac。",
            .evidenceMessageHeader:          "Vakter 警报 — 您的 Mac 可能已被移动或访问。",
            .evidenceLocationLine:           "位置: {maps_url}",
            .evidenceLastKnownLocationLine:  "最后已知位置 ({age_minutes} 分钟前): {maps_url}",
            .evidenceLocationUnavailable:    "位置:不可用。",
            .findMyClearedReason:            "Vakter 启用期间“查找”被关闭。",
            .appleIDChangedReason:           "Vakter 启用期间登录的 Apple ID 已更改。",
            .evidenceFooter:                 "已附上照片。解除 Vakter 以停止警报。",
        ],
        .ko: [
            .alarmVoiceCue:                  "이 맥북은 추적되고 있습니다. 내려놓아 주세요.",
            .alarmVoiceCueEscalation2:       "이 맥에서 떨어져 주세요. 소유자에게 알림이 전송되었습니다.",
            .alarmVoiceCueEscalation3:       "사진이 촬영되고 있습니다. 지금 맥을 내려놓으세요.",
            .evidenceMessageHeader:          "Vakter 경보 — Mac이 이동되거나 접근되었을 수 있습니다.",
            .evidenceLocationLine:           "위치: {maps_url}",
            .evidenceLastKnownLocationLine:  "마지막 알려진 위치 ({age_minutes}분 전): {maps_url}",
            .evidenceLocationUnavailable:    "위치: 사용할 수 없음.",
            .findMyClearedReason:            "Vakter 작동 중에 '나의 찾기'가 비활성화되었습니다.",
            .appleIDChangedReason:           "Vakter 작동 중에 Apple ID가 변경되었습니다.",
            .evidenceFooter:                 "사진이 첨부되었습니다. Vakter를 해제하면 경보가 멈춥니다.",
        ],
    ]
}
