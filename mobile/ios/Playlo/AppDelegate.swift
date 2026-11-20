import UIKit
import WebKit
import Darwin
import Security

/// Public YouTube content is isolated from the Playlo session and native message bridge.
final class PlayloYouTubeScreen: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private let videoId: String
    private var identityHost: String { (Bundle.main.bundleIdentifier ?? "nl.playlo.app").lowercased() }
    private var player: WKWebView!
    private var background: NSObjectProtocol?
    init(videoId: String) { self.videoId = videoId; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    override var prefersStatusBarHidden: Bool { true }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Hits & clips"
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "‹ Muziek", style: .plain, target: self, action: #selector(closePlayer))
        view.backgroundColor = UIColor(red: 0.047, green: 0.063, blue: 0.137, alpha: 1)
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent(); config.allowsInlineMediaPlayback = true; config.mediaTypesRequiringUserActionForPlayback = .all
        player = WKWebView(frame: .zero, configuration: config); player.navigationDelegate = self; player.uiDelegate = self; player.isOpaque = false; player.backgroundColor = view.backgroundColor; player.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(player)
        NSLayoutConstraint.activate([player.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor), player.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor), player.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), player.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)])
        guard videoId.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil, let file = Bundle.main.url(forResource: "youtube-player", withExtension: "html", subdirectory: "Shared"), let html = try? String(contentsOf: file, encoding: .utf8) else { let label = UILabel(); label.text = "Spelerbestand ontbreekt. Installeer de app opnieuw."; label.textColor = .white; label.numberOfLines = 0; label.frame = view.bounds.insetBy(dx: 24, dy: 60); view.addSubview(label); return }
        guard identityHost.range(of: "^[a-z0-9.-]+$", options: .regularExpression) != nil else { return }
        let identityOrigin = "https://" + identityHost
        player.loadHTMLString(html.replacingOccurrences(of: "{{VIDEO_ID}}", with: videoId).replacingOccurrences(of: "{{APP_ORIGIN}}", with: identityOrigin), baseURL: URL(string: identityOrigin + "/"))
        #if DEBUG
        if CommandLine.arguments.contains("--playlo-youtube-smoke") { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.recordPlayerSmoke(0) } }
        #endif
        background = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in DispatchQueue.main.async { self?.pause() } }
    }
    #if DEBUG
    private func recordPlayerSmoke(_ attempt: Int) {
        let script = "(()=>{const f=document.querySelector('iframe'),r=f?.getBoundingClientRect();return {text:document.getElementById('status')?.textContent||'',origin:location.origin,iframe:f?.src||'',width:r?.width||0,height:r?.height||0,hasAccountBridge:!!window.webkit?.messageHandlers?.PlayloNative}})()"
        player.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            let info = value as? [String: Any] ?? [:]
            let text = info["text"] as? String ?? ""
            let ready = text.hasPrefix("Klaar.")
            if !ready && attempt < 50 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.recordPlayerSmoke(attempt + 1) }; return }
            let correctOrigin = info["origin"] as? String == "https://" + self.identityHost
            let isolated = info["hasAccountBridge"] as? Bool == false
            let fits = (info["width"] as? Double ?? 0) >= 200 && (info["height"] as? Double ?? 0) >= 200
            var report = info; report["status"] = ready && correctOrigin && isolated && fits && error == nil ? "PASS" : "FAIL"
            report["nativeController"] = "PlayloYouTubeScreen"; report["playbackTested"] = false
            if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first, let data = try? JSONSerialization.data(withJSONObject: report, options: .prettyPrinted) { try? data.write(to: directory.appendingPathComponent("Playlo-native-youtube.json")) }
        }
    }
    #endif
    @objc private func closePlayer() { navigationController?.popViewController(animated: true) }
    private func pause() { player?.evaluateJavaScript("window.playloPause&&window.playloPause()", completionHandler: nil) }
    override func viewWillDisappear(_ animated: Bool) { if isMovingFromParent || isBeingDismissed || navigationController?.isBeingDismissed == true { pause() }; super.viewWillDisappear(animated) }
    deinit { if let background { NotificationCenter.default.removeObserver(background) } }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if action.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
        if url.absoluteString == "about:blank" || (url.scheme == "https" && url.host == identityHost && url.user == nil && (url.port == nil || url.port == 443)) { decisionHandler(.allow); return }
        decisionHandler(.cancel)
        if action.navigationType == .linkActivated, url.scheme == "https", url.user == nil { confirmExternal(url) }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url, url.scheme == "https", url.user == nil { confirmExternal(url) }; return nil
    }
    private func confirmExternal(_ url: URL) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: "Playlo verlaten?", message: "Alleen deze gekozen link opent buiten Playlo. Je muziekselectie blijft bewaard.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "In Playlo blijven", style: .cancel)); alert.addAction(UIAlertAction(title: "Link openen", style: .default) { _ in UIApplication.shared.open(url) }); present(alert, animated: true)
    }
}

