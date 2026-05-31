import Foundation

/// Adversarial prompt-engineering corpus for the EXPLAIN module
/// (Issue #72).
///
/// **All fixtures are synthetic.** No real PII, no real phishing URLs,
/// no scraped emails. The corpus is built from three safe sources:
///
///   1. **Reserved test ranges**: phone numbers use the `555-01XX`
///      range (North American Numbering Plan, reserved by the FCC for
///      fictional/film use — never a real subscriber). SSNs use the
///      `987-65-43XX` range (also fictional-use reserved by the SSA).
///      Credit card numbers, where present, use the industry-standard
///      Visa test number `4111-1111-1111-1111` (publicly documented as
///      Luhn-valid but never issued).
///
///   2. **Documented example domains**: `example.com`, `example.org`,
///      `test.invalid` — reserved by IANA / RFC 2606 so a typo can't
///      route a request anywhere real.
///
///   3. **Synthesised phishing patterns**: phrases that match
///      well-known scam taxonomies (Anti-Phishing Working Group's
///      published heuristics, common SOC training corpora) without
///      copying any specific live campaign. URLs in phishing fixtures
///      use synthetic subdomains under `example.com` so the corpus
///      isn't itself a usable attack tool.
///
/// The fixtures are exposed as `static let` constants so test files
/// can reference them by name in `XCTAssertEqual` failure messages —
/// "fixture `applePhishLookalikeDomain` should have classified as
/// `.unsure`" is a more useful diagnostic than a literal string dump.
///
/// **What this corpus does NOT contain:**
///   - Real victim emails or scraped scam samples.
///   - Live malicious URLs (the brand contract is "Vakter never sends
///     anything to a model that could re-attack the user"; the test
///     corpus inherits that contract).
///   - Anyone's real name, address, or other identifier — the only
///     names used are common single-word placeholders ("Alice", "Bob")
///     that any reasonable redactor will pass through as common nouns.
enum ExplainPromptFixtures {

    // MARK: - Phishing — Apple-support impersonation

    /// Lookalike domain that visually resembles `apple.com` but uses an
    /// attacker-controlled subdomain pattern (`apple.com.<attacker>`).
    /// The TLD is `.xyz` — a common low-cost gTLD favoured for short-
    /// lived phishing infrastructure. Domain is synthesised under
    /// `example.com` so this fixture is never resolvable.
    static let applePhishLookalikeDomain =
        "Apple Support notice: your Apple ID will be suspended in 24 " +
        "hours. Verify at https://apple.com.support-helper.example.com " +
        "immediately to keep your account active."

    /// "Your Apple ID was used to sign in to a device" — a classic
    /// urgency-driven Apple-impersonation hook.
    static let applePhishSignInAlert =
        "[Apple] Your Apple ID (AppleID-2026-987) was used to sign in " +
        "to an iCloud account on an unrecognized device. If this was " +
        "not you, lock your account immediately at " +
        "https://icloud.example.com/lock?token=xyz."

    /// Apple-impersonation that asks the recipient to "verify payment
    /// method." Synthetic CC anchor.
    static let applePhishPaymentVerification =
        "Your Apple Pay subscription could not be processed. Update " +
        "your payment method to avoid losing access. Visit " +
        "https://apple-billing.example.org/verify?u=4111 to confirm."

    // MARK: - Phishing — bank impersonation

    /// Generic bank-suspension hook — domain-name "bank-name-here"
    /// keeps the fixture vendor-neutral.
    static let bankPhishAccountSuspended =
        "[BankOf Synthetic] Unusual activity detected on account ending " +
        "in -4321. To avoid a temporary suspension, log in at " +
        "https://secure.bankof-synthetic.example.net/login within 24 " +
        "hours."

    /// "Verify your wire transfer" — pretexting common in business-
    /// email-compromise scams. Synthetic IBAN-shaped string anchor.
    static let bankPhishWireVerification =
        "Confirm the outgoing wire of $9,750 to recipient account " +
        "DE89 3704 0044 0532 0130 00 by clicking " +
        "https://wire-confirm.example.com/?id=AB12. If you did not " +
        "request this, contact your relationship manager."

