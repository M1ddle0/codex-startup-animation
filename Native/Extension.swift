import AppKit

final class ExtensionDelegate: NSObject, NSApplicationDelegate {
    var process: Process?
    func fail(_ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.messageText = "Codex"; alert.informativeText = text
        alert.addButton(withTitle: "知道了"); alert.runModal(); NSApp.terminate(nil)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") else { fail("没有找到官方 Codex / ChatGPT 应用。"); return }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex")
        if CommandLine.arguments.contains("--probe") {
            let result: [String: Any] = ["application": app.path, "running": running.map { Int($0.processIdentifier) }]
            print(String(data: try! JSONSerialization.data(withJSONObject: result), encoding: .utf8)!)
            NSApp.terminate(nil); return
        }
        if let existing = running.first {
            existing.unhide()
            existing.activate(options: [.activateAllWindows])
            NSApp.terminate(nil); return
        }
        // Validate the signed app before executing its bundled runtime.
        let check = Process(); check.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        check.arguments = ["--verify", "--deep", "--strict", app.path]
        do { try check.run(); check.waitUntilExit() } catch { fail("无法检查应用签名：\(error.localizedDescription)"); return }
        guard check.terminationStatus == 0 else { fail("应用签名检查未通过，未启动扩展。"); return }
        let runner = Process(), output = Pipe()
        runner.executableURL = app.appendingPathComponent("Contents/Resources/cua_node/bin/node")
        runner.arguments = [Bundle.main.resourceURL!.appendingPathComponent("web/extension/run.mjs").path, "--bundle", app.path]
        runner.standardOutput = output; runner.standardError = output
        runner.terminationHandler = { [weak self] task in
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "启动失败"
            DispatchQueue.main.async { if task.terminationStatus == 0 { NSApp.terminate(nil) } else { self?.fail(message) } }
        }
        process = runner
        do { try runner.run() } catch { fail("无法运行扩展：\(error.localizedDescription)") }
    }
}
let app = NSApplication.shared
let delegate = ExtensionDelegate()
app.delegate = delegate
app.run()
