import AppKit
import WebKit

/// Enregistre une page web (lien glissé) : PDF d'une seule longue page, texte en Markdown, ou capture d'écran de toute la page.
/// La page est chargée par WebKit dans une fenêtre invisible, comme Safari (sans cookies ni connexions : c'est la page publique).
enum WebCaptureKind {
    case pdf, markdown, screenshot
    var ext: String { self == .pdf ? "pdf" : (self == .markdown ? "md" : "png") }
    var jobTitle: String { self == .pdf ? "Saving page as PDF…" : (self == .markdown ? "Saving page as Markdown…" : "Saving screenshot…") }
}

@MainActor
final class WebCapture: NSObject, WKNavigationDelegate {
    static let width: CGFloat = 1280
    static let maxHeight: CGFloat = 14000          // au-delà, un PDF ou une image deviennent ingérables : la page est coupée là

    private var webView: WKWebView!
    private var window: NSWindow!
    private var loaded: CheckedContinuation<Void, Error>?

    /// Charge `link`, produit le fichier dans `folder` et le renvoie.
    static func save(_ link: URL, as kind: WebCaptureKind, to folder: URL) async throws -> URL {
        let job = WebCapture()
        defer { job.window.close() }
        try await job.load(link)
        try Task.checkCancellation()
        let title = (try? await job.webView.evaluateJavaScript("document.title") as? String) ?? ""
        let base = Self.fileName(title: title, link: link)
        let out = OutputNaming.unique(folder: folder, base: base, ext: kind.ext)
        switch kind {
        case .markdown:
            let md = try await job.markdown(title: title, link: link)
            try md.write(to: out, atomically: true, encoding: .utf8)
        case .pdf, .screenshot:
            let height = try await job.prepareFullPage()
            try Task.checkCancellation()
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            if kind == .pdf {
                let cfg = WKPDFConfiguration(); cfg.rect = rect
                try await job.webView.pdf(configuration: cfg).write(to: out)
            } else {
                let cfg = WKSnapshotConfiguration(); cfg.rect = rect; cfg.snapshotWidth = NSNumber(value: Double(width))
                let image = try await job.webView.takeSnapshot(configuration: cfg)
                guard let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
                else { throw MandarineError(L("Couldn't render the page as an image.")) }
                try png.write(to: out)
            }
        }
        return out
    }