    /// "Update your debit card PIN online" — almost never legitimate.
    static let bankPhishPINReset =
        "Important: your debit card PIN must be re-confirmed online. " +
        "Visit https://my-bank.example.org/pin-reset and follow the " +
        "instructions. Failure to do so within 48 hours will lock " +
        "your card."

    // MARK: - Phishing — package-shipper impersonation

    /// "Your package is held at customs" — a perennial UPS/FedEx/USPS
    /// impersonation; small fee, big upside for the attacker.
    static let packagePhishCustomsHold =
        "Your shipment (tracking SYN9876543210) is being held at " +
        "customs pending a $2.99 import fee. Pay the fee at " +
        "https://customs-fee.example.com/pay to release your package."

    /// "Reschedule your delivery" — phishes a credit card under the
    /// guise of a small re-delivery fee.
    static let packagePhishRedelivery =
        "USPS notice: your package could not be delivered on the first " +
        "attempt. Reschedule and pay the $1.99 re-delivery fee at " +
        "https://usps-reschedule.example.net/."

    /// FedEx-style "verify delivery address" hook.
    static let packagePhishAddressVerification =
        "FedEx update: we were unable to verify the delivery address " +
        "for your package. Please confirm your address at " +
        "https://fedex-verify.example.org/track to avoid return-to-" +
        "sender."

    // MARK: - Phishing — lottery / prize / advance-fee

    /// "You've won the lottery" — the canonical 419-adjacent hook.
    static let lotteryPhishYouveWon =
        "CONGRATULATIONS! Your email address has been randomly selected " +
        "as the winner of $2,500,000 USD in the International Email " +
        "Lottery. To claim your prize, reply with your full name, " +
        "address, and phone number."

    /// "Free iPhone giveaway" — survey-fronted phish.
    static let lotteryPhishFreeiPhone =
        "You're one of 10 lucky users selected to receive a FREE " +
        "iPhone 17 Pro Max! Click https://giveaway.example.com/claim " +
        "and complete a short survey to claim your prize before " +
        "midnight tonight."

    // MARK: - Phishing — romance / pig-butchering openers

    /// Anonymous opener targeting the recipient as "dear" — classic
    /// romance-scam first contact.
    static let romancePhishColdOpener =
        "Dear, I hope this message finds you well. I came across your " +
        "profile and felt an immediate connection. I am a widowed " +
        "businesswoman currently working in Dubai. Tell me about " +
        "yourself when you have time."

    /// "Pig-butchering" investment hook — the romance opener pivots to
    /// crypto/forex within a few messages.
    static let romancePhishInvestmentPivot =
        "It's been wonderful getting to know you these past weeks. " +
        "My uncle, who works in trading, told me about a guaranteed " +
        "crypto strategy that returned 40% last month. I'd love to " +
        "share it with you — message me on Telegram @synth_trader for " +
        "the details."

    // MARK: - Phishing — regulator / government impersonation

    /// "Your account will be suspended" framed as a regulator notice.
    static let regulatorPhishGenericSuspension =
        "Notice from the Office of the Comptroller of the Currency: " +
        "your business account is scheduled for suspension within 72 " +
        "hours pending review. Submit your verification at " +
        "https://occ-verify.example.com/ to avoid suspension."

    /// IRS-impersonation — "you are owed a refund, pay a fee."
    static let regulatorPhishIRSRefund =
        "IRS notice: you are eligible for a $1,247 tax refund from " +
        "the 2025 tax year. Verify your bank routing information at " +
        "https://irs-refund.example.org/claim within 14 days or your " +
        "refund will be forfeited."

    /// EU GDPR / data-protection regulator impersonation.
    static let regulatorPhishEUGDPR =
        "GDPR compliance team: a recent audit identified your account " +
        "as not in compliance with Article 32. Update your records " +
        "and confirm consent at https://gdpr-verify.example.eu/ " +
        "within 48 hours to avoid a €500 administrative fee."