final class AppNetworkResult: @unchecked Sendable { var data: Data?; var response: HTTPURLResponse?; var error: Error? }
final class AppApiClient: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = AppApiClient()
    private let queue = DispatchQueue(label: "nl.playlo.app-api")
    private let origin: URL?
    private lazy var session: URLSession = { let config = URLSessionConfiguration.ephemeral; config.httpCookieStorage = nil; config.httpShouldSetCookies = false; config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 20; return URLSession(configuration: config, delegate: self, delegateQueue: nil) }()
    override init() { if let file = Bundle.main.url(forResource: "app-online", withExtension: "json", subdirectory: "Shared/Web"), let data = try? Data(contentsOf: file), let config = try? JSONSerialization.jsonObject(with: data) as? [String: String], let raw = config["apiOrigin"], let url = URL(string: raw), url.scheme == "https", url.host != nil, url.user == nil, url.port == nil, url.query == nil, url.path.isEmpty { origin = url } else { origin = nil }; super.init() }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    private func cookie() throws -> String { guard let origin else { return "" }; let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"nl.playlo.app-api",kSecAttrAccount as String:origin.absoluteString,kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne];var found: CFTypeRef?;let status = SecItemCopyMatching(query as CFDictionary,&found);if status == errSecItemNotFound { return "" };guard status == errSecSuccess, let data = found as? Data, let value = String(data: data,encoding: .utf8) else { throw NSError(domain:"PlayloSession",code:Int(status)) };return value }
    private func cookie(_ value: String) throws { guard let origin else { return };let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"nl.playlo.app-api",kSecAttrAccount as String:origin.absoluteString];let change = [kSecValueData as String:Data(value.utf8)];var status = SecItemUpdate(query as CFDictionary,change as CFDictionary);if status == errSecItemNotFound { var insert = query;insert[kSecValueData as String] = Data(value.utf8);insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;status = SecItemAdd(insert as CFDictionary,nil) };guard status == errSecSuccess else { throw NSError(domain:"PlayloSession",code:Int(status)) } }
    func send(_ message: [String: Any], completion: @escaping ([String: Any]) -> Void) {
        queue.async { [self] in
            let id = message["id"] as? String ?? ""
            do {
                guard id.range(of:"^[a-f0-9-]{36}$",options:.regularExpression) != nil, let origin, let path = message["path"] as? String, path.hasPrefix("/api/"), !path.contains("\\"), !path.contains("\n"), !path.contains("\r"), let url = URL(string:path,relativeTo:origin)?.absoluteURL, url.host == origin.host, url.scheme == "https" else { throw NSError(domain:"PlayloAPI",code:1) }
                let method = message["method"] as? String ?? "GET";guard ["GET","POST"].contains(method) else { throw NSError(domain:"PlayloAPI",code:2) }
                let body = Data((message["body"] as? String ?? "").utf8);guard body.count <= 1250000 else { throw NSError(domain:"PlayloAPI",code:3) }
                var request = URLRequest(url:url);request.httpMethod = method;request.setValue(origin.absoluteString,forHTTPHeaderField:"Origin");request.setValue("application/json",forHTTPHeaderField:"Content-Type");let saved = try cookie();if !saved.isEmpty { request.setValue(saved,forHTTPHeaderField:"Cookie") };if let nonce = message["nonce"] as? String,nonce.range(of:"^[a-f0-9-]{36}$",options:.regularExpression) != nil { request.setValue(nonce,forHTTPHeaderField:"Idempotency-Key") };if method == "POST" { request.httpBody = body }
                let result = AppNetworkResult(), ready = DispatchSemaphore(value:0)
                let task = session.dataTask(with:request) { data,response,error in result.data = data;result.response = response as? HTTPURLResponse;result.error = error;ready.signal() };task.resume()
                guard ready.wait(timeout:.now()+22) == .success,result.error == nil,let response = result.response else { task.cancel();throw NSError(domain:"PlayloAPI",code:4) }
                let bytes = result.data ?? Data();guard bytes.count <= 4*1024*1024 else { throw NSError(domain:"PlayloAPI",code:5) }
                if let header = response.value(forHTTPHeaderField:"Set-Cookie"),let range = header.range(of:"__Host-playlo_session=[a-f0-9]{64}",options:.regularExpression) { try cookie(String(header[range])) }
                completion(["id":id,"status":response.statusCode,"mime":response.value(forHTTPHeaderField:"Content-Type") ?? "application/json","data":bytes.base64EncodedString()])
            } catch { completion(["id":id,"error":"De Playlo-server is niet bereikbaar. Je lokale code blijft bewaard; probeer opnieuw of kies offline spelen."]) }
        }
    }
}