    private override init() {
        super.init()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: Self.width, height: 900), configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
        webView.navigationDelegate = self
        // une fenêtre hors de l'écran : WebKit ne dessine que les vues qui sont dans une fenêtre
        window = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: Self.width, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.orderBack(nil)
    }

    private func load(_ link: URL) async throws {
        webView.load(URLRequest(url: link, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30))
        let timeout = Task { @MainActor in
            try await Task.sleep(nanoseconds: 45_000_000_000)
            self.finish(.failure(MandarineError(L("The page took too long to load."))))
        }
        defer { timeout.cancel() }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in loaded = c }
        // laisse la page finir de s'afficher (scripts, polices, images de premier plan)
        try await Task.sleep(nanoseconds: 1_200_000_000)
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let c = loaded else { return }
        loaded = nil
        c.resume(with: result)
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { Task { @MainActor in self.finish(.success(())) } }
    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { Task { @MainActor in self.finish(.failure(error)) } }
    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { Task { @MainActor in self.finish(.failure(error)) } }

    /// Fait défiler la page pour charger les images différées, retire bandeaux de cookies et fenêtres surgissantes, puis donne à la vue
    /// la hauteur de toute la page. Renvoie cette hauteur.
    private func prepareFullPage() async throws -> CGFloat {
        let script = #"""
        const bad = /cookie|consent|gdpr|onetrust|didomi|cmp-|newsletter|popup|modal|overlay|paywall/i;
        document.querySelectorAll('body *').forEach(e => {
          const s = getComputedStyle(e);
          if ((s.position === 'fixed' || s.position === 'sticky') && (bad.test(e.id) || bad.test(e.className && e.className.toString()))) e.remove();
        });
        document.documentElement.style.overflow = 'visible'; document.body.style.overflow = 'visible';
        const height = () => Math.max(document.body.scrollHeight, document.documentElement.scrollHeight);
        let y = 0; const step = Math.max(400, innerHeight * 0.8), limit = Math.min(height(), 15000);
        while (y < limit) { window.scrollTo(0, y); await new Promise(r => setTimeout(r, 110)); y += step; }
        window.scrollTo(0, 0); await new Promise(r => setTimeout(r, 300));
        return height();
        """#
        let value = try await webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page)
        let h = min(max((value as? NSNumber)?.doubleValue ?? 900, 300), Double(Self.maxHeight))
        window.setContentSize(NSSize(width: Self.width, height: h))
        webView.frame = NSRect(x: 0, y: 0, width: Self.width, height: h)
        try await Task.sleep(nanoseconds: 600_000_000)
        return CGFloat(h)
    }

    private func markdown(title: String, link: URL) async throws -> String {
        let body = try await webView.callAsyncJavaScript(Self.markdownScript, arguments: [:], in: nil, contentWorld: .page) as? String ?? ""
        guard body.trimmingCharacters(in: .whitespacesAndNewlines).count > 20 else { throw MandarineError(L("No readable text found on this page.")) }
        let source = "> Source: " + link.absoluteString
        // la page commence déjà par son titre (h1) : on met la source juste dessous, sans répéter le titre
        if body.hasPrefix("# "), let end = body.range(of: "\n\n") {
            let heading = String(body[..<end.lowerBound])
            let rest = String(body[end.upperBound...])
            return heading + "\n\n" + source + "\n\n" + rest + "\n"
        }
        let heading = "# " + (title.isEmpty ? (link.host ?? "Page") : title)
        return heading + "\n\n" + source + "\n\n" + body + "\n"
    }

    /// Nom de fichier lisible d'après le titre de la page.
    static func fileName(title: String, link: URL) -> String {
        let bad = CharacterSet(charactersIn: "/:\\?%*|\"<>\n\r\t")
        var name = title.components(separatedBy: bad).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        while name.contains("  ") { name = name.replacingOccurrences(of: "  ", with: " ") }
        if name.isEmpty { name = (link.host ?? "page").replacingOccurrences(of: "www.", with: "") }
        return String(name.prefix(80)).trimmingCharacters(in: .whitespaces)
    }

    /// Extrait le texte principal de la page (article, sinon le bloc qui contient le plus de paragraphes) et le convertit en Markdown.
    private static let markdownScript = #"""
    const SKIP = new Set(['SCRIPT','STYLE','NOSCRIPT','NAV','FOOTER','ASIDE','FORM','IFRAME','SVG','BUTTON','SELECT','INPUT','TEXTAREA','CANVAS','VIDEO','AUDIO','TEMPLATE']);
    const hidden = e => e.hidden || e.getAttribute('aria-hidden') === 'true' || getComputedStyle(e).display === 'none';
    const textLen = e => (e.innerText || '').trim().length;

    function mainNode() {
      const article = [...document.querySelectorAll('article')].sort((a, b) => textLen(b) - textLen(a))[0];
      if (article && textLen(article) > 600) return article;
      const scores = new Map();
      document.querySelectorAll('p').forEach(p => {
        const n = (p.innerText || '').trim().length;
        if (n < 40) return;
        const a = p.parentElement, b = a && a.parentElement;
        if (a) scores.set(a, (scores.get(a) || 0) + n);
        if (b) scores.set(b, (scores.get(b) || 0) + n / 2);
      });
      let best = null, bestScore = 0;
      scores.forEach((v, k) => { if (v > bestScore) { best = k; bestScore = v; } });
      return best || document.querySelector('main, [role=main]') || document.body;
    }

    const clean = s => s.replace(/\s+/g, ' ');
    function inline(node) {
      let out = '';
      node.childNodes.forEach(c => {
        if (c.nodeType === 3) { out += clean(c.textContent); return; }
        if (c.nodeType !== 1 || SKIP.has(c.tagName) || hidden(c)) return;
        const t = c.tagName;
        if (t === 'UL' || t === 'OL') return;          // listes imbriquées : écrites par block()
        const inner = () => inline(c);
        if (t === 'BR') out += '  \n';
        else if (t === 'STRONG' || t === 'B') { const s = inner().trim(); if (s) out += '**' + s + '**'; }
        else if (t === 'EM' || t === 'I') { const s = inner().trim(); if (s) out += '*' + s + '*'; }
        else if (t === 'CODE') out += '`' + c.textContent + '`';
        else if (t === 'A') { const s = inner().trim(); out += c.href && s && !c.href.startsWith('javascript:') ? '[' + s + '](' + c.href + ')' : s; }
        else if (t === 'IMG') { const src = c.currentSrc || c.src; if (src && !src.startsWith('data:')) out += '![' + (c.alt || '') + '](' + src + ')'; }
        else out += inner();
      });
      return out;
    }

    function block(node, depth) {
      let out = '';
      node.childNodes.forEach(c => {
        if (c.nodeType === 3) { const s = clean(c.textContent).trim(); if (s) out += s + ' '; return; }
        if (c.nodeType !== 1 || SKIP.has(c.tagName) || hidden(c)) return;
        const t = c.tagName;
        if (/^H[1-6]$/.test(t)) { const s = inline(c).trim(); if (s) out += '\n\n' + '#'.repeat(+t[1]) + ' ' + s + '\n\n'; }
        else if (t === 'P') { const s = inline(c).trim(); if (s) out += '\n\n' + s + '\n\n'; }
        else if (t === 'UL' || t === 'OL') {
          let i = 1; if (depth === 0) out += '\n';
          c.querySelectorAll(':scope > li').forEach(li => {
            const mark = t === 'OL' ? (i++) + '. ' : '- ';
            const s = inline(li).trim().replace(/\n+/g, ' ');
            if (s) out += '  '.repeat(depth) + mark + s + '\n';
            li.querySelectorAll(':scope > ul, :scope > ol').forEach(sub => { out += block(sub.parentNode === li ? wrap(sub) : sub, depth + 1); });
          });
          if (depth === 0) out += '\n';
        }
        else if (t === 'PRE') out += '\n\n```\n' + c.textContent.replace(/\n+$/, '') + '\n```\n\n';
        else if (t === 'BLOCKQUOTE') { const s = block(c, depth).trim(); if (s) out += '\n\n' + s.split('\n').map(l => '> ' + l).join('\n') + '\n\n'; }
        else if (t === 'HR') out += '\n\n---\n\n';
        else if (t === 'TABLE') {
          const rows = [...c.querySelectorAll('tr')].map(tr => [...tr.children].map(td => inline(td).trim().replace(/\|/g, '\\|').replace(/\n+/g, ' ')));
          if (rows.length) {
            const w = Math.max(...rows.map(r => r.length));
            const line = r => '| ' + Array.from({ length: w }, (_, i) => r[i] || '').join(' | ') + ' |';
            out += '\n\n' + line(rows[0]) + '\n| ' + Array(w).fill('---').join(' | ') + ' |\n' + rows.slice(1).map(line).join('\n') + '\n\n';
          }
        }
        else if (t === 'FIGURE') { out += block(c, depth); }
        else if (t === 'FIGCAPTION') { const s = inline(c).trim(); if (s) out += '\n\n*' + s + '*\n\n'; }
        else if (t === 'IMG') { const s = inline({ childNodes: [c] }).trim(); if (s) out += '\n\n' + s + '\n\n'; }
        else if (/^(DIV|SECTION|ARTICLE|MAIN|HEADER|SPAN|A|LI|DL|DD|DT|CENTER|DETAILS|SUMMARY)$/.test(t)) {
          const hasBlocks = c.querySelector('p, h1, h2, h3, h4, h5, h6, ul, ol, pre, blockquote, table, figure, div, section');
          if (hasBlocks) out += block(c, depth);
          else { const s = inline(c).trim(); if (s) out += '\n\n' + s + '\n\n'; }
        }
        else { const s = inline(c).trim(); if (s) out += s + ' '; }
      });
      return out;
    }
    function wrap(el) { const d = document.createElement('div'); d.appendChild(el.cloneNode(true)); return d; }

    const root = mainNode();
    return block(root, 0).replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n').trim();
    """#
}
