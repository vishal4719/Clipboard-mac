import AppKit

struct AppVersionInfo: Codable {
    let version: String
    let downloadUrl: String
    let releaseNotes: String?
}

class UpdateManager {
    static let shared = UpdateManager()
    
    // REPLACE THIS with your actual GitHub username and repo name after creating it
    private let versionFileUrl = "https://raw.githubusercontent.com/vishalgupta/Clipboard/main/version.json"
    
    func checkForUpdates(quietly: Bool = true) {
        guard let url = URL(string: versionFileUrl) else { return }
        
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let data = data, error == nil else {
                if !quietly {
                    print("Error fetching update info: \(String(describing: error))")
                }
                return
            }
            
            do {
                let info = try JSONDecoder().decode(AppVersionInfo.self, from: data)
                DispatchQueue.main.async {
                    self?.handleVersionInfo(info, quietly: quietly)
                }
            } catch {
                if !quietly {
                    print("Error decoding update info: \(error)")
                }
            }
        }
        task.resume()
    }
    
    private func handleVersionInfo(_ info: AppVersionInfo, quietly: Bool) {
        guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else { return }
        
        if isNewerVersion(remote: info.version, local: currentVersion) {
            showUpdateAlert(item: info)
        } else if !quietly {
            // Optional: User manually checked, so tell them they are up to date
             print("App is up to date")
        }
    }
    
    private func isNewerVersion(remote: String, local: String) -> Bool {
        return remote.compare(local, options: .numeric) == .orderedDescending
    }
    
    private func showUpdateAlert(item: AppVersionInfo) {
        let alert = NSAlert()
        alert.messageText = "New Version Available"
        alert.informativeText = "Version \(item.version) is available.\n\n\(item.releaseNotes ?? "A new update has been released.")"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Cancel")
        
        // Ensure alert pops up in front of everything
        NSApp.activate(ignoringOtherApps: true)
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: item.downloadUrl) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