    /// CEO-fraud / business-email-compromise opener — "urgent wire,
    /// don't tell anyone."
    static let regulatorPhishCEOWire =
        "I need you to handle a confidential transaction for me " +
        "today. Don't loop in finance — they're in the audit meeting. " +
        "Wire $48,750 to vendor account 9876543210 and confirm by " +
        "email. -CEO"

    // MARK: - Benign inputs — real-looking domains

    /// Plain reference to `apple.com` in normal prose.
    static let benignApplePlainURL =
        "I'm trying to download the macOS Sequoia installer. The " +
        "Apple support page at https://support.apple.com/guide/" +
        "mac-help has clear instructions for creating a bootable " +
        "USB drive."

    /// Real-looking bank URL referenced as part of a benign request.
    static let benignBankPlainURL =
        "I logged into https://www.chase.com on Chrome and updated my " +
        "mailing address — the change went through within a minute. " +
        "No issues at all."

    /// Real-looking package tracking number with the carrier URL.
    static let benignPackageTracking =
        "Your Amazon order shipped via UPS — tracking number " +
        "1Z999AA10123456784. You can track at " +
        "https://www.ups.com/track."

    /// Casual personal email about lunch.
    static let benignFriendLunchEmail =
        "Hey! Are you still up for lunch on Friday? I was thinking " +
        "that new ramen place near the office — they take reservations " +
        "on opentable. Let me know what works."

    /// Legitimate password-reset email — has the right shape (link,
    /// expiry, "if this wasn't you" footer).
    static let benignPasswordResetLegit =
        "We received a request to reset your password. Use the link " +
        "below within the next hour to choose a new password. If you " +
        "did not request this reset, you can safely ignore this email; " +
        "your password will remain unchanged. -- the GitHub team"

    /// Order-confirmation email with realistic structure.
    static let benignOrderConfirmation =
        "Thanks for your order! Order #ORD-2026-3849 will ship within " +
        "two business days. You'll get a tracking link when it leaves " +
        "our warehouse. View order details in your account at any time."

    /// Newsletter excerpt — calls to action but no urgency.
    static let benignNewsletter =
        "This week in security: Apple released a patch for an XNU " +
        "vulnerability tracked as CVE-2026-1234, NIST published " +
        "draft guidance on post-quantum hash migration, and the EFF " +
        "reported on a new tracker-blocker browser extension."

    /// Two-factor authentication code — short, benign, expected shape.
    static let benignTwoFactorCode =
        "Your verification code is 829-103. This code will expire in " +
        "10 minutes. If you did not request this code, please ignore " +
        "this message."

    /// Calendar invite reminder.
    static let benignCalendarReminder =
        "Reminder: your meeting \"Q2 roadmap review\" starts in 15 " +
        "minutes. The meeting will be held in conference room 4B. The " +
        "agenda is in the shared document linked from the invite."

    /// Build CI status email.
    static let benignBuildCIStatus =
        "Your build for branch `feature/explain-tests` passed all " +
        "checks: lint (5s), unit tests (1m 47s, 372 passing), " +
        "integration tests (4m 12s), and the security scan."

    // MARK: - Ambiguous — looks-like-phishing-but-isn't

    /// Real lottery the user actually signed up for — has the same
    /// breathless headline shape as a scam.
    static let ambiguousRealLotteryWinner =
        "CONGRATS! You won the Q2 raffle at the office holiday party — " +
        "the $50 Amazon gift card is yours. Reply to this email and " +
        "I'll drop it on your desk Monday. -Janet, HR"

    /// Security researcher's own phishing test — the framing is " +
    /// adversarial but the intent is defensive.
    static let ambiguousResearcherTestPhish =
        "[INTERNAL — phishing simulation test] Your Acme corp account " +
        "will be locked in 24 hours. Click https://internal-phish-" +
        "training.example.com/test123 to reset. (This is a test from " +
        "the security team — if you click, you'll be redirected to " +
        "training.)"

    /// Friend forwarding a phishing email and asking "is this real?"
    static let ambiguousFriendForwardedPhish =
        "Hey can you look at the email below? Looks suspicious to me " +
        "but my mom got it and is freaking out. Forwarded message: " +
        "---- Your iCloud will be terminated in 24 hours. Verify at " +
        "https://icloud-help.example.com/verify ---- What do you think?"

