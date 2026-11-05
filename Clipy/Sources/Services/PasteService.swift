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
        guard !pasteboardHoldsSameText(pasteboard, as: string) else { return }
        write(text: string, to: pasteboard)
    }

    func copyToPasteboard(with clip: CPYClip) {
        lock.lock(); defer { lock.unlock() }

        guard let data = NSKeyedUnarchiver.unarchiveObject(withFile: clip.dataPath) as? CPYClipData else { return }

        let pasteboard = NSPasteboard.general
        // 纯文本用一次 writeObjects 写入。declareTypes 加多次 set* 会让剪贴板在两次调用之间
        // 处于「类型已声明、数据尚未写入」的状态，其它监听剪贴板的进程若在该窗口内读取，
        // 会读到不完整的 item（NSPasteboard 内部类型缓存数组越界，抛 NSRangeException）。
        if data.isTextOnly {
            guard !pasteboardHoldsSameText(pasteboard, as: data.stringValue) else { return }
            write(text: data.stringValue, to: pasteboard)
            return
        }

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

// MARK: - Pasteboard
fileprivate extension PasteService {
    /// 单次写入，避免剪贴板出现「类型已声明但数据为空」的中间状态。
    /// NSPasteboard 会把 public.utf8-plain-text 自动补上 NSStringPboardType 别名，行为与旧路径一致。
    func write(text: String, to pasteboard: NSPasteboard) {
        let item = NSPasteboardItem()
        guard item.setString(text, forType: .string) else { return }
        pasteboard.writeObjects([item])
    }

    /// 剪贴板里已经是同一段纯文本时，不再重写。
    /// 每次写入都会让 changeCount 变化，正在轮询剪贴板的其它进程（如小米互联服务的
    /// dist_clipboard）会因此多一次读取机会，跳过可显著减少它们的暴露次数。
    func pasteboardHoldsSameText(_ pasteboard: NSPasteboard, as text: String) -> Bool {
        guard !text.isEmpty, pasteboard.string(forType: .string) == text else { return false }
        // 只有当前剪贴板里「全是纯文本类型」才跳过。带 public.html / 图片 / RTF 等更重的内容时不跳过，
        // 否则会把富文本粘出去，和这条纯文本历史记录的粘贴结果不一致。
        let textTypes: Set<NSPasteboard.PasteboardType> = [
            .string, .publicText, .utf8PlainText, .utf16PlainText, .deprecatedString,
            NSPasteboard.PasteboardType(rawValue: "public.plain-text"),
            NSPasteboard.PasteboardType(rawValue: "public.utf16-plain-text"),
            NSPasteboard.PasteboardType(rawValue: "com.apple.traditional-mac-plain-text")
        ]
        return (pasteboard.types ?? []).allSatisfy { textTypes.contains($0) }
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