/// Serves only packaged resources on loopback. No API, account data, or LAN listener.
final class PlayloBundleServer {
    private let listener: Int32
    private let directory: URL
    init() throws {
        guard let directory = Bundle.main.url(forResource: "Web", withExtension: nil, subdirectory: "Shared"), FileManager.default.fileExists(atPath: directory.appendingPathComponent("bundle-manifest.json").path) else { throw NSError(domain: "PlayloBundle", code: 1) }
        self.directory = directory.standardizedFileURL
        listener = socket(AF_INET, SOCK_STREAM, 0)
        guard listener >= 0 else { throw NSError(domain: "PlayloBundle", code: 2) }
        var one: Int32 = 1; setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout.size(ofValue: one)))
        var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); address.sin_family = sa_family_t(AF_INET); address.sin_port = UInt16(41837).bigEndian; address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) { pointer in pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard bound == 0, Darwin.listen(listener, 16) == 0 else { Darwin.close(listener); throw NSError(domain: "PlayloBundle", code: 3) }
        let descriptor = listener, base = self.directory
        DispatchQueue.global(qos: .userInitiated).async {
            while true { let client = Darwin.accept(descriptor, nil, nil); if client < 0 { break }; DispatchQueue.global(qos: .userInitiated).async { Self.serve(client, directory: base) } }
        }
    }
    private static func serve(_ client: Int32, directory: URL) {
        defer { Darwin.close(client) }
        var one: Int32 = 1; setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout.size(ofValue: one)))
        var timeout = timeval(tv_sec: 5, tv_usec: 0); setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        var request = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while request.count < 8192 { let count = Darwin.recv(client, &buffer, buffer.count, 0); if count <= 0 { return }; request.append(contentsOf: buffer.prefix(count)); if request.range(of: Data("\r\n\r\n".utf8)) != nil { break } }
        guard let text = String(data: request, encoding: .utf8), let first = text.components(separatedBy: "\r\n").first else { return }
        let pieces = first.split(separator: " "); guard pieces.count == 3, ["GET", "HEAD"].contains(String(pieces[0])), pieces[1].hasPrefix("/"), !pieces[1].hasPrefix("//") else { return }
        let headers = text.components(separatedBy: "\r\n").dropFirst().compactMap { line -> (String, String)? in guard let colon = line.firstIndex(of: ":") else { return nil }; return (String(line[..<colon]).lowercased(), line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)) }
        guard headers.contains(where: { $0.0 == "host" && $0.1 == "localhost:41837" }) else { return }
        guard let url = URL(string: "http://localhost:41837" + pieces[1]), let decoded = url.path.removingPercentEncoding, !decoded.contains("\0"), !decoded.split(separator: "/").contains("..") else { return }
        let file = directory.appendingPathComponent(decoded == "/" ? "index.html" : String(decoded.dropFirst())).standardizedFileURL
        guard file.path.hasPrefix(directory.path + "/") else { return }
        let data = try? Data(contentsOf: file), status = data == nil ? "404 Not Found" : "200 OK"
        let types = ["html":"text/html; charset=utf-8", "js":"text/javascript", "css":"text/css", "json":"application/json", "wasm":"application/wasm", "svg":"image/svg+xml", "png":"image/png", "webp":"image/webp", "jpg":"image/jpeg", "jpeg":"image/jpeg", "woff2":"font/woff2"]
        let body = data ?? Data(), header = "HTTP/1.1 \(status)\r\nContent-Type: \(types[file.pathExtension] ?? "application/octet-stream")\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n"
        func send(_ data: Data) { data.withUnsafeBytes { bytes in guard let base = bytes.baseAddress else { return }; var offset = 0; while offset < data.count { let count = Darwin.send(client, base.advanced(by: offset), data.count - offset, 0); if count <= 0 { break }; offset += count } } }
        send(Data(header.utf8)); if pieces[0] != "HEAD" { send(body) }
    }
    deinit { Darwin.shutdown(listener, SHUT_RDWR); Darwin.close(listener) }
}

final class PlayloMessageReceiver: NSObject, WKScriptMessageHandler {
    weak var target: PlayloScreen?
    init(_ target: PlayloScreen) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) { target?.userContentController(userContentController, didReceive: message) }
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var bundleServer: PlayloBundleServer?
    func applicationDidBecomeActive(_ application: UIApplication) { ((window?.rootViewController as? UINavigationController)?.topViewController as? PlayloScreen)?.resumeWeb() }
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool { guard url.scheme == "playlo-native", url.host == "resume" else { return false }; applicationDidBecomeActive(app); return true }
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        do { bundleServer = try PlayloBundleServer() } catch {
            let window = UIWindow(frame: UIScreen.main.bounds), controller = UIViewController(), label = UILabel()
            controller.view.backgroundColor = .systemBackground; label.text = "Playlo kon de lokale spellen niet openen. Sluit de app en probeer opnieuw."; label.numberOfLines = 0; label.frame = CGRect(x: 24, y: 100, width: window.bounds.width - 48, height: 200); controller.view.addSubview(label); window.rootViewController = controller; window.makeKeyAndVisible(); self.window = window; return true
        }
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UINavigationController(rootViewController: PlayloMenu())
        #if DEBUG
        if CommandLine.arguments.contains("--playlo-offline-smoke") { window.rootViewController = UINavigationController(rootViewController: PlayloScreen(url: PlayloConfig.origin)) }
        if CommandLine.arguments.contains("--playlo-youtube-smoke") { window.rootViewController = UINavigationController(rootViewController: PlayloYouTubeScreen(videoId: "6b78T9iOPfE")) }
        #endif
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