    /// "We've updated our terms of service" — boring, occasionally
    /// scammy, hard to classify.
    static let ambiguousToSUpdate =
        "We've updated our Terms of Service and Privacy Policy. The " +
        "changes take effect on June 15. To continue using your " +
        "account, please review and accept the updated terms at " +
        "https://www.example.com/terms-update."

    /// Cold sales outreach — has unsolicited-stranger DNA but isn't
    /// phishing.
    static let ambiguousColdSales =
        "Hi, I'm reaching out because I noticed you're the Director " +
        "of IT at a fast-growing SaaS company. We help teams like " +
        "yours reduce cloud costs by 30%. Are you the right person to " +
        "talk to about a 15-minute demo?"

    /// "Cryptocurrency airdrop" — sometimes legit (rare), often a phish.
    static let ambiguousCryptoAirdrop =
        "You're eligible for a 500 SYNTH token airdrop based on your " +
        "wallet activity. Claim before the deadline at " +
        "https://airdrop.example.com/claim. No private keys required."

    /// LinkedIn-style "I'm a recruiter" outreach — sometimes real,
    /// sometimes a credential-grab pretext.
    static let ambiguousRecruiterOutreach =
        "Hi, I came across your profile and thought of a Senior " +
        "Security Engineer role at a Fortune 100 company. Salary band " +
        "$280K-$340K + equity. Are you open to a quick chat? Reply " +
        "with your resume and I'll send details."

    /// "Your subscription is about to renew" — real if you have the
    /// subscription, suspicious if you don't.
    static let ambiguousSubscriptionRenewal =
        "Your annual subscription renews on June 5 for $99. No action " +
        "needed if you'd like to continue. To cancel or update your " +
        "payment method, sign in at https://www.example.com/account."

    /// "Charity donation receipt" — real receipts and fake ones look
    /// remarkably similar.
    static let ambiguousCharityReceipt =
        "Thank you for your $25 donation to the Pacific Wildlife Fund. " +
        "Your contribution is tax-deductible to the extent allowed by " +
        "law. Receipt #PWF-2026-849283. Visit " +
        "https://pwf.example.org/donations for a full receipt."

    /// Vague "an unexpected sign-in" notice with no domain context.
    static let ambiguousVagueSignIn =
        "We noticed a sign-in to your account from a new device. If " +
        "this was you, no action is needed. If it wasn't, please " +
        "review your recent activity."

    // MARK: - Confidence edge cases

    /// Very short input — below useful-analysis threshold.
    static let edgeVeryShortInput = "hi"

    /// Empty whitespace.
    static let edgeAllWhitespace = "   \t\n  \n "

    /// Very long input (>10kB) — a paragraph repeated until it crosses
    /// the size threshold.
    static let edgeVeryLongInput: String = {
        let paragraph =
            "This is a long input that should still be redactable. " +
            "It contains an email contact@example.com and a phone " +
            "number 555-0123 for testing. We repeat to exceed 10kB. "
        // ~150 chars × 80 = ~12kB
        return String(repeating: paragraph, count: 80)
    }()

    /// RTL Unicode injection — bidi override mid-string. Should be
    /// stripped by the redactor's normalisation pass.
    static let edgeRTLInjection =
        "Please verify alice\u{202E}@example.com or your account will " +
        "be locked."

    /// Zero-width-character bypass — splits an SSN with ZWSP. Uses
    /// 123-prefix because the redactor rejects 9XX-prefixed candidates
    /// per actual SSN-issuance policy (`(?!9\d{2})`).
    static let edgeZeroWidthInSSN =
        "Customer SSN on file: 123\u{200B}-45\u{200B}-6789. Please " +
        "confirm."

    /// Zero-width-character bypass on credit card.
    static let edgeZeroWidthInCC =
        "Charge to 4111\u{200B}-1111\u{200B}-1111\u{200B}-1111 today."

