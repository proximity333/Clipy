//
//  CPYClipData.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2015/06/21.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Cocoa
import SwiftHEXColors

final class CPYClipData: NSObject {

    // MARK: - Properties
    fileprivate let kTypesKey       = "types"
    fileprivate let kStringValueKey = "stringValue"
    fileprivate let kRTFDataKey     = "RTFData"
    fileprivate let kPDFKey         = "PDF"
    fileprivate let kFileNamesKey   = "filenames"
    fileprivate let kURLsKey        = "URL"
    fileprivate let kImageKey       = "image"

    var types          = [NSPasteboard.PasteboardType]()
    var fileNames      = [String]()
    var URLs           = [String]()
    var stringValue    = ""
    var RTFData: Data?
    var PDF: Data?
    var image: NSImage?

    override var hash: Int {
        // Pasteboard type order is not stable for some system file copy flows.
        // Hash against a normalized type set so repeated copies of the same item dedupe reliably.
        var hash = types.map { $0.rawValue }.sorted().joined(separator: "|").hash
        if let image = self.image, let imageData = image.tiffRepresentation {
            hash ^= CPYClipData.hashData(imageData)
        } else if let image = self.image, let pngData = image.pngData {
            hash ^= CPYClipData.hashData(pngData)
        } else if let image = self.image {
            hash ^= image.hash
        }
        if !fileNames.isEmpty {
            fileNames.forEach { hash ^= $0.hash }
        } else if !self.URLs.isEmpty {
            URLs.forEach { hash ^= $0.hash }
        } else if let pdf = PDF {
            hash ^= pdf.count
        } else if !stringValue.isEmpty {
            hash ^= stringValue.hash
        }
        if let data = RTFData {
            hash ^= data.count
        }
        return hash
    }
    var primaryType: NSPasteboard.PasteboardType? {
        return types.first
    }
    var isOnlyStringType: Bool {
        return types == [.deprecatedString]
    }
    var hasMeaningfulContent: Bool {
        if !stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if RTFData != nil || PDF != nil || image != nil { return true }
        if !fileNames.isEmpty || !URLs.isEmpty { return true }
        return false
    }
    var titleText: String {
        let trimmedString = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedString.isEmpty {
            return trimmedString
        }
        if let fileName = fileNames.first {
            let path = NSString(string: fileName).expandingTildeInPath
            let displayName = FileManager.default.displayName(atPath: path)
            if !displayName.isEmpty {
                return displayName
            }
            return URL(fileURLWithPath: path).lastPathComponent
        }
        if let urlString = URLs.first {
            return urlString
        }
        if PDF != nil {
            return "(PDF)"
        }
        return ""
    }
    var thumbnailImage: NSImage? {
        let width: CGFloat = 100
        let height: CGFloat = 32

        if let image = image, fileNames.isEmpty {
            // Image only data
            return image.resizeImage(width, height)
        } else if let fileName = fileNames.first, let path = fileName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed), let url = URL(string: path) {
             // In the case of the local file correct data is not included in the image variable
             // Judge the image from the path and create a thumbnail
            switch url.pathExtension.lowercased() {
            case "jpg", "jpeg", "png", "bmp", "tiff":
                return NSImage(contentsOfFile: fileName)?.resizeImage(width, height)
            default: break
            }
        }
        return nil
    }
    var colorCodeImage: NSImage? {
        guard let color = NSColor(hexString: stringValue) else { return nil }
        return NSImage.create(with: color, size: NSSize(width: 20, height: 20))
    }

    private static func hashData(_ data: Data) -> Int {
        var result = data.count
        let step = max(1, data.count / 256)
        for i in Swift.stride(from: 0, to: data.count, by: step) {
            result = result &* 31 &+ Int(data[i])
        }
        return result
    }

    static var availableTypes: [NSPasteboard.PasteboardType] {
        return [.deprecatedString,
                .string,
                .publicText,
                .utf8PlainText,
                .utf16PlainText,
                .deprecatedRTF,
                .deprecatedRTFD,
                .deprecatedPDF,
                .deprecatedFilenames,
                .deprecatedURL,
                .png,
                .tiff,
                .deprecatedTIFF]
    }
    static var availableTypesString: [String] {
        return ["String",
                "String",
                "String",
                "String",
                "String",
                "RTF",
                "RTFD",
                "PDF",
                "Filenames",
                "URL",
                "TIFF",
                "TIFF",
                "TIFF"]
    }
    static var availableTypesDictinary: [NSPasteboard.PasteboardType: String] {
        var availableTypes = [NSPasteboard.PasteboardType: String]()
        zip(CPYClipData.availableTypes, CPYClipData.availableTypesString).forEach { availableTypes[$0] = $1 }
        return availableTypes
    }

    // MARK: - Init
    init(pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) {
        super.init()
        self.types = types
        types.forEach { type in
            switch type {
            case .deprecatedString, .string, .publicText, .utf8PlainText, .utf16PlainText:
                guard let string = pasteboard.string(forType: type) ??
                        pasteboard.string(forType: .string) ??
                        pasteboard.string(forType: .deprecatedString) else { return }
                stringValue = string
            case .deprecatedRTFD:
                RTFData = pasteboard.data(forType: .deprecatedRTFD)
            case .deprecatedRTF where RTFData == nil:
                RTFData = pasteboard.data(forType: .deprecatedRTF)
            case .deprecatedPDF:
                PDF = pasteboard.data(forType: .deprecatedPDF)
            case .deprecatedFilenames:
                guard let filenames = pasteboard.propertyList(forType: .deprecatedFilenames) as? [String] else { return }
                self.fileNames = filenames
            case .deprecatedURL:
                guard let urls = pasteboard.propertyList(forType: .deprecatedURL) as? [String] else { return }
                URLs = urls
            case .png, .tiff, .deprecatedTIFF:
                image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage
            default: break
            }
        }
    }

    init(image: NSImage) {
        self.types = [.deprecatedTIFF]
        self.image = image
    }

    deinit {
        self.RTFData = nil
        self.PDF = nil
        self.image = nil
    }

    // MARK: - NSCoding
    @objc func encodeWithCoder(_ aCoder: NSCoder) {
        aCoder.encode(types.map { $0.rawValue }, forKey: kTypesKey)
        aCoder.encode(stringValue, forKey: kStringValueKey)
        aCoder.encode(RTFData, forKey: kRTFDataKey)
        aCoder.encode(PDF, forKey: kPDFKey)
        aCoder.encode(fileNames, forKey: kFileNamesKey)
        aCoder.encode(URLs, forKey: kURLsKey)
        aCoder.encode(image, forKey: kImageKey)
    }

    @objc required init(coder aDecoder: NSCoder) {
        types = (aDecoder.decodeObject(forKey: kTypesKey) as? [String])?.compactMap { NSPasteboard.PasteboardType(rawValue: $0) } ?? []
        fileNames = aDecoder.decodeObject(forKey: kFileNamesKey) as? [String] ?? [String]()
        URLs = aDecoder.decodeObject(forKey: kURLsKey) as? [String] ?? [String]()
        stringValue = aDecoder.decodeObject(forKey: kStringValueKey) as? String ?? ""
        RTFData = aDecoder.decodeObject(forKey: kRTFDataKey) as? Data
        PDF = aDecoder.decodeObject(forKey: kPDFKey) as? Data
        image = aDecoder.decodeObject(forKey: kImageKey) as? NSImage
        super.init()
    }
}