enum PlayloConfig {
    static let values: [String: Any] = {
        let url = Bundle.main.url(forResource: "app-shell", withExtension: "json", subdirectory: "Shared")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()
    static var origin: URL { URL(string: "http://localhost:41837")! }
    static var destinations: [[String: String]] { values["destinations"] as! [[String: String]] }
    static func trusted(_ url: URL) -> Bool {
        url.scheme == origin.scheme && url.host?.lowercased() == origin.host?.lowercased() && url.port == origin.port && url.user == nil && url.password == nil
    }
    static func asset(_ name: String, _ ext: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Shared"), let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }
}

final class PlayloMenu: UIViewController {
    private var screen: PlayloScreen?
    private let stack = UIStackView()
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Playlo"
        view.backgroundColor = UIColor(red: 0.078, green: 0.106, blue: 0.192, alpha: 1)
        let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(scroll)
        stack.axis = .vertical; stack.spacing = 18; stack.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 32), stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48)
        ])
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        for child in stack.arrangedSubviews { stack.removeArrangedSubview(child); child.removeFromSuperview() }
        let heading = UILabel(); heading.text = "Samen spelen. Zelf maken."; heading.textColor = .white; heading.font = .preferredFont(forTextStyle: .largeTitle); heading.adjustsFontForContentSizeCategory = true; heading.numberOfLines = 0; stack.addArrangedSubview(heading)
        if screen != nil { addButton("Terug naar je scherm") { [weak self] in guard let self, let screen = self.screen else { return }; self.navigationController?.pushViewController(screen, animated: true) } }
        for destination in PlayloConfig.destinations {
            addButton((destination["title"] ?? "Playlo") + "\n" + (destination["description"] ?? "")) { [weak self] in
                guard let self, let url = URL(string: destination["path"]!, relativeTo: PlayloConfig.origin)?.absoluteURL else { return }
                let open = { self.screen = PlayloScreen(url: url); self.navigationController?.pushViewController(self.screen!, animated: true) }
                if self.screen != nil { let alert = UIAlertController(title: "Ander scherm openen?", message: "Je verlaat het huidige scherm. Een online partij kan blijven doorlopen.", preferredStyle: .alert); alert.addAction(UIAlertAction(title: "Annuleren", style: .cancel)); alert.addAction(UIAlertAction(title: "Openen", style: .default) { _ in open() }); self.present(alert, animated: true) } else { open() }
            }
        }
        let note = UILabel(); note.text = "Alle 34 spellen in de app. Je account, online spelers en opgeslagen spellen zijn hetzelfde als op de Playlo-website."; note.textColor = .lightGray; note.numberOfLines = 0; note.font = .preferredFont(forTextStyle: .footnote); stack.addArrangedSubview(note)
    }
    private func addButton(_ title: String, action: @escaping () -> Void) {
        let button = UIButton(type: .system); var config = UIButton.Configuration.filled(); config.title = title; config.baseBackgroundColor = UIColor(red: 0.38, green: 0.29, blue: 0.72, alpha: 1); config.cornerStyle = .large; config.titleAlignment = .leading; config.image = UIImage(systemName: title.hasPrefix("Studio") ? "hammer.fill" : "gamecontroller.fill"); config.imagePadding = 16; config.contentInsets = NSDirectionalEdgeInsets(top: 18, leading: 16, bottom: 18, trailing: 16); button.configuration = config; button.titleLabel?.numberOfLines = 0; button.heightAnchor.constraint(greaterThanOrEqualToConstant: 58).isActive = true; button.addAction(UIAction { _ in action() }, for: .touchUpInside); stack.addArrangedSubview(button)
    }
}

