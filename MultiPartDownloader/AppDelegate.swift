//
//  AppDelegate.swift
//  MultiPartDownloader
//
//  Created by Neeraj Singh on 3/18/20.
//  Copyright © 2020 Neeraj Singh. All rights reserved.
//

import Cocoa

enum SampleURL: String {
    case smallWWDCVideo = "https://devstreaming-cdn.apple.com/videos/wwdc/2019/248ts94v3ev4q5/248/248_sd_creating_an_accessible_reading_experience.mp4"
    case bigWWDCVideo = "https://devstreaming-cdn.apple.com/videos/wwdc/2019/410p24ercmpgj258x/410/410_hd_creating_swift_packages.mp4"
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSTextFieldDelegate {

    @IBOutlet weak var window: NSWindow!
    var downloader: MultiPartDownload?

    @IBOutlet weak var urlTextField: NSTextField!
    @IBOutlet weak var downloadButton: NSButton!
    @IBOutlet weak var label: NSTextField!
    @IBOutlet weak var indicator: NSProgressIndicator!
    @IBOutlet weak var bigSampleLabel: NSTextField!
    @IBOutlet weak var smallSampleLabel: NSTextField!
    @IBOutlet weak var bigSampleButton: NSButton!
    @IBOutlet weak var smallSampleButton: NSButton!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
        bigSampleLabel.stringValue = SampleURL.bigWWDCVideo.rawValue
        smallSampleLabel.stringValue = SampleURL.smallWWDCVideo.rawValue
        window.makeFirstResponder(urlTextField)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
    
    func showMessage(_ message: String) {
        let alert = NSAlert()
        alert.informativeText = message
        alert.messageText = "Error"
        alert.runModal()        
    }

    @IBAction func startDownload(_ sender: Any) {
        guard let url = downloadURL else {
            showMessage("Please Enter valid URL to download")
            window.makeFirstResponder(urlTextField)
            return
        }
        
        guard let scheme = url.scheme?.lowercased(), scheme.contains("http") else {
            showMessage("Please Enter valid HTTP URL to download")
            window.makeFirstResponder(urlTextField)
            return
        }
        
        let downloader = MultiPartDownload(url)
        self.downloader = downloader
        updateUI(true)
        downloader.start {[weak self] (url, error) in
            DispatchQueue.main.async { [weak self] in
                guard let strongSelf = self else { return }
                if let error = error {
                    strongSelf.showMessage("Error: \(error)")
                }
                strongSelf.downloadFinished(url)
            }
        }
    }
    
    func updateUI(_ started: Bool) {
        downloadButton.isEnabled = !started
        urlTextField.isEnabled = !started
        bigSampleButton.isEnabled = !started
        smallSampleButton.isEnabled = !started

        label.stringValue = ""
        if started {
            indicator.startAnimation(self)
        } else {
            indicator.stopAnimation(self)
        }
    }
    
    func downloadFinished(_ url: URL?) {
        updateUI(false)
        if let fileURL = url {
            label.stringValue = fileURL.path
            var folder = fileURL
            folder.deleteLastPathComponent()
            NSWorkspace.shared.open(folder)
            NSWorkspace.shared.open(fileURL)
        }
    }
    
    var downloadURL: URL? {
        let value = urlTextField.stringValue
        return URL(string: value)
    }
    
    @IBAction func useSampleURL(_ sender: Any) {
        guard let button = sender as? NSButton else {
            return
        }
        
        if button == bigSampleButton {
            urlTextField.stringValue = bigSampleLabel.stringValue
        } else if button == smallSampleButton {
            urlTextField.stringValue = smallSampleLabel.stringValue
        }
    }
}