    /// Base64-encoded URL — the redactor doesn't decode base64, so
    /// this fixture documents that limitation. The content base64-
    /// decodes to "https://apple-phish.example.com".
    static let edgeBase64URLBypass =
        "Click the link: aHR0cHM6Ly9hcHBsZS1waGlzaC5leGFtcGxlLmNvbQ== " +
        "to verify your account."

    /// Homograph attack — Cyrillic 'а' (U+0430) instead of Latin 'a' in
    /// "apple". Visually identical but a different code-point. The
    /// fixture also includes a recognisable English context so a
    /// model has something to grade.
    static let edgeHomographAttack =
        "Visit https://\u{0430}pple.com to verify your account. (The " +
        "first letter is Cyrillic.)"

    /// Mixed-script in a domain — uses Greek omicron in "support".
    static let edgeMixedScriptDomain =
        "Customer service: https://supp\u{03BF}rt.example.com/help"

    /// Punycode-shaped lookalike — `xn--` prefix often hides homograph
    /// payloads. The fixture is a placeholder; real punycode would
    /// resolve to a non-ASCII glyph.
    static let edgePunycodeLookalike =
        "Sign in to verify: https://xn--pple-43d.example.com/account"

    /// Single emoji input — a one-glyph prompt.
    static let edgeSingleEmoji = "🚨"

    /// Control characters embedded mid-string.
    static let edgeControlCharacters =
        "Verify your\u{0007}\u{0008} account at https://example.com\u{001B}/login"

    // MARK: - PII-leakage prevention

    /// Email-bearing phishing fixture — to confirm redaction happens
    /// before any bridge call.
    static let piiEmailInPhish =
        "Reply to security-team@example.org to reactivate your " +
        "account. Include your full name and account number."

    /// Phone-bearing fixture — synthetic 555-01XX range (reserved
    /// fictional / film-use; never a real subscriber). Formatted as a
    /// full North-American 10-digit number so the phone regex (three
    /// digit groups) can match.
    static let piiPhoneInBenign =
        "Call us at 415-555-0123 if you have any questions about your " +
        "order."

    /// SSN-bearing fixture — `123-45-XXXX` is the canonical SSN pattern
    /// used in test fixtures (the SSA's reserved-for-fiction `987-65-
    /// XXXX` range fails the redactor's area-code rule, which rejects
    /// 9XX prefixes per actual SSN-issuance policy). The four-digit
    /// serial is synthesised so the value is not a real allocated SSN.
    static let piiSSNInPhish =
        "We need to verify your identity. Please reply with your SSN " +
        "(123-45-6789) and date of birth to proceed."

    /// Mixed PII — email + phone + CC. Phone is formatted as a full
    /// 10-digit North-American number so it matches the redactor's
    /// 3-group pattern.
    static let piiMixedInPhish =
        "Account suspended. Email recovery@example.org or call " +
        "415-555-0199 with card 4111-1111-1111-1111 on file. Verify " +
        "within 24 hours."

    /// File path + bundle ID — Mac-specific PII.
    static let piiMacSpecific =
        "Please attach the crash report at /Users/jdoe/Library/Logs/" +
        "Diagnostics/com.apple.Mail.crash and send to support."

    /// API token in prompt — must never reach the bridge.
    static let piiAPITokenInPrompt =
        "I think my deploy is broken. Here's the env: Authorization: " +
        "Bearer sk-test-abcdefghijklmnopqrstuvwxyz0123456789 — can " +
        "you help?"

    /// IBAN in prompt.
    static let piiIBANInPrompt =
        "Wire transfer details: DE89 3704 0044 0532 0130 00 — confirm " +
        "the recipient name."

    /// IP address + MAC — network identifiers.
    static let piiNetworkIdentifiers =
        "Device at 192.168.1.42 with MAC 00:1A:2B:3C:4D:5E is " +
        "misbehaving on the network."

    /// GPS coordinates — location PII.
    static let piiGPSCoordinates =
        "I was at 37.7749, -122.4194 when the incident happened."

    /// Social handle — identity PII.
    static let piiSocialHandle =
        "DM me at @synthetic_test_user_2026 for the details."
}
