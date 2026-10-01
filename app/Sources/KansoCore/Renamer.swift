import Foundation
import NaturalLanguage
import PDFKit
import Vision

/// Deterministic check for names no person chose: scanner, camera and download patterns, bare numbers, UUIDs, timestamps.
public enum Meaningless {
    public static let patterns: [(label: String, regex: String)] = [
        ("Scan_####", #"^(scan|scanned|scansione|skanna)([ _-]?\d+)*$"#),
        ("IMG_####", #"^(img|image|dsc|dscn|dscf|pxl|mvimg|photo|pict?)[ _-]?\d+([ _-]\d+)*$"#),
        ("download (n)", #"^(download|downloads|file|attachment|document|doc)( ?\(\d+\)| ?\d+)?$"#),
        ("untitled", #"^(untitled|unbenannt|namnlös|sans titre)( ?\(\d+\)| ?\d+)?$"#),
        ("UUIDs", #"^[0-9a-f]{8}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{12}$|^[0-9a-f]{6,}(-[0-9a-f]{2,})*$"#),
        ("numbers", #"^[\d _.()-]+$"#),
    ]
    private static let compiled = patterns.map { try! NSRegularExpression(pattern: $0.regex, options: [.caseInsensitive]) }

    public static func check(_ stem: String, extra: [String] = [], disabled: [String] = []) -> Bool {
        let s = stem.trimmingCharacters(in: .whitespaces)
        let r = NSRange(s.startIndex..., in: s)
        if zip(patterns, compiled).contains(where: { !disabled.contains($0.0.label) && $0.1.firstMatch(in: s, range: r) != nil }) { return true }
        return extra.contains { fnmatch($0.lowercased(), s.lowercased(), 0) == 0 }
    }

    /// Which pattern matched, for "How Kanso decided" (Scanner names, Camera names, Download names).
    public static func label(_ stem: String) -> String? {
        let r = NSRange(stem.startIndex..., in: stem)
        return zip(patterns, compiled).first { $0.1.firstMatch(in: stem, range: r) != nil }?.0.label
    }
}

/// What reading a file found. Only the decision survives; the text itself is discarded.
public struct Extracted: Sendable, Equatable {
    public var kind: String?
    public var organization: String?
    public var date: Date?
    public var source: String  // "contents, page 1" / "contents (OCR)" / "from name"
    public init(kind: String?, organization: String?, date: Date?, source: String) {
        self.kind = kind; self.organization = organization; self.date = date; self.source = source
    }
}

public enum Reader {
    public static let maxChars = 2000
    static let readable: Set<String> = ["pdf", "txt", "md", "rtf", "doc", "docx", "odt", "pages", "jpg", "jpeg", "png", "heic", "tiff", "webp", "csv"]
    static let neverRead: Set<String> = [Shelf.keys]

    /// The first page or ~2,000 characters, never more. nil for types that are never read.
    public static func text(_ url: URL, shelf: String) -> (text: String, source: String)? {
        let ext = url.pathExtension.lowercased()
        guard readable.contains(ext), !neverRead.contains(shelf), !isPlaceholder(url),
              !url.pathComponents.contains(Library.manual) else { return nil }
        switch ext {
        case "pdf":
            guard let doc = PDFDocument(url: url) else { return nil }
            let pages = (0..<min(2, doc.pageCount)).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n")
            if pages.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let page = doc.page(at: 0) {
                let img = page.thumbnail(of: CGSize(width: 1400, height: 1800), for: .mediaBox)
                return img.cgImage(forProposedRect: nil, context: nil, hints: nil).flatMap(ocr).map { ($0, "contents (OCR)") }
            }
            return (String(pages.prefix(maxChars)), "contents, page 1")
        case "jpg", "jpeg", "png", "heic", "tiff", "webp":
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
            return ocr(img).map { ($0, "contents (OCR)") }
        case "txt", "md", "csv":
            guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? h.close() }
            let data = h.readData(ofLength: maxChars * 2)
            return (String(String(decoding: data, as: UTF8.self).prefix(maxChars)), ext == "csv" ? "contents, row 1" : "contents, page 1")
        default:
            guard let s = try? NSAttributedString(url: url, options: [:], documentAttributes: nil).string else { return nil }
            return (String(s.prefix(maxChars)), "contents, page 1")
        }
    }

    static func ocr(_ image: CGImage) -> String? {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage: image).perform([req])
        let s = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        return s.isEmpty ? nil : String(s.prefix(maxChars))
    }

    static func isPlaceholder(_ url: URL) -> Bool {
        let v = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        return v?.ubiquitousItemDownloadingStatus == .notDownloaded
    }

    /// Document kind by keywords (several languages), organization by NER, date by NSDataDetector.
    public static func extract(_ text: String, source: String, host: String? = nil) -> Extracted {
        Extracted(kind: kind(text), organization: organization(text) ?? org(fromHost: host), date: date(text), source: source)
    }

    static let kinds: [(String, [String])] = [
        ("Invoice", ["invoice", "rechnung", "faktura", "factura", "facture", "fattura", "tax invoice", "amount due"]),
        ("Receipt", ["receipt", "kvitto", "quittung", "kassenbon", "recibo", "reçu", "ricevuta", "thank you for your purchase"]),
        ("Ticket", ["boarding pass", "ticket", "biljett", "fahrkarte", "billet", "e-ticket", "gate", "seat"]),
        ("Payslip", ["payslip", "pay slip", "salary statement", "lönespecifikation", "gehaltsabrechnung", "net pay"]),
        ("Lease", ["lease agreement", "rental agreement", "hyresavtal", "mietvertrag", "tenancy"]),
        ("Contract", ["contract", "agreement", "avtal", "vertrag", "contrat", "terms and conditions"]),
        ("Statement", ["bank statement", "account statement", "kontoauszug", "kontoutdrag", "statement period"]),
        ("Insurance", ["insurance", "försäkring", "versicherung", "policy number", "assurance"]),
        ("Letter", ["dear ", "sehr geehrte", "hej ", "yours sincerely", "kind regards", "med vänliga", "letter", "brev", "beslut", "decision"]),
        ("CV", ["curriculum vitae", "resume", "work experience", "lebenslauf"]),
        ("Order", ["order confirmation", "order number", "bestellung", "orderbekräftelse"]),
    ]

    static func kind(_ text: String) -> String? {
        let t = text.lowercased()
        let scored = kinds.map { k in (k.0, k.1.reduce(0) { $0 + t.components(separatedBy: $1).count - 1 }) }
        return scored.filter { $0.1 > 0 }.max { $0.1 < $1.1 }?.0
    }

    static let legal: Set<String> = ["ab", "gmbh", "inc", "inc.", "ltd", "ltd.", "llc", "ag", "sa", "as", "oy", "bv", "nv", "plc", "co", "co.", "corp", "corp.", "&"]

    static let companyLine = try! NSRegularExpression(pattern: #"([A-ZÅÄÖÜ][\p{L}&.-]*(?: [A-ZÅÄÖÜ][\p{L}&.-]*){0,2}) (AB|GmbH|Inc\.?|Ltd\.?|LLC|AG|SA|Oy|AS|A/S|BV|NV|plc|Corporation|Corp\.?)\b"#)

    static func organization(_ text: String) -> String? {
        if let m = companyLine.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let r = Range(m.range(at: 1), in: text) {
            return clean(String(text[r]))
        }
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var counts: [String: Int] = [:]
        var order: [String] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType,
                             options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, range in
            if tag == .organizationName {
                let n = String(text[range])
                if counts[n] == nil { order.append(n) }
                counts[n, default: 0] += 1
            }
            return true
        }
        guard let best = order.max(by: { counts[$0]! < counts[$1]! }) else { return nil }
        return clean(best)
    }

    static func org(fromHost host: String?) -> String? {
        guard let host else { return nil }
        let generic: Set<String> = ["google", "googleusercontent", "gmail", "icloud", "apple", "dropbox", "amazonaws", "cloudfront", "github", "githubusercontent", "slack", "outlook", "live", "microsoft", "sharepoint", "wetransfer", "localhost"]
        let parts = host.lowercased().split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return nil }
        let name = parts[parts.count - 2]
        if generic.contains(name) || name.count < 2 { return nil }
        return name.count <= 3 ? name.uppercased() : clean(name)  // kth.se → KTH
    }

    static func clean(_ s: String) -> String? {
        let words = s.split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { !legal.contains($0.lowercased()) }
        let keep = words.first.map { $0.count >= 3 ? 1 : 2 } ?? 0  // "Telia Sverige" → Telia; "Circle K" → CircleK
        let joined = words.prefix(keep).map { w in
            if w.count <= 4 && w == w.uppercased() { return w }  // SJ, IKEA: acronyms stay
            let base = w == w.uppercased() ? w.lowercased() : w
            return base.prefix(1).uppercased() + base.dropFirst()
        }.joined()
        return joined.count >= 2 ? joined : nil
    }

    static let months = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december",
                         "januar", "februar", "märz", "mai", "juni", "juli", "oktober", "dezember", "januari", "februari", "mars", "maj", "augusti"]
    static let monthNumber: [String: Int] = ["januar": 1, "februar": 2, "märz": 3, "mai": 5, "juni": 6, "juli": 7, "oktober": 10, "dezember": 12,
                                             "januari": 1, "februari": 2, "mars": 3, "maj": 5, "augusti": 8]
    static let monthYear = try! NSRegularExpression(pattern: "\\b(" + months.joined(separator: "|") + ")\\s+(20\\d\\d)\\b", options: .caseInsensitive)

    static func date(_ text: String) -> Date? {
        let d = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let dates = d?.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.date) ?? []
        // A detected "today" or relative time is not a document date.
        if let found = dates.first(where: { abs($0.timeIntervalSinceNow) > 3600 && $0 < Date().addingTimeInterval(400 * 86400) }) { return found }
        // "September 2026" (no day) is common on payslips and statements.
        guard let m = monthYear.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let mr = Range(m.range(at: 1), in: text), let yr = Range(m.range(at: 2), in: text) else { return nil }
        let name = text[mr].lowercased()
        let month = months.firstIndex(of: name).flatMap { $0 < 12 ? $0 + 1 : nil } ?? monthNumber[name] ?? 1
        return Calendar.current.date(from: DateComponents(year: Int(text[yr]), month: month, day: 1))
    }
}

public enum Renamer {
    /// `Invoice-Vattenfall-2026-03.pdf`, or nil when there isn't enough to say (a kind plus an organization or date).
    public static func name(_ e: Extracted, ext: String, separator: String = "-", dateFormat: String = "yyyy-MM", parts order: [String] = ["kind", "organization", "date"]) -> String? {
        guard let kind = e.kind, e.organization != nil || e.date != nil else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = dateFormat == "MMM yyyy" ? "MMM-yyyy" : dateFormat
        let by = ["kind": kind, "organization": e.organization, "date": e.date.map { f.string(from: $0) }]
        let parts = order.compactMap { by[$0] ?? nil }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: separator) + (ext.isEmpty ? "" : ".\(ext)")
    }

    /// Stores the original name in an xattr and Finder comment, so Spotlight still finds it and undo can restore it.
    public static func keepOriginal(_ url: URL, _ original: String) {
        Xattr.setPlist(url, "com.apple.metadata:kMDItemFinderComment", "Originally \(original)")
        Xattr.setPlist(url, "app.kanso.original-name", original)
    }
}
