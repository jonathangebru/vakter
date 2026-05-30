// Main.swift
//
// CLI entry point. Reads config from env vars and command-line flags,
// runs the publisher, prints a one-line summary.
//
//   Usage:
//     vakter-threat-feed-publisher \
//       --out out/v1 \
//       --key-id vakter-feed-2026-q2 \
//       [--dry-run] \
//       [--apple-fakes-path /path/to/manual.txt]
//
//   Env (required in CI):
//     THREAT_FEED_ED25519_PRIVATE = PEM or 64-hex Ed25519 private key.
//
//   --dry-run: skip network and use built-in fixtures so a CI smoke run
//   can confirm the pipeline end-to-end without depending on PhishTank
//   being up.

import Foundation

@main
struct CLI {
    static func main() {
        do {
            try run(args: Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(
                ("vakter-threat-feed-publisher: error: \(error)\n").data(using: .utf8) ?? Data()
            )
            exit(1)
        }
    }

    static func run(args: [String]) throws {
        var outPath = "out/v1"
        var keyID = "vakter-feed-2026-q2"
        var dryRun = false
        var applePath: String? = nil
        var i = 0
        while i < args.count {
            let a = args[i]
            switch a {
            case "--out":
                i += 1; outPath = args[i]
            case "--key-id":
                i += 1; keyID = args[i]
            case "--dry-run":
                dryRun = true
            case "--apple-fakes-path":
                i += 1; applePath = args[i]
            case "-h", "--help":
                print(helpText)
                return
            default:
                throw CLIError.unknownArgument(a)
            }
            i += 1
        }

        let outURL = URL(fileURLWithPath: outPath)

        // Resolve apple-fakes-path: explicit flag wins, else look in the
        // sources/ sibling directory of the publisher's package.
        let apple = applePath.map(URL.init(fileURLWithPath:))
            ?? defaultAppleFakesPath()

        // Resolve signing key. In dry-run mode we generate a one-shot key.
        let signer: Signer
        if dryRun {
            signer = Signer(key: .init())
            FileHandle.standardError.write(
                Data("vakter-threat-feed-publisher: dry-run: using ephemeral signing key\n".utf8)
            )
        } else {
            guard let raw = ProcessInfo.processInfo.environment["THREAT_FEED_ED25519_PRIVATE"],
                  !raw.isEmpty else {
                throw CLIError.missingEnv("THREAT_FEED_ED25519_PRIVATE")
            }
            signer = try Signer.from(material: raw)
        }

        // Adapters: live URLSession by default, fixtures in dry-run.
        let phishtankFetcher: FetcherProtocol
        let urlhausFetcher: FetcherProtocol
        let fccFetcher: FetcherProtocol
        if dryRun {
            phishtankFetcher = FixtureFetcher([PhishTankAdapter.url: dryRunPhishTankFixture()])
            urlhausFetcher = FixtureFetcher([URLhausAdapter.url: dryRunURLhausFixture()])
            fccFetcher = FixtureFetcher([FCCRobocallAdapter.url: dryRunFCCFixture()])
        } else {
            phishtankFetcher = URLSessionFetcher()
            urlhausFetcher = URLSessionFetcher()
            fccFetcher = URLSessionFetcher()
        }

        let config = PublisherConfig(
            outputDirectory: outURL,
            bundleDate: Date(),
            feedHost: "feed.vakter.app",
            publisherKeyID: keyID,
            schemaVersion: 1,
            phishTank: PhishTankAdapter(fetcher: phishtankFetcher),
            urlHaus: URLhausAdapter(fetcher: urlhausFetcher),
            fccRobocall: FCCRobocallAdapter(fetcher: fccFetcher),
            appleSupportFakes: AppleSupportFakesAdapter(path: apple),
            previousBundleVersion: nil,
            previousBundleSHA256: nil,
            signer: signer
        )

        let result = try Publisher(config).run()

        // One-line summary on stdout. CI scrapes this for the run log.
        let summary: [String: Any] = [
            "bundle_version": result.bundleVersion,
            "tarball_sha256": result.tarballSHA256,
            "manifest_sha256": result.manifestSHA256,
            "total_entry_count": result.manifest.total_entry_count,
            "files": result.manifest.files.map { ["name": $0.name, "entry_count": $0.entry_count] }
        ]
        let json = try JSONSerialization.data(
            withJSONObject: summary,
            options: [.sortedKeys, .prettyPrinted]
        )
        FileHandle.standardOutput.write(json)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    static func defaultAppleFakesPath() -> URL {
        // The CLI binary lives in `.build/<config>/vakter-threat-feed-publisher`;
        // the sources/ directory is two parents up from the package root.
        // We resolve relative to the current working directory by default so
        // running from the repo root works.
        return URL(fileURLWithPath: "Anchor/threat-feed/sources/apple-support-fakes-manual.txt")
    }
}

enum CLIError: Error, CustomStringConvertible {
    case unknownArgument(String)
    case missingEnv(String)

    var description: String {
        switch self {
        case .unknownArgument(let a): return "Unknown argument: \(a)"
        case .missingEnv(let e): return "Required environment variable not set: \(e)"
        }
    }
}

let helpText = """
vakter-threat-feed-publisher

  --out <dir>             Output directory (default: out/v1)
  --key-id <id>           publisher_key_id (default: vakter-feed-2026-q2)
  --apple-fakes-path <p>  Path to apple-support-fakes-manual.txt
  --dry-run               Use fixtures instead of live network. Ephemeral key.
  -h, --help              Show this help.

Env (live runs only):
  THREAT_FEED_ED25519_PRIVATE   PEM or 64-hex Ed25519 private key.
"""

// MARK: - Dry-run fixtures

func dryRunPhishTankFixture() -> Data {
    let csv = """
phish_id,url,phish_detail_url,submission_time,verified,verification_time,online,target
1,https://apple-id-verify.example/login,...,2026-05-29T05:00:00Z,yes,...,yes,Apple
2,https://wells-fargo-secure.example/x,...,2026-05-29T05:01:00Z,yes,...,yes,Wells Fargo
"""
    return csv.data(using: .utf8)!
}

func dryRunURLhausFixture() -> Data {
    let csv = """
# URLhaus dry-run fixture
"1","2026-05-29 05:00:00","https://malware-host.example/dropper.exe","online","","exe","tag","https://urlhaus","reporter"
"2","2026-05-29 05:01:00","https://shipping-track.example/pkg","online","","js","tag","https://urlhaus","reporter"
"""
    return csv.data(using: .utf8)!
}

func dryRunFCCFixture() -> Data {
    let csv = """
ticket_id,caller_id_number,issue
1,8005551234,Unwanted call
2,(415) 555-9876,Unwanted call
3,18475550000,Unwanted call
"""
    return csv.data(using: .utf8)!
}
