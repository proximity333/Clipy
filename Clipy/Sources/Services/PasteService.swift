//
//  PasteService.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/11/23.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation
import Cocoa
import Sauce

final class PasteService {

    // MARK: - Properties
    fileprivate let lock = NSRecursiveLock(name: "com.clipy-app.Clipy.Pastable")
}

// MARK: - Copy
extension PasteService {
    func paste(with clip: CPYClip) {
        guard !clip.isInvalidated else { return }

        AppEnvironment.current.clipService.incrementChangeCount()
        copyToPasteboard(with: clip)
        AppEnvironment.current.clipService.syncChangeCountToPasteboard()
        AppEnvironment.current.clipService.markAsRecentlyUsed(clip)
        paste()
    }

    func copyToPasteboard(with string: String) {
        lock.lock(); defer { lock.unlock() }

        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.deprecatedString], owner: nil)
        pasteboard.setString(string, forType: .deprecatedString)
    }

    func copyToPasteboard(with clip: CPYClip) {
        lock.lock(); defer { lock.unlock() }

        guard let data = NSKeyedUnarchiver.unarchiveObject(withFile: clip.dataPath) as? CPYClipData else { return }

        let pasteboard = NSPasteboard.general
        let types = data.types
        pasteboard.declareTypes(types, owner: nil)
        types.forEach { type in
            switch type {
            case .deprecatedString:
                let pbString = data.stringValue
                pasteboard.setString(pbString, forType: .deprecatedString)
            case .deprecatedRTFD:
                guard let rtfData = data.RTFData else { return }
                pasteboard.setData(rtfData, forType: .deprecatedRTFD)
            case .deprecatedRTF:
                guard let rtfData = data.RTFData else { return }
                pasteboard.setData(rtfData, forType: .deprecatedRTF)
            case .deprecatedPDF:
                guard let pdfData = data.PDF, let pdfRep = NSPDFImageRep(data: pdfData) else { return }
                pasteboard.setData(pdfRep.pdfRepresentation, forType: .deprecatedPDF)
            case .deprecatedFilenames:
                let fileNames = data.fileNames
                pasteboard.setPropertyList(fileNames, forType: .deprecatedFilenames)
            case .deprecatedURL:
                let url = data.URLs
                pasteboard.setPropertyList(url, forType: .deprecatedURL)
            case .png:
                guard let image = data.image, let imageData = image.pngData else { return }
                pasteboard.setData(imageData, forType: .png)
            case .tiff, .deprecatedTIFF:
                guard let image = data.image, let imageData = image.tiffRepresentation else { return }
                pasteboard.setData(imageData, forType: type)
            default: break
            }
        }
    }
}

// MARK: - Paste
extension PasteService {
    func paste() {
        guard AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.inputPasteCommand) else { return }
        // Check Accessibility Permission
        guard AppEnvironment.current.accessibilityService.isAccessibilityEnabled(isPrompt: false) else {
            AppEnvironment.current.accessibilityService.showAccessibilityAuthenticationAlert()
            return
        }

        let vKeyCode = Sauce.shared.keyCode(by: .v)
        DispatchQueue.main.async {
            let source = CGEventSource(stateID: .combinedSessionState)
            // Disable local keyboard events while pasting
            source?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents], state: .eventSuppressionStateSuppressionInterval)
            // Press Command + V
            let keyVDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
            keyVDown?.flags = .maskCommand
            // Release Command + V
            let keyVUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
            keyVUp?.flags = .maskCommand
            // Post Paste Command
            keyVDown?.post(tap: .cgAnnotatedSessionEventTap)
            keyVUp?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}
