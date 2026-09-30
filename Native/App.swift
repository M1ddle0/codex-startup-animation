import AppKit
import WebKit
import UniformTypeIdentifiers

// A short-lived, local-only player. No CDP, theme daemon, or changes to Codex.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    private var window: NSWindow!
    private var webView: WKWebView!
    private var target: NSRunningApplication?
    private var launchMode = false
    private var animationDone = false
    private var opening = false
    private var terminating = false
    private var watchdog: Timer?
    private let smokeTest = CommandLine.arguments.contains("--smoke-test")
    private var snapshotPath: String? {
        guard let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[i + 1]
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu()
        let item = NSMenuItem(); menu.addItem(item)
        let appMenu = NSMenu(); item.submenu = appMenu
        appMenu.addItem(withTitle: "退出爱弥斯启动动画", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = menu

        let available = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(1000, available.width - 80, (available.height - 80) * 1.52)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: width / 1.52), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "爱弥斯 · 12 秒启动动画"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.delegate = self
        window.center()

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController.add(self, name: "launcher")
        if smokeTest {
            let profileScript = """
            window.__startupProfile={draw:[],gaps:[],last:0};
            const nativeRAF=window.requestAnimationFrame.bind(window);
            window.requestAnimationFrame=callback=>nativeRAF(now=>{
              const start=performance.now();callback(now);
              const elapsed=Number(document.querySelector('.window')?.dataset.elapsed||0),p=window.__startupProfile;
              if(elapsed>=4&&elapsed<=5.1){p.draw.push(performance.now()-start);if(p.last)p.gaps.push(now-p.last);p.last=now;}
            });
            """
            configuration.userContentController.addUserScript(WKUserScript(source: profileScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        webView = WKWebView(frame: window.contentView!.bounds, configuration: configuration)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        window.contentView!.addSubview(webView)
        guard let resources = Bundle.main.resourceURL else { NSApp.terminate(nil); return }
        let page = resources.appendingPathComponent("web/index.html")
        webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // An unresponsive renderer must never leave a blocking splash indefinitely.
        watchdog = Timer.scheduledTimer(withTimeInterval: 25, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.launchMode { self.revealAndQuit() }
            else if self.smokeTest { print("SMOKE FAIL: renderer timeout"); NSApp.terminate(nil) }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let action = message.body as? String else { return }
        switch action {
        case "ready":
            print("PLAYER READY")
            if smokeTest { webView.evaluateJavaScript("window.addEventListener('error', event => window.webkit.messageHandlers.launcher.postMessage('SMOKE JS ERROR: ' + event.message))") }
            if CommandLine.arguments.contains("--settings") { webView.evaluateJavaScript("window.launcherUI.openSettings()") }
            if CommandLine.arguments.contains("--launch") && !smokeTest { startLaunch() }
            if let path = snapshotPath {
                for (index, seconds) in [0.5, 3.0, 4.22, 4.34, 4.55, 6.1, 7.5].enumerated() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in self?.snapshot(to: path.replacingOccurrences(of: ".png", with: "-\(index).png")) }
                }
            }
        case "launch": if !smokeTest { startLaunch() }
        case "reveal":
            if launchMode { target?.unhide() }
        case "complete":
            animationDone = true
            print("ANIMATION COMPLETE")
            if launchMode { finishIfReady() }
            else if smokeTest {
                webView.evaluateJavaScript("JSON.stringify({elapsed:document.querySelector('.window').dataset.elapsed,playing:document.querySelector('.window').dataset.playing,completed:document.querySelector('.window').dataset.completed,imageWidth:document.querySelector('.artwork').naturalWidth,avatarWidth:document.querySelector('.avatar').naturalWidth,trace:document.querySelector('.line-art').dataset,profile:window.__startupProfile})") { result, error in
                    print("SMOKE RESULT: \(result ?? "missing") \(error?.localizedDescription ?? "")")
                    NSApp.terminate(nil)
                }
            }
        case "assetError":
            print("ASSET ERROR")
            if launchMode { revealAndQuit() }
            else if smokeTest { NSApp.terminate(nil) }
        default:
            if smokeTest && action.hasPrefix("SMOKE JS ERROR:") { print(action); NSApp.terminate(nil) }
        }
    }

    private func startLaunch() {
        guard !opening && !launchMode else { return }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") else {
            reportError("没有找到已安装的 Codex / ChatGPT 桌面应用。"); return
        }
        launchMode = true; opening = true; animationDone = false
        window.level = .floating
        webView.evaluateJavaScript("window.launcherUI.beginLaunch()")
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 25, repeats: false) { [weak self] _ in self?.revealAndQuit() }
        if let existing = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").first {
            target = existing
            existing.hide()
            print("CODEX REUSED; hidden=\(existing.isHidden)")
            opening = false
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { [weak self] app, error in
            DispatchQueue.main.async {
                guard let self else { app?.unhide(); return }
                self.opening = false
                if let error {
                    self.launchMode = false
                    self.window.level = .normal
                    self.watchdog?.invalidate()
                    self.reportError("启动失败：\(error.localizedDescription)")
                    return
                }
                self.target = app
                if self.terminating { app?.unhide(); app?.activate(options: [.activateAllWindows]); return }
                app?.hide()
                self.finishIfReady()
            }
        }
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .webP]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { result in completionHandler(result == .OK ? panel.urls : nil) }
    }

    private func finishIfReady() {
        guard animationDone else { return }
        guard !opening, let target, !target.isTerminated else {
            webView.evaluateJavaScript("window.launcherUI.waiting()")
            return
        }
        // LaunchServices completion confirms app launch, not renderer/chat readiness.
        revealAndQuit()
    }

    private func revealAndQuit() {
        guard !terminating else { return }
        terminating = true
        watchdog?.invalidate()
        target?.unhide()
        target?.activate(options: [.activateAllWindows])
        print("HANDOFF; hidden=\(target?.isHidden.description ?? "no target"); terminated=\(target?.isTerminated.description ?? "no target")")
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            self.window.animator().alphaValue = 0
        }, completionHandler: { NSApp.terminate(nil) })
    }

    private func reportError(_ message: String) {
        let data = try! JSONSerialization.data(withJSONObject: [message])
        let json = String(data: data, encoding: .utf8)!
        webView.evaluateJavaScript("window.launcherUI.error(\(json)[0])")
    }

    private func snapshot(to path: String) {
        webView.takeSnapshot(with: nil) { image, error in
            guard let data = image?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) else {
                print("SNAPSHOT ERROR: \(error?.localizedDescription ?? "no image")"); return
            }
            do { try png.write(to: URL(fileURLWithPath: path)); print("SNAPSHOT SAVED") }
            catch { print("SNAPSHOT ERROR: \(error.localizedDescription)") }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.request.url?.isFileURL == true ? .allow : .cancel)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if launchMode { revealAndQuit() }
        else { print("RENDERER TERMINATED"); NSApp.terminate(nil) }
    }
    func windowWillClose(_ notification: Notification) { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        terminating = true
        watchdog?.invalidate()
        if launchMode { target?.unhide() }
        webView?.stopLoading()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "launcher")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