final class PlayloScreen: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    private func debugProgress(_ stage: String) {
        #if DEBUG
        if CommandLine.arguments.contains("--playlo-offline-smoke"), let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first, let data = try? JSONSerialization.data(withJSONObject: ["stage":stage]) { try? FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true); try? data.write(to:directory.appendingPathComponent("Playlo-native-progress.json")) }
        #endif
    }
    private let initialURL: URL
    private var web: WKWebView!
    private var errorPanel: UIStackView?
    private var activity = UIActivityIndicatorView(style: .medium)
    private var exportURL: URL?
    init(url: URL) { initialURL = url; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    override var prefersStatusBarHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .bottom }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Playlo"; debugProgress("view-loaded")
        view.backgroundColor = UIColor(red: 0.078, green: 0.106, blue: 0.192, alpha: 1)
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Appmenu", style: .plain, target: self, action: #selector(menu))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Opnieuw", style: .plain, target: self, action: #selector(reload))
        let config = WKWebViewConfiguration(); config.websiteDataStore = .default(); config.allowsInlineMediaPlayback = true; config.applicationNameForUserAgent = "PlayloNative/1 iPhone"
        #if DEBUG
        if CommandLine.arguments.contains("--playlo-offline-smoke") { config.userContentController.addUserScript(WKUserScript(source: "localStorage.setItem('playlo-language','nl')", injectionTime: .atDocumentStart, forMainFrameOnly: true)) }
        #endif
        config.userContentController.addUserScript(WKUserScript(source: "window.PlayloNativeCapabilities={youtube:true}", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let shell = PlayloConfig.asset("shell", "js")
        config.userContentController.addUserScript(WKUserScript(source: shell, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let css = PlayloConfig.asset("game-screen", "css")
        if let encoded = try? JSONSerialization.data(withJSONObject: [css]), let literal = String(data: encoded, encoding: .utf8) {
            config.userContentController.addUserScript(WKUserScript(source: "(()=>{const s=document.createElement('style');s.textContent=(\(literal))[0];document.head.append(s)})()", injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        web = WKWebView(frame: .zero, configuration: config); web.navigationDelegate = self; web.uiDelegate = self; web.allowsBackForwardNavigationGestures = true; web.isOpaque = false; web.backgroundColor = view.backgroundColor; web.scrollView.contentInsetAdjustmentBehavior = .never; web.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(web)
        // The handler rejects non-main frames and foreign origins before accepting any file.
        config.userContentController.add(PlayloMessageReceiver(self), name: "PlayloNative")
        NSLayoutConstraint.activate([web.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor), web.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor), web.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), web.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)])
        activity.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(activity); NSLayoutConstraint.activate([activity.centerXAnchor.constraint(equalTo: view.centerXAnchor), activity.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
        web.load(URLRequest(url: initialURL))
    }
    func resumeWeb() { if let url = web?.url, PlayloConfig.trusted(url) { web.evaluateJavaScript("dispatchEvent(new Event('playlo:resume'))", completionHandler: nil) } }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); resumeWeb() }
    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) { if response.isForMainFrame, let http = response.response as? HTTPURLResponse, http.statusCode >= 400 { decisionHandler(.cancel); showError() } else { decisionHandler(.allow) } }
    @objc private func menu() { navigationController?.popViewController(animated: true) }
    @objc private func reload() { let alert = UIAlertController(title: "Scherm opnieuw laden?", message: "Een lopend lokaal spel kan opnieuw beginnen.", preferredStyle: .alert); alert.addAction(UIAlertAction(title: "Doorgaan", style: .cancel)); alert.addAction(UIAlertAction(title: "Herladen", style: .default) { [weak self] _ in self?.web.reload() }); present(alert, animated: true) }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        let authentication = url.path.hasPrefix("/signin-with-chatgpt") || url.path.hasPrefix("/signout-with-chatgpt") || url.path == "/native-signin"
        if PlayloConfig.trusted(url) && !authentication {
            if action.targetFrame == nil { if action.sourceFrame.isMainFrame { webView.load(action.request) }; decisionHandler(.cancel) } else { decisionHandler(.allow) }
        } else {
            if (action.targetFrame?.isMainFrame == true || action.targetFrame == nil) && url.scheme == "https" { UIApplication.shared.open(url) }
            decisionHandler(.cancel)
        }
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { errorPanel?.removeFromSuperview(); errorPanel = nil; activity.startAnimating() }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        activity.stopAnimating(); debugProgress("document-loaded")
        #if DEBUG
        if CommandLine.arguments.contains("--playlo-offline-smoke") {
            let script = #"""
            let smokeStep='initial';
            try {
            for(let i=0;i<120&&document.documentElement.dataset.playloNetwork!=='online';i++)await new Promise(r=>setTimeout(r,250));
            // Pace the UI journey on the real native HTTP bridge; allow background reads to finish between 29 immediate game switches.
            const nativeFetch=window.fetch.bind(window);let pendingAPI=0;
            window.fetch=async(...args)=>{const input=args[0],path=new URL(typeof input==='string'?input:input instanceof URL?input.href:input.url,location.href).pathname,tracked=path.startsWith('/api/');if(tracked)pendingAPI++;try{return await nativeFetch(...args)}finally{if(tracked)pendingAPI--}};
            const post=async(path,data)=>{const r=await fetch('/api/'+path,{method:'POST',headers:{'content-type':'application/json','idempotency-key':crypto.randomUUID()},body:JSON.stringify(data)});const d=await r.json();if(!r.ok)throw Error(JSON.stringify(d));return d};
            const manifest=await (await fetch('/bundle-manifest.json')).json(),session=await post('session',{}),board=await post('game',{action:'practice',name:'Cloud QA'});
            const escape=await post('halloween/runs',{gameId:'escape',mode:'practice',room:0,route:0});
            const wait=async(find)=>{for(let i=0;i<160;i++){const value=find();if(value)return value;await new Promise(r=>setTimeout(r,125))}throw Error('UI timeout: '+find.toString())};
            const button=(name)=>[...document.querySelectorAll('button')].find(b=>b.textContent.trim()===name&&!b.disabled&&b.getClientRects().length>0&&getComputedStyle(b).visibility!=='hidden');
            await wait(()=>document.querySelector('.onboarding input[maxlength="18"]'));
            (await wait(()=>document.querySelector('.onboarding section>button'))).click();
            (await wait(()=>document.querySelector('.homeQuickLinks a[href="/?collection=all"]'))).click();
            const graphics=[];
            for(const name of ['Rendier Express','Schoorsteen Sprint']){
              await wait(()=>pendingAPI===0);const card=await wait(()=>[...document.querySelectorAll('.catalogGrid article')].find(a=>a.querySelector('h2')?.textContent.trim()===name));card.querySelector('button').click();
              (await wait(()=>button('Start de route'))).click();
              const canvas=await wait(()=>{const c=document.querySelector('.winterCanvas');return c&&Number(c.dataset.tick)>20?c:null});
              const webgl=!!canvas.getContext('webgl2');if(!webgl)throw Error(name+': no WebGL2 renderer');graphics.push({name,webgl2:webgl,ticks:Number(canvas.dataset.tick)});
              (await wait(()=>document.querySelector('button[aria-label="Terug naar spellen"]'))).click();
            }
            for(const name of ['Lava Run','Castle Siege','Balloon Battle','Floor Drop','Crown Thief','Laser Escape','Traffic Panic','Falling Stuff','Grab and Run','King of the Hill','Delivery Disaster']){
              await wait(()=>pendingAPI===0);const card=await wait(()=>[...document.querySelectorAll('.catalogGrid article')].find(a=>a.querySelector('h2')?.textContent.trim()===name));card.querySelector('button').click();
              (await wait(()=>document.querySelector('.playModeCards>button'))).click();
              (await wait(()=>document.querySelector('.actionSetup>button:not([disabled])'))).click();
              const canvas=await wait(()=>{const c=document.querySelector('.actionCampaign[data-stage=play] .action3DWorld canvas');return c&&c.dataset.tick!==undefined?c:null});
              (await wait(()=>document.querySelector('.tacticalDirections button:not([disabled]),.actionControl-special:not([disabled])'))).click();
              await wait(()=>Number(canvas.dataset.tick)>0);const webgl=!!canvas.getContext('webgl2');if(!webgl)throw Error(name+': no WebGL2 renderer');graphics.push({name,webgl2:webgl,ticks:Number(canvas.dataset.tick)});
              document.querySelector('.actionCampaign>header>button').click();(await wait(()=>document.querySelector('.actionPause section>button:last-child'))).click();
            }
            {
              await wait(()=>pendingAPI===0);const card=await wait(()=>[...document.querySelectorAll('.catalogGrid article')].find(a=>a.querySelector('h2')?.textContent.trim()==='Pumpkin Dash'));card.querySelector('button').click();
              (await wait(()=>document.querySelector('.pumpkinStart'))).click();
              const canvas=await wait(()=>{const c=document.querySelector('.pumpkinWorld3D canvas');return c&&Number(c.dataset.tick)>10?c:null});const webgl=!!canvas.getContext('webgl2');if(!webgl)throw Error('Pumpkin Dash: no WebGL2');graphics.push({name:'Pumpkin Dash',webgl2:webgl,ticks:Number(canvas.dataset.tick)});
              (await wait(()=>document.querySelector('.pumpkinEndless>header>button'))).click();
            }
            const settle=()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));
            const tap=async(name)=>{smokeStep=smokeStep.split(' → ')[0]+' → '+name;(await wait(()=>button(name))).click();await settle()};
            const take=async()=>{(await wait(()=>[...document.querySelectorAll('button')].find(b=>/^Ik ben /.test(b.textContent.trim())&&!b.disabled))).click();await settle()};
            const openCard=async(name)=>{smokeStep=name;await wait(()=>pendingAPI===0);const card=await wait(()=>[...document.querySelectorAll('.catalogGrid article')].find(a=>a.querySelector('h2')?.textContent.trim()===name));card.querySelector('button').click();await settle()};
            const setField=(input,value)=>{Object.getOwnPropertyDescriptor(input.tagName==='TEXTAREA'?HTMLTextAreaElement.prototype:HTMLInputElement.prototype,'value').set.call(input,value);input.dispatchEvent(new Event('input',{bubbles:true}))};
            const fillPlayers=async()=>{await wait(()=>document.querySelector('.playerNames input'));const count=document.querySelectorAll('.playerNames input').length;for(let i=0;i<count;i++){setField(document.querySelectorAll('.playerNames input')[i],['Ada','Bram','Cleo','Daan','Eva'][i]||'Speler '+i);await settle()}};
            const selectValue=async(value)=>{const select=await wait(()=>[...document.querySelectorAll('select')].find(s=>[...s.options].some(o=>o.value===value)));select.value=value;select.dispatchEvent(new Event('change',{bubbles:true}));await settle()};
            const localMode=async()=>{(await wait(()=>[...document.querySelectorAll('.playModeCards button')].find(b=>/LOKAAL|SOLO/.test(b.textContent)&&!b.disabled))).click();await settle()};
            const recordMesh=async(name,selector='.decisionMeshes')=>{const canvas=await wait(()=>{const c=document.querySelector(selector);return c&&(Number(c.dataset.frame)>0||c.dataset.distance!==undefined||selector.includes('bombObject'))?c:null});if(!canvas.getContext('webgl2'))throw Error(name+': no live WebGL2');graphics.push({name,webgl2:true,ticks:Math.max(1,Number(canvas.dataset.frame??canvas.dataset.distance??1))})};
            const leave=async()=>{for(let i=0;i<6;i++){if(document.querySelector('.catalogGrid'))return;const exit=[...document.querySelectorAll('button')].find(b=>b.closest('header,nav')&&/^(←|Terug)/.test(b.textContent.trim())&&!b.disabled);if(!exit)throw Error('No exit from '+document.querySelector('main')?.className);exit.click();await settle();const stop=button('Stoppen');if(stop){stop.click();await settle()}}await wait(()=>document.querySelector('.catalogGrid'))};
            window.confirm=()=>true;
            for(const name of ['Minority Wins','Most Likely To','Secret Missions','Bet On Your Friend']){
              await openCard(name);await localMode();await fillPlayers();if(name==='Secret Missions')await selectValue('extra');await tap('Start de match');await take();await recordMesh(name);await leave();
            }
            for(const name of ['Who Said It','Story Liar','Meme Me','Undercover']){
              await openCard(name);await localMode();await fillPlayers();if(name==='Undercover')await selectValue('oral');await tap('Start de party');
              for(let i=0;i<3;i++){await take();if(name==='Undercover')await tap('Onthouden en verbergen');else{const field=await wait(()=>document.querySelector('.partyWritingDesk textarea'));setField(field,'Een verhaal van '+['Ada','Bram','Cleo'][i]);await settle();await tap('Opslaan en verbergen')}}
              await tap('Begin de geheime stemronde');await take();if(button('Beurt afronden en verbergen')){await tap('Beurt afronden en verbergen');await take()}await recordMesh(name);await leave();
            }
            await openCard('Freeze');await localMode();await fillPlayers();await tap('Start de match');await tap('Start mijn beurt');{
              const hold=await wait(()=>document.querySelector('.freezeHold'));hold.focus();hold.dispatchEvent(new KeyboardEvent('keydown',{key:' ',bubbles:true}));await wait(()=>Number(document.querySelector('.freezeWorld3D')?.dataset.distance)>0);hold.dispatchEvent(new KeyboardEvent('keyup',{key:' ',bubbles:true}));await recordMesh('Freeze','.freezeWorld3D');await leave();
            }
            await openCard('Wrong Button');await localMode();await fillPlayers();await tap('Start de match');await tap('Start mijn beurt');await recordMesh('Wrong Button','.trapCompass .decisionMeshes');document.querySelector('.trapCompass button:not([disabled])').click();await wait(()=>document.querySelector('[data-stage=reveal]'));await leave();
            await openCard('Bomb Pass');(await wait(()=>[...document.querySelectorAll('button')].find(b=>/1 telefoon doorgeven/.test(b.textContent)))).click();(await wait(()=>document.querySelector('.bombSetup .bombPrimary:not([disabled])'))).click();await recordMesh('Bomb Pass','.bombObject3D canvas');await leave();
            await openCard('Maffia');(await wait(()=>[...document.querySelectorAll('button')].find(b=>/Samen op één telefoon/.test(b.textContent)))).click();await tap('Start Maffia');for(let i=0;i<5;i++){await take();await tap('Begrepen · verberg en geef door')}for(let i=0;i<5;i++){await take();if(document.querySelector('.decisionMeshes')){await recordMesh('Maffia');break}await tap('Geen actie · telefoon doorgeven');if(button('Bevestig'))await tap('Bevestig')}await leave();
            await openCard('Wie is het monster?');await localMode();await tap('Start partij');for(let i=0;i<4;i++){await take();await tap('Bedek en geef door')}for(let i=0;i<4;i++){await take();const clues=await wait(()=>document.querySelectorAll('.monsterClueGrid button').length?document.querySelectorAll('.monsterClueGrid button'):null);clues[0].click();await settle();document.querySelectorAll('.monsterClueGrid button')[1].click();await settle();await tap('Verstuur en geef door')}await tap('Klaar met bespreken');await take();await recordMesh('Wie is het monster?');await leave();
            await openCard('Wie overleeft het spookhuis?');await tap('Speel');await tap('Start');await recordMesh('Wie overleeft het spookhuis?');await leave();
            await openCard('Trick or Trap?');await tap('Risicotocht · kansen en buit');await tap('Start');await recordMesh('Trick or Trap?');await leave();

            return {status:graphics.length===29&&manifest.games.length===34&&!!board.game&&!!escape.run&&!session.account?'PASS':'FAIL',graphics,isSecureContext,games:manifest.games.length,version:manifest.version,studio:manifest.studio,guestSession:!session.account,network:document.documentElement.dataset.playloNetwork,apiOrigin:(await(await fetch('/app-online.json')).json()).apiOrigin,board:!!board.game,escape:!!escape.run,url:location.origin};
            } catch(error) { return {status:'FAIL',step:smokeStep,body:document.body.innerText.slice(0,3500),message:String(error),stack:error.stack,screen:document.querySelector('main')?.className,buttons:[...document.querySelectorAll('button')].map(b=>b.textContent.trim()).slice(0,20)}; }
            """#
            webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { result in
                self.debugProgress("smoke-finished")
                let report: Any
                switch result { case .success(let value): report = value; case .failure(let error): report = ["status":"FAIL", "error":error.localizedDescription] }
                if let data = try? JSONSerialization.data(withJSONObject: report, options: .prettyPrinted), let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first { try? data.write(to: directory.appendingPathComponent("Playlo-native-smoke.json")) }
            }
        }
        #endif
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if (error as NSError).code != NSURLErrorCancelled { showError() } }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { showError() }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { showError() }
    private func showError() {
        activity.stopAnimating(); errorPanel?.removeFromSuperview()
        let label = UILabel(); label.text = "De ingebouwde spellen konden niet laden.\nOpen het scherm opnieuw. Je gegevens blijven op dit apparaat."; label.numberOfLines = 0; label.textColor = .white; label.font = .preferredFont(forTextStyle: .title3)
        let retry = UIButton(type: .system); retry.setTitle("Opnieuw proberen", for: .normal); retry.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true; retry.addAction(UIAction { [weak self] _ in guard let self else { return }; self.web.load(URLRequest(url: self.web.url.flatMap { PlayloConfig.trusted($0) ? $0 : nil } ?? self.initialURL)) }, for: .touchUpInside)
        let panel = UIStackView(arrangedSubviews: [label, retry]); panel.axis = .vertical; panel.spacing = 20; panel.isLayoutMarginsRelativeArrangement = true; panel.layoutMargins = UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24); panel.backgroundColor = view.backgroundColor; panel.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(panel); NSLayoutConstraint.activate([panel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor), panel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor), panel.centerYAnchor.constraint(equalTo: view.centerYAnchor)]); errorPanel = panel
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let source = message.frameInfo.securityOrigin
        guard message.frameInfo.isMainFrame, source.protocol == PlayloConfig.origin.scheme, source.host.lowercased() == PlayloConfig.origin.host?.lowercased(), source.port == PlayloConfig.origin.port, let url = web.url, PlayloConfig.trusted(url), let raw = message.body as? String, raw.utf8.count <= 6 * 1024 * 1024, let data = raw.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if object["type"] as? String == "youtubeClip" {
            guard let id = object["videoId"] as? String, id.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil else { return }
            navigationController?.pushViewController(PlayloYouTubeScreen(videoId: id), animated: true); return
        }
        if object["type"] as? String == "api" {
            AppApiClient.shared.send(object) { [weak self] response in DispatchQueue.main.async { guard let self,let url = self.web?.url,PlayloConfig.trusted(url),let data = try? JSONSerialization.data(withJSONObject:response),let json = String(data:data,encoding:.utf8) else { return };self.web.evaluateJavaScript("dispatchEvent(new CustomEvent('playlo:api-response',{detail:"+json+"}))",completionHandler:nil) } };return
        }
        guard object["type"] as? String == "save",let encoded = object["data"] as? String,let bytes = Data(base64Encoded:encoded),bytes.count <= 4*1024*1024 else { return }
        let name = String((object["name"] as? String ?? "Playlo-export.html").replacingOccurrences(of: "[\\\\/\\p{Cc}]", with: "_", options: .regularExpression).prefix(100))
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent(name.isEmpty ? "Playlo-export.html" : name); try bytes.write(to: file); exportURL = file
            let share = UIActivityViewController(activityItems: [file], applicationActivities: nil); share.popoverPresentationController?.sourceView = view; share.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            share.completionWithItemsHandler = { [weak self] _, _, _, _ in try? FileManager.default.removeItem(at: directory); self?.exportURL = nil }; present(share, animated: true)
        } catch { showError() }
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) { let alert = UIAlertController(title: "Playlo", message: message, preferredStyle: .alert); alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() }); present(alert, animated: true) }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) { let alert = UIAlertController(title: "Playlo", message: message, preferredStyle: .alert); alert.addAction(UIAlertAction(title: "Annuleren", style: .cancel) { _ in completionHandler(false) }); alert.addAction(UIAlertAction(title: "Doorgaan", style: .default) { _ in completionHandler(true) }); present(alert, animated: true) }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) { let alert = UIAlertController(title: "Playlo", message: prompt, preferredStyle: .alert); alert.addTextField { $0.text = defaultText }; alert.addAction(UIAlertAction(title: "Annuleren", style: .cancel) { _ in completionHandler(nil) }); alert.addAction(UIAlertAction(title: "Bewaren", style: .default) { _ in completionHandler(alert.textFields?.first?.text) }); present(alert, animated: true) }
    deinit { web?.configuration.userContentController.removeScriptMessageHandler(forName: "PlayloNative"); if let file = exportURL { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) } }
}
